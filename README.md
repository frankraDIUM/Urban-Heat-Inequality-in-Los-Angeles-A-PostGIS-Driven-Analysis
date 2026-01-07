# Urban-Heat-Inequality-in-Los-Angeles-A-PostGIS-Driven-Analysis
This project investigates urban heat inequality in Los Angeles County using geospatial data and PostGIS/SQL. Interact with map on kepler.gl (https://tinyurl.com/mrbwdjsp)



## Project Overview
This project investigates urban heat inequality in Los Angeles County using geospatial data and PostGIS/SQL. The goal was to calculate mean land surface temperature (LST) per census tract, integrate median household income data, classify tracts into income quintiles, and visualize heat exposure disparities. The analysis reveals that lower-income areas experience significantly higher temperatures, highlighting environmental justice issues.

### 1. Data Sourcing and Preparation
- **Census Tracts**: Downloaded 2023 TIGER/Line shapefiles for California from the U.S. Census Bureau (EPSG:4269). Imported into PostGIS using `shp2pgsql` and reprojected to EPSG:4326. Filtered to Los Angeles County (FIPS 037, ~2,498 tracts).
- **Land Surface Temperature (LST) Raster**: Exported mean summer 2023 LST (June-August, Celsius) from Landsat 8/9 via Google Earth Engine. Imported as raster table `lst_raster` using `raster2pgsql`. Handled NODATA values and verified stats (mean ~35–42°C).
- **Median Household Income**: Downloaded ACS 5-Year Estimates (2023, Table S1901) as CSV from Census Bureau. Cleaned special values ("-", "250,000+"), imported into `income` table, and joined to tracts using GEOID (98% match rate).

### 2. PostGIS Database Setup
- Created database `urban_heat_la` with PostGIS and PostGIS Raster extensions.
- Loaded raster and vector data with spatial indexes (GIST) for performance.
- Resolved import issues (NODATA constraints, CRS mismatches).

### 3. Spatial Analysis
- **Mean LST per Tract**: Used spatial join with `ST_Intersects`, `ST_Clip`, and `ST_SummaryStats` to compute average LST per tract. Stored in `tract_heat_analysis` table.
  - Core Query Example:
    ```
    SELECT t.full_geoid AS geoid, AVG(ss.mean)::numeric AS mean_lst_celsius
    FROM tracts t JOIN lst_raster r ON ST_Intersects(t.geom, r.rast)
    CROSS JOIN LATERAL ST_SummaryStats(ST_Clip(r.rast, t.geom), 1, TRUE) ss
    GROUP BY t.full_geoid;
    ```
- **Income Quintiles**: Added `income_quintile` using `NTILE(5)` over median income. Labeled as "Lowest Income" to "Highest Income" for readability.

<div>
  <img src="https://github.com/frankraDIUM/Urban-Heat-Inequality-in-Los-Angeles-A-PostGIS-Driven-Analysis/blob/main/PgAdmin.png"/>
</div> 

### 4. Key Results
- Quintile Analysis Table (Summer 2023 Daytime LST):
  | Income Group          | Number of Tracts | Avg Income ($) | Avg LST (°C) |
  |-----------------------|------------------|----------------|--------------|
  | Lowest Income         | 491              | 48,842         | **48.07**    |
  | Low-Middle Income     | 491              | 69,410         | 47.93        |
  | Middle Income         | 490              | 86,895         | 46.99        |
  | Upper-Middle Income   | 490              | 106,786        | 45.80        |
  | Highest Income        | 490              | 156,652        | **43.31**    |

- **Finding**: Poorest tracts are ~4.8°C hotter than richest, confirming urban heat inequality linked to socioeconomic factors (e.g., less green space in low-income areas).

### 5. Visualization
- Created mappable view `vw_heat_by_income` with geometry, LST, income, and quintiles.
- Exported to GeoJSON and visualized in QGIS:
  - Choropleth map styled with graduated symbology (Oranges ramp: hotter = darker red).
  - Clipped to LA County boundary for focused extent.
  - Added basemap (OpenStreetMap), title, legend, and key finding label.
- Final Map Preview: Shows clear heat islands in central/downtown LA (dark red, lower-income) vs. cooler coastal areas (light orange, higher-income).

QGIS
<div>
  <img src="https://github.com/frankraDIUM/Urban-Heat-Inequality-in-Los-Angeles-A-PostGIS-Driven-Analysis/blob/main/Urban%20LA%202.png"/>
</div> 

### 6. Technical Challenges Overcome
- Raster import errors (NODATA constraints, NaN stats) resolved with PostGIS functions like `ST_SetBandNoDataValue`.
- QGIS loading warnings for views handled by adding unique `id` column.

### Conclusion
This project demonstrates a complete geospatial workflow: data acquisition, PostGIS ETL and analysis, SQL-based statistics, and QGIS visualization. It provides actionable insights into how heat exposure disproportionately affects lower-income communities in LA, supporting policy recommendations for green infrastructure equity.

