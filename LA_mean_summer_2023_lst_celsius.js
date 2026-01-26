// 1. Define Los Angeles area of interest (AOI)
// Use a simple bounding box covering LA city and county.
// You can zoom/pan the map later to verify.
var la_aoi = ee.Geometry.Rectangle([-118.95, 33.5, -117.6, 34.85]);

// Center the map on LA and zoom in
Map.centerObject(la_aoi, 10);
Map.addLayer(la_aoi, {color: 'red'}, 'LA Area of Interest');

// 2. Load Landsat 8/9 Collection 2 Level-2 data (includes pre-computed LST)
var landsat = ee.ImageCollection('LANDSAT/LC08/C02/T1_L2')  // Landsat 8
                .merge(ee.ImageCollection('LANDSAT/LC09/C02/T1_L2'));  // Merge with Landsat 9

// 3. Filter for summer months (June-August) in recent years, low cloud cover, and clip to LA
var lst_collection = landsat
  .filterBounds(la_aoi)
  .filterDate('2023-06-01', '2023-08-31')  // Adjust years as needed (up to current data)
  .filter(ee.Filter.lt('CLOUD_COVER', 20))  // Less than 20% clouds
  .select('ST_B10');  // Select the LST band (surface temperature in Kelvin * 100)

// 4. Function to convert scaled Kelvin to Celsius
var kelvinToCelsius = function(image) {
  return image
    .multiply(0.00341802)  // Apply USGS scaling factor
    .add(149.0)            // Add offset
    .subtract(273.15)      // Convert Kelvin to Celsius
    .copyProperties(image, ['system:time_start']);
};

// Apply conversion
var lst_celsius = lst_collection.map(kelvinToCelsius);

// 5. Create a median composite (reduces clouds/noise) for summer mean LST
var mean_summer_lst = lst_celsius.median().clip(la_aoi);

// 6. Visualize the mean LST on the map
var lstVis = {
  min: 20,   // Typical summer daytime LST in °C for LA
  max: 50,
  palette: ['blue', 'cyan', 'green', 'yellow', 'orange', 'red']
};

Map.addLayer(mean_summer_lst, lstVis, 'Mean Summer LST (°C)');

// 7. Print some info to the Console (top-right tab)
print('Number of scenes used:', lst_collection.size());
print('Mean LST image:', mean_summer_lst);


// 8. Export the mean summer LST raster to Google Drive
Export.image.toDrive({
  image: mean_summer_lst,                  // The LST image in °C
  description: 'LA_Mean_Summer_LST_2023_Celsius',  // File name (no spaces/special chars recommended)
  folder: 'GEE_Exports',                   // Optional: Creates a folder in your Drive
  fileNamePrefix: 'LA_mean_summer_2023_lst_celsius',
  region: la_aoi,                          // Exports only the LA area
  scale: 30,                               // 30-meter resolution (native Landsat)
  crs: 'EPSG:4326',                        // Export in WGS84 (easy for PostGIS; you can change to UTM if preferred)
  maxPixels: 1e10,                         // Allows large exports
  fileFormat: 'GeoTIFF'
});