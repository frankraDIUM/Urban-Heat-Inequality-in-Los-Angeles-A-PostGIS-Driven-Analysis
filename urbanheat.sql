ALTER TABLE income ALTER COLUMN median_income TYPE NUMERIC USING median_income::NUMERIC;

-- 1. Drop the old income table and recreate with correct types
DROP TABLE IF EXISTS income;
CREATE TABLE income (
  geoid12 TEXT,
  median_income NUMERIC
);

-- 2. Create a temp table to accept the full CSV (only naming the columns we care about, others will be skipped by selecting only these)
CREATE TEMP TABLE temp_csv (
  GEO_ID TEXT,
  S1901_C01_012E TEXT  -- Median income as text to handle "-"
  -- We don't need to define all columns
);

-- 3. Import the cleaned CSV into temp table (select only the two columns we need)
COPY temp_csv(GEO_ID, S1901_C01_012E)
FROM 'I:\GEO DATA ANALYSIS\ACSST5Y2023.S1901_2026-01-02T044336\cleaned_income_la1.csv'  -- Use your exact cleaned CSV path
WITH (FORMAT csv, HEADER true, DELIMITER ',', QUOTE '"');

-- 4. Insert into real income table, handling ALL ACS special values (no ON CONFLICT)
INSERT INTO income (geoid12, median_income)
SELECT
  GEO_ID,
  CASE
    WHEN TRIM(S1901_C01_012E) IN ('-', 'N', '', '(X)', '**') OR S1901_C01_012E IS NULL THEN NULL
    WHEN S1901_C01_012E LIKE '%+%' THEN 275000  -- "250,000+" → 275000 estimate
    WHEN S1901_C01_012E LIKE '%,%' THEN 
      REGEXP_REPLACE(S1901_C01_012E, '[^0-9]', '', 'g')::NUMERIC  -- Remove commas
    ELSE S1901_C01_012E::NUMERIC
  END
FROM temp_csv
WHERE GEO_ID LIKE '1400000US06%';  -- Only LA County tracts

-- 5. Clean up temp table
DROP TABLE IF EXISTS temp_csv;


-- 6. Verify the income table is now populated correctly
SELECT COUNT(*) AS total_rows,
       COUNT(median_income) AS valid_income_rows,
       ROUND(AVG(median_income), 0) AS avg_median_income,
       MIN(median_income) AS min_income,
       MAX(median_income) AS max_income
FROM income;

-- Sample high-income tracts
SELECT geoid12, median_income 
FROM income 
WHERE median_income IS NOT NULL
ORDER BY median_income DESC
LIMIT 10;

ALTER TABLE tracts ADD COLUMN IF NOT EXISTS median_income NUMERIC;


-- Join: extract the 11-digit GEOID from the 20-character geoid12
UPDATE tracts t
SET median_income = i.median_income
FROM income i
WHERE t.full_geoid = SUBSTRING(i.geoid12 FROM 10 FOR 11);

-- Critical check: how many LA tracts got income?
SELECT 
  COUNT(*) AS total_la_tracts,
  COUNT(median_income) AS tracts_with_income,
  ROUND(AVG(median_income), 0) AS avg_income_la,
  MIN(median_income) AS min_income,
  MAX(median_income) AS max_income
FROM tracts;


-- Delete all tracts outside LA County (countyfp = '037')
DELETE FROM tracts 
WHERE countyfp != '037';

-- Or if countyfp is not present, use the full_geoid (starts with '06037')
-- DELETE FROM tracts WHERE full_geoid NOT LIKE '06037%';

-- Vacuum to clean up
VACUUM ANALYZE tracts;

-- Re-check
SELECT 
  COUNT(*) AS la_tracts_now,
  COUNT(median_income) AS with_income,
  ROUND(AVG(median_income), 0) AS avg_income_la
FROM tracts;


-- 1. Compute mean land surface temperature per tract (fixed ROUND)
DROP TABLE IF EXISTS tract_heat_analysis;
CREATE TABLE tract_heat_analysis AS
SELECT 
  t.full_geoid AS geoid,
  t.namelsad AS tract_name,
  t.median_income,
  ROUND(AVG(ss.mean)::numeric, 2) AS mean_lst_celsius  -- Cast to numeric first
FROM tracts t
JOIN lst_raster r ON ST_Intersects(t.geom, r.rast)
CROSS JOIN LATERAL ST_SummaryStats(ST_Clip(r.rast, t.geom), 1, TRUE) ss
GROUP BY t.full_geoid, t.namelsad, t.median_income;



-- Indexes for performance
CREATE INDEX ON tract_heat_analysis(mean_lst_celsius);
CREATE INDEX ON tract_heat_analysis(median_income);

-- Add the quintile column
ALTER TABLE tract_heat_analysis ADD COLUMN IF NOT EXISTS income_quintile INTEGER;

-- Calculate quintiles using a subquery/CTE
WITH ranked AS (
  SELECT 
    geoid,
    NTILE(5) OVER (ORDER BY median_income ASC) AS quintile
  FROM tract_heat_analysis
  WHERE median_income IS NOT NULL
)
UPDATE tract_heat_analysis tha
SET income_quintile = r.quintile
FROM ranked r
WHERE tha.geoid = r.geoid;


-- Final Urban Heat Inequality Result
SELECT 
  income_quintile AS "Income Quintile (1=poorest, 5=richest)",
  COUNT(*) AS "Number of Tracts",
  ROUND(MIN(median_income)::numeric, 0) AS "Min Income ($)",
  ROUND(MAX(median_income)::numeric, 0) AS "Max Income ($)",
  ROUND(AVG(median_income)::numeric, 0) AS "Avg Income ($)",
  ROUND(AVG(mean_lst_celsius)::numeric, 2) AS "Avg LST (°C)"
FROM tract_heat_analysis
WHERE income_quintile IS NOT NULL
GROUP BY income_quintile
ORDER BY income_quintile;


-- Create a view with geometry + results for export
DROP VIEW IF EXISTS vw_heat_by_income;
CREATE VIEW vw_heat_by_income AS
SELECT 
  t.geom,
  tha.geoid,
  tha.tract_name,
  tha.median_income,
  tha.mean_lst_celsius,
  tha.income_quintile
FROM tract_heat_analysis tha
JOIN tracts t ON tha.geoid = t.full_geoid;

-- Quick preview (should return rows)
SELECT income_quintile, ROUND(AVG(mean_lst_celsius), 2) 
FROM vw_heat_by_income 
GROUP BY income_quintile 
ORDER BY income_quintile;