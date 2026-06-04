# Western Water Datahub collection field guide

The [Western Water Datahub](https://api.wwdh.internetofwater.app)
publishes many water-relevant datasets through an [OGC API -
Environmental Data Retrieval](https://ogcapi.ogc.org/edr/) and OGC API
Features interface. The [Swagger/OpenAPI
page](https://api.wwdh.internetofwater.app/openapi) is the authoritative
endpoint reference. This page is the companion field guide: it is meant
to help a technically comfortable water SME decide which collection to
open, which query shape to try first, and how to turn the response into
a table, plot, map, or CSV.

The examples below were checked against the live WWDH collection
metadata on June 4, 2026. The Datahub changes over time, so treat the
code in the first section as the durable part: re-run discovery before
starting a new analysis.

## 1. The mental model

An EDR service has a few layers:

1.  The service landing page tells you what top-level resources exist.
2.  `/collections` lists datasets, called collections.
3.  `/collections/{id}` describes one collection, including its
    parameters, extent, links, and supported EDR query types.
4.  Query endpoints retrieve either station/location metadata, feature
    geometries, or sampled environmental values.

In practice, WWDH collections fall into three broad families.

| Family | Typical collections | Best first query | What comes back |
|----|----|----|----|
| Station or site time series | `rise-edr`, `snotel-edr`, `awdb-forecasts-edr`, `usace-edr`, `resviz-edr`, `teacup-edr`, `resops-edr` | [`edr_locations()`](https://ksonda.github.io/edr4r/reference/edr_locations.md) to find sites, then [`edr_cube()`](https://ksonda.github.io/edr4r/reference/edr_cube.md) or [`edr_location()`](https://ksonda.github.io/edr4r/reference/edr_location.md) for values | GeoJSON for sites; CoverageJSON for time series |
| Gridded or point-sampled coverages | `usgs-prism` | [`edr_cube()`](https://ksonda.github.io/edr4r/reference/edr_cube.md) for a small bbox, or [`edr_position()`](https://ksonda.github.io/edr4r/reference/edr_position.md) for one lon/lat | CoverageJSON with grid cells or a point series |
| Feature/catalog layers | `snotel-huc06-means`, drought monitor layers, many NOAA forecast layers, DOI regions | [`edr_queryables()`](https://ksonda.github.io/edr4r/reference/edr_queryables.md) and [`edr_items()`](https://ksonda.github.io/edr4r/reference/edr_items.md) | GeoJSON features and attributes |

The most important distinction is this:

- `parameter_names` are data variables you can ask for, such as
  reservoir storage, SWE, stage, precipitation, or maximum temperature.
  In `edr4r`, discover them with
  [`edr_parameters()`](https://ksonda.github.io/edr4r/reference/edr_parameters.md)
  and pass them to query helpers as `parameter_name =`.
- `queryables` are filterable feature properties, such as `id`, `name`,
  `valid_time`, or `basin_index`. Discover them with
  [`edr_queryables()`](https://ksonda.github.io/edr4r/reference/edr_queryables.md).
  They are most useful for `/items` collections and feature-style
  filtering.

## 2. Ten-minute discovery checklist

Start every WWDH session by listing collections and their advertised
query types.

``` r

library(edr4r)

wwdh <- edr_client("https://api.wwdh.internetofwater.app")

collections <- edr_collections(wwdh)
collections[, c("id", "title", "data_queries")]
#> # A tibble: 35 x 3
#>    id                 title                                  data_queries
#>    <chr>              <chr>                                  <list>
#>  1 rise-edr           USBR Reclamation Information Sharing... <chr [4]>
#>  2 snotel-edr         USDA Snowpack Telemetry Network ...     <chr [4]>
#>  3 awdb-forecasts-edr USDA Air and Water Database Forecasts   <chr [4]>
#>  4 snotel-huc06-means USDA Snotel Snow Water Equivalent ...   <NULL>
#>  5 usace-edr          USACE Access2Water API                  <chr [4]>
#>  6 noaa-qpf-day-1     NOAA Weather Prediction Center ...      <NULL>
#>  7 noaa-qpf-day-2     NOAA Weather Prediction Center ...      <NULL>
#>  8 noaa-qpf-day-3     NOAA Weather Prediction Center ...      <NULL>
#>  9 noaa-qpf-day-4-5   NOAA Weather Prediction Center ...      <NULL>
#> 10 noaa-qpf-day-6-7   NOAA Weather Prediction Center ...      <NULL>
#> # i 25 more rows
```

The `data_queries` column is your route map. If it contains `locations`,
the collection has a site index. If it contains `cube`, you can usually
pull many sites or grid cells inside a bbox in one request. If it
contains `area`, you can query a polygon. If it is empty, do not assume
the collection is useless; it is often an OGC API Features layer, so use
[`edr_queryables()`](https://ksonda.github.io/edr4r/reference/edr_queryables.md)
and
[`edr_items()`](https://ksonda.github.io/edr4r/reference/edr_items.md).

Then inspect one collection before retrieving data:

``` r

edr_collection(wwdh, "snotel-edr")$title
#> [1] "USDA Snowpack Telemetry Network (SNOTEL)"

names(edr_collection(wwdh, "snotel-edr")$data_queries)
#> [1] "locations" "cube" "area" "items"

params <- edr_parameters(wwdh, "snotel-edr")
params[params$id %in% c("WTEQ", "SNWD", "PREC"),
       c("id", "name", "unit_symbol")]
#> # A tibble: 3 x 3
#>   id    name                                unit_symbol
#>   <chr> <chr>                               <chr>
#> 1 PREC  Precipitation Accumulation (in)     in
#> 2 SNWD  Snow Depth (in)                     in
#> 3 WTEQ  Snow Water Equivalent               in
```

The same metadata is browsable without R:

- `https://api.wwdh.internetofwater.app/collections?f=html`
- `https://api.wwdh.internetofwater.app/collections/snotel-edr?f=html`
- `https://api.wwdh.internetofwater.app/collections/snotel-edr/queryables?f=html`

## 3. Choosing a query type

Use the smallest query that answers the question.

| Question | EDR helper | URL shape | Notes |
|----|----|----|----|
| What collections exist? | [`edr_collections()`](https://ksonda.github.io/edr4r/reference/edr_collections.md) | `/collections` | First step for every session |
| What variables does this collection serve? | [`edr_parameters()`](https://ksonda.github.io/edr4r/reference/edr_parameters.md) | `/collections/{id}` | Use returned `id` values as `parameter_name` |
| What sites are in my study area? | [`edr_locations()`](https://ksonda.github.io/edr4r/reference/edr_locations.md) | `/collections/{id}/locations` | Returns GeoJSON, usually promoted to `sf` |
| What features or polygons are in this layer? | [`edr_items()`](https://ksonda.github.io/edr4r/reference/edr_items.md) | `/collections/{id}/items` | Best for non-EDR feature collections |
| What is the value at one lon/lat? | [`edr_position()`](https://ksonda.github.io/edr4r/reference/edr_position.md) | `/collections/{id}/position` | Good for gridded coverages such as PRISM |
| What values fall in this bbox? | [`edr_cube()`](https://ksonda.github.io/edr4r/reference/edr_cube.md) | `/collections/{id}/cube` | Best first bulk query for stations or grids |
| What values fall in this polygon? | [`edr_area()`](https://ksonda.github.io/edr4r/reference/edr_area.md) | `/collections/{id}/area` | Useful for watershed or management boundaries |
| What values are near this point? | [`edr_radius()`](https://ksonda.github.io/edr4r/reference/edr_radius.md) | `/collections/{id}/radius` | Supported by the client, but not common on WWDH |
| What values follow a path? | [`edr_trajectory()`](https://ksonda.github.io/edr4r/reference/edr_trajectory.md) / [`edr_corridor()`](https://ksonda.github.io/edr4r/reference/edr_corridor.md) | `/trajectory`, `/corridor` | More common in weather/ocean EDR than current WWDH use |

In R, arguments use readable names such as `parameter_name`. In the raw
URL, EDR uses kebab-case query parameters such as `parameter-name`.
`edr4r` does that translation for you.

Always remember bbox order:

``` r

bbox <- c(min_lon, min_lat, max_lon, max_lat)
```

## 4. Station and reservoir time series

Station-style collections have two parts: a location index and sampled
values. Start with a small bbox and one parameter.

``` r

co_front_range <- c(-107, 37, -105, 40)

snotel_sites <- edr_locations(
  wwdh, "snotel-edr",
  bbox  = co_front_range,
  limit = 5
)

nrow(snotel_sites)
#> [1] 51

snotel_sites[, c("stationTriplet", "name", "stateCode", "networkCode")]
#> Simple feature collection with 51 features and 4 fields
#> # A tibble: 51 x 5
#>   stationTriplet name              stateCode networkCode geometry
#>   <chr>          <chr>             <chr>     <chr>       <POINT [deg]>
#> 1 303:CO:SNTL    Apishapa          CO        SNTL        ...
#> 2 1041:CO:SNTL   Beaver Ck Village CO        SNTL        ...
#> 3 335:CO:SNTL    Berthoud Summit   CO        SNTL        ...
#> # i 48 more rows
```

Some providers honor `limit` on `/locations`, and some return all
matching sites inside the spatial filter. That is normal provider
variation. Keep the bbox small while exploring.

For more than one station, prefer
[`edr_cube()`](https://ksonda.github.io/edr4r/reference/edr_cube.md)
when the collection advertises it. It is one server request across a
bbox, rather than one request per station.

``` r

swe <- edr_cube(
  wwdh, "snotel-edr",
  bbox           = c(-106.2, 39.6, -105.8, 40.0),
  datetime       = "2024-02-01/2024-04-30",
  parameter_name = "WTEQ"
)

swe_tbl <- covjson_to_tibble(swe)
dim(swe_tbl)
#> [1] 540   9

head(swe_tbl[, c("coverage_id", "parameter", "datetime", "x", "y", "value")])
#> # A tibble: 6 x 6
#>   coverage_id parameter datetime                x     y value
#>   <chr>       <chr>     <dttm>              <dbl> <dbl> <dbl>
#> 1 1           WTEQ      2024-02-01 00:00:00 -106.  39.9  11.6
#> 2 1           WTEQ      2024-02-02 00:00:00 -106.  39.9  11.7
#> 3 1           WTEQ      2024-02-03 00:00:00 -106.  39.9  12.3
#> 4 1           WTEQ      2024-02-04 00:00:00 -106.  39.9  12.3
#> 5 1           WTEQ      2024-02-05 00:00:00 -106.  39.9  12.5
#> 6 1           WTEQ      2024-02-06 00:00:00 -106.  39.9  12.5
```

The long table returned by
[`covjson_to_tibble()`](https://ksonda.github.io/edr4r/reference/covjson_to_tibble.md)
has the same core columns across station, grid, and profile data:

| Column | Meaning |
|----|----|
| `coverage_id` | The server’s coverage identifier for a station, feature, grid, or sampled geometry |
| `parameter` | The requested parameter id, such as `WTEQ`, `raw`, `Stage`, or `ppt` |
| `parameter_label` | Human-readable label when the server provides one |
| `unit` | Unit label or symbol when available |
| `datetime` | Time coordinate, parsed to UTC `POSIXct` when possible |
| `x`, `y`, `z` | Longitude, latitude, and optional vertical coordinate |
| `value` | The observation, forecast, summary statistic, or modeled value |

Reservoir-oriented collections follow the same pattern. A few useful
parameter examples:

| Collection | Parameter id | Meaning | Unit |
|----|----|----|----|
| `rise-edr` | `3` | Daily lake/reservoir storage | acre-ft |
| `rise-edr` | `1830` | Lake/reservoir release - total | cfs |
| `usace-edr` | `Stage` | Stage | ft |
| `usace-edr` | `Outflow` | Outflow | ft3/s |
| `resviz-edr` | `raw` | Daily lake/reservoir storage | acre-ft |
| `resviz-edr` | `p10`, `avg`, `p90` | Historical storage quantiles | acre-ft |
| `resops-edr` | `p10`, `avg`, `p90` | USACE 30-year storage summaries | million cubic meters |

For fast exploratory products,
[`edr_explore()`](https://ksonda.github.io/edr4r/reference/edr_explore.md)
chooses a bulk query when possible and returns either a leaflet map, a
ggplot, or the tidy data.

``` r

edr_explore(
  wwdh, "usace-edr",
  bbox           = c(-98, 31, -94, 34),
  datetime       = "2024-01-01/2024-03-31",
  parameter_name = "Stage",
  label_col      = "name",
  popup          = "plot+csv"
)
```

## 5. Gridded climate data: PRISM

`usgs-prism` is different from the station collections. It advertises
`position` and `cube`, and its parameters are gridded monthly climate
variables.

``` r

edr_parameters(wwdh, "usgs-prism")[, c("id", "name", "unit_symbol")]
#> # A tibble: 3 x 3
#>   id    name                                  unit_symbol
#>   <chr> <chr>                                 <chr>
#> 1 ppt   Mean monthly precipitation            mm/month
#> 2 tmn   Minimum monthly temperature           deg C
#> 3 tmx   Maximum Monthly Temperature           deg C
```

Use
[`edr_position()`](https://ksonda.github.io/edr4r/reference/edr_position.md)
when you want the monthly series at one point:

``` r

prism_point <- edr_position(
  wwdh, "usgs-prism",
  coords         = c(-112.4, 36.9),
  datetime       = "2023-01-01/2023-02-28",
  parameter_name = "ppt"
)

covjson_to_tibble(prism_point)
#> # A tibble: 2 x 9
#>   coverage_id parameter parameter_label unit     datetime        x     y     z value
#>   <chr>       <chr>     <chr>           <chr>    <dttm>      <dbl> <dbl> <dbl> <dbl>
#> 1 1           ppt       Mean monthly... mm/month 2023-01-01 -112.  36.9    NA ...
#> 2 1           ppt       Mean monthly... mm/month 2023-02-01 -112.  36.9    NA ...
```

Use [`edr_cube()`](https://ksonda.github.io/edr4r/reference/edr_cube.md)
when you want a small grid:

``` r

prism_grid <- edr_cube(
  wwdh, "usgs-prism",
  bbox           = c(-112.6, 36.7, -112.2, 37.1),
  datetime       = "2023-01-01/2023-02-28",
  parameter_name = c("ppt", "tmx")
)

grid_tbl <- covjson_to_tibble(prism_grid)
grid_tbl[, c("parameter", "datetime", "x", "y", "value")]
#> # A tibble: 324 x 5
#>   parameter datetime                x     y value
#>   <chr>     <dttm>              <dbl> <dbl> <dbl>
#> 1 ppt       2023-01-01 00:00:00 -113.  37.1  116.
#> 2 ppt       2023-01-01 00:00:00 -113.  37.1  120.
#> 3 ppt       2023-01-01 00:00:00 -112.  37.1  131.
#> # i 321 more rows

edr_map(grid_tbl, initial = list(parameter = "ppt"))
```

For grid data,
[`edr_map()`](https://ksonda.github.io/edr4r/reference/edr_map.md)
builds an interactive cell map with selectors for parameter and time.

## 6. Feature and catalog layers

Some WWDH collections do not advertise EDR data queries. These are
usually feature layers: polygons, lines, or points with attributes. They
still matter for water analysis because they can carry forecast
products, drought categories, basin summaries, boundaries, or current
status attributes.

The workflow is:

``` r

q <- edr_queryables(wwdh, "snotel-huc06-means")
names(q$properties)
#> [1] "geometry"
#> [2] "name"
#> [3] "geoconnex_url"
#> [4] "id"
#> [5] "number_of_stations_used_for_basin_index_calculation"
#> [6] "current_snow_water_equivalent_relative_to_thirty_year_avg"
#> [7] "basin_index"

huc_swe <- edr_items(wwdh, "snotel-huc06-means", limit = 3)
names(huc_swe)
#>  [1] "id"
#>  [2] "name"
#>  [3] "station_list"
#>  [4] "current_snow_water_equivalent_relative_to_thirty_year_avg"
#>  [5] "basin_index"
#>  [6] "median_values"
#>  [7] "latest_values"
#>  [8] "number_of_stations_used_for_basin_index_calculation"
#>  [9] "geoconnex_url"
#> [10] "latest_full_day_of_data"
#> [11] "geometry"
```

For catalog layers, treat `/items` as a feature download, not as a
time-series sampling query. If the layer is large or provider-backed,
begin with a small bbox or a low limit. Some upstream wrappers are
sensitive to particular filter combinations, so if a request fails, try
these in order:

1.  Open the HTML collection page with `?f=html`.
2.  Open the queryables page and check exact field names.
3.  Try `/items?f=json&limit=1`.
4.  Try `/items?f=json&bbox=minx,miny,maxx,maxy`.
5.  Remove optional filters and add them back one at a time.

## 7. Browser and curl equivalents

You do not have to use R for the exploration step. Every helper above
maps to a plain URL.

Collection metadata:

``` text
https://api.wwdh.internetofwater.app/collections/rise-edr?f=html
https://api.wwdh.internetofwater.app/collections/rise-edr?f=json
```

Find SNOTEL stations in a bbox:

``` text
https://api.wwdh.internetofwater.app/collections/snotel-edr/locations?f=json&bbox=-107,37,-105,40
```

Sample PRISM precipitation at one point:

``` text
https://api.wwdh.internetofwater.app/collections/usgs-prism/position?f=json&coords=POINT(-112.4%2036.9)&datetime=2023-01-01/2023-02-28&parameter-name=ppt
```

Fetch feature items from a catalog collection:

``` text
https://api.wwdh.internetofwater.app/collections/snotel-huc06-means/items?f=json&limit=3
```

With `curl`, quote URLs that contain `?` or `&` so your shell does not
interpret them:

``` sh
curl -sS \
  'https://api.wwdh.internetofwater.app/collections/usgs-prism?f=json'
```

## 8. Practical troubleshooting

When a WWDH request fails, it is usually one of these:

| Symptom | Likely cause | What to try |
|----|----|----|
| HTTP 404 on a query verb | The collection does not support that query type | Check `data_queries` and switch verbs |
| HTTP 400 or 500 on a large query | The request is too broad or a source wrapper failed | Reduce bbox, date range, and parameter count |
| Empty features | The bbox/date/parameter combination has no data, or the provider ignores one filter | Confirm with the HTML page and try a known active area |
| [`edr_parameters()`](https://ksonda.github.io/edr4r/reference/edr_parameters.md) is empty | The collection is likely feature/catalog style | Use [`edr_queryables()`](https://ksonda.github.io/edr4r/reference/edr_queryables.md) and [`edr_items()`](https://ksonda.github.io/edr4r/reference/edr_items.md) |
| Unexpected station IDs | Provider-specific IDs differ from names or display codes | Use the feature `id` or the id column returned by [`edr_locations()`](https://ksonda.github.io/edr4r/reference/edr_locations.md) |
| Values are character instead of numeric | At least one returned parameter had non-numeric values | Query numeric and categorical parameters separately |

Good habits:

- Start with one parameter and one short time window.
- Use a bbox even when the endpoint can technically return everything.
- Prefer `cube` for bulk station/grid retrieval when it is advertised.
- Prefer `/items` for feature/catalog layers with no EDR data queries.
- Save intermediate results as CSV or RDS once you have a query you
  trust, rather than re-hitting the live service during every analysis
  step.

## 9. A compact workflow template

``` r

library(edr4r)

wwdh <- edr_client("https://api.wwdh.internetofwater.app", verbose = TRUE)

# 1. Pick a collection.
collections <- edr_collections(wwdh)
collections[, c("id", "title", "data_queries")]

# 2. Inspect variables and feature filters.
edr_parameters(wwdh, "rise-edr")
edr_queryables(wwdh, "rise-edr")

# 3. Find sites or features.
locs <- edr_locations(
  wwdh, "rise-edr",
  bbox  = c(-116, 35, -114, 37),
  limit = 25
)

# 4. Pull a small data sample.
resp <- edr_cube(
  wwdh, "rise-edr",
  bbox           = c(-116, 35, -114, 37),
  datetime       = "2024-01-01/2024-03-31",
  parameter_name = "3"
)

df <- covjson_to_tibble(resp)

# 5. Visualize or export.
edr_plot(df)
edr_map(locs, data = df, popup = "plot+csv")
write.csv(df, "wwdh-sample.csv", row.names = FALSE)
```

Once this works, enlarge one dimension at a time: a wider bbox, a longer
date range, or more parameters. That makes failures easier to diagnose
and keeps the shared API responsive.
