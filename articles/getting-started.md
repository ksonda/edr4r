# Getting started with edr4r

`edr4r` is a small, tidy client for any service that speaks [OGC API -
Environmental Data Retrieval](https://ogcapi.ogc.org/edr/). Most of the
real-world use to date has been against in-situ monitoring networks –
stream gauges, weather stations, snow telemetry, reservoir telemetry –
but the package itself is generic.

Two example endpoints you can point it at right now:

- [USGS waterdata OGC API](https://api.waterdata.usgs.gov/ogcapi/beta/)
- [Western Water Datahub](https://api.wwdh.internetofwater.app)

This vignette runs end-to-end against the Western Water Datahub’s
`rise-edr` collection – a [pygeoapi](https://pygeoapi.io) wrap of USBR’s
reservoir telemetry. Every code chunk below is a real working call you
can copy into a session.

## 1. Create a client

``` r

library(edr4r)

client <- edr_client("https://api.wwdh.internetofwater.app")
client
```

The client just stores connection settings (base URL, user agent,
timeout, retry policy). Pass `verbose = TRUE` to echo every request URL,
or `headers =` to attach auth tokens.

## 2. Discover collections and parameters

[`edr_collections()`](https://ksonda.github.io/edr4r/reference/edr_collections.md)
lists every EDR collection the service serves.

``` r

collections <- edr_collections(client)
collections[, c("id", "title", "data_queries")]
```

The `data_queries` column tells you which EDR query types each
collection supports (`locations`, `cube`, `area`, …). Hit a verb the
server doesn’t implement and you get an HTTP error.

To see the **data parameters** a collection exposes (the values you can
pass to `parameter_name =` on the query verbs), use
[`edr_parameters()`](https://ksonda.github.io/edr4r/reference/edr_parameters.md):

``` r

params <- edr_parameters(client, "rise-edr")
params
#> # A tibble: 782 × 6
#>   id    name                          description unit_symbol unit_label
#>   <chr> <chr>                         <chr>       <chr>       <chr>
#> 1 1835  Secondary Canal Stage         "Average …" ft          Secondary…
#> 2 1834  Lake/Reservoir Elevation      "Average …" ft          Lake/Rese…
#> 3 1830  Lake/Reservoir Release Rate   "Instant…"  cfs         Lake/Rese…
#> ...
```

[`edr_queryables()`](https://ksonda.github.io/edr4r/reference/edr_queryables.md)
is something different – it returns the OGC queryables JSON Schema
(filterable feature properties for CQL2 / OGC API Features). For
discovering parameter names,
[`edr_parameters()`](https://ksonda.github.io/edr4r/reference/edr_parameters.md)
is what you want.

``` r

# Pick out the daily reservoir storage parameter (id "3"):
params[params$id == "3", ]
#> # A tibble: 1 × 6
#>   id    name                              description unit_symbol unit_label
#>   <chr> <chr>                             <chr>       <chr>       <chr>
#> 1 3     Daily Lake/Reservoir Storage      RISE Param… acre·ft     Acre Foot
```

## 3. Find locations

With no filters,
[`edr_locations()`](https://ksonda.github.io/edr4r/reference/edr_locations.md)
returns the station index as a GeoJSON `FeatureCollection`, promoted to
an `sf` object when [`sf`](https://r-spatial.github.io/sf/) is
installed:

``` r

stations <- edr_locations(client, "rise-edr")
nrow(stations)            # ~906 reservoirs
head(stations[, c("_id", "locationName")])
```

Note that the WWDH `rise-edr` locations index uses `_id` as the
identifier column, not `id`. That’s fine – the query verbs accept
either, and
[`edr_map()`](https://ksonda.github.io/edr4r/reference/edr_map.md) will
auto-detect.

## 4. Retrieve data for a station

Pick a known station (Lake Mead, id `3514`) and a parameter (`3`, Daily
Reservoir Storage) and you get CoverageJSON back. Flatten it into a tidy
tibble with
[`covjson_to_tibble()`](https://ksonda.github.io/edr4r/reference/covjson_to_tibble.md):

``` r

resp <- edr_location(
  client, "rise-edr",
  location_id    = 3514,
  datetime       = "2023-01-01/2023-06-30",
  parameter_name = "3"
)

df <- covjson_to_tibble(resp)
head(df)
#> # A tibble: 6 × 9
#>   coverage_id parameter parameter_label              unit  datetime
#>   <chr>       <chr>     <chr>                        <chr> <dttm>
#> 1 1           3         Lake/Reservoir Storage       af    2023-01-01 07:00:00
#> 2 1           3         Lake/Reservoir Storage       af    2023-01-02 07:00:00
#> ...
```

## 5. Plot the time series

[`edr_plot()`](https://ksonda.github.io/edr4r/reference/edr_plot.md) is
a small `ggplot2` wrapper for the tidy tibble:

``` r

library(ggplot2)
edr_plot(resp)            # accepts the edr_response directly
```

Faceted by parameter (so different units don’t share a y-axis) and
coloured by station. Add layers or themes like any other ggplot.

## 6. Map stations with per-station popups

[`edr_map()`](https://ksonda.github.io/edr4r/reference/edr_map.md) puts
the stations on a leaflet basemap. With `data =`, each marker gets a
popup containing a small inline plot and a “Download CSV” link for that
station. Pass a named list keyed by station id when you’ve fetched one
CovJSON per station (server-assigned `coverage_id`s won’t naturally
match the feature id):

``` r

data_list <- list("3514" = df)
m <- edr_map(
  stations[stations$`_id` == 3514, ],
  data        = data_list,
  id_col      = "_id",
  label_col   = "locationName",
  popup       = "plot+csv"
)
m
```

To save the map to a standalone HTML file (embedded plots and CSVs – no
sidecar directory):

``` r

edr_save_html(m, "lake-mead.html")
```

## 7. One-shot: `edr_explore()`

For a quick scan of a small set of stations,
[`edr_explore()`](https://ksonda.github.io/edr4r/reference/edr_explore.md)
does the whole pipeline – fetch locations, fetch one time series per
station, render the map – in a single call:

``` r

edr_explore(
  client, "rise-edr",
  limit          = 8,                       # cap on stations to fetch
  datetime       = "2023-01-01/2023-03-31",
  parameter_name = "3",
  file           = "rise-storage.html"
)
```

Each station gets its own popup. Stations the server has no data for (in
the requested window or for the requested parameter) fall back to a
label and the attribute table.

## A few things worth knowing

- `datetime` is forgiving: pass `"start/end"`, an open interval like
  `"2020-01-01/.."`, or a length-2 character vector. It gets normalised
  into the ISO-8601 form the server expects.
- `parameter_name` is a character vector. It’s sent as one
  comma-separated `parameter-name` query parameter.
- Some monitoring networks use compound station IDs (colon-separated
  triplets like `"1185:CO:SNTL"` show up in snow and forecast networks).
  Those work as-is – reserved characters get URL-encoded for you. A
  literal `/` in an ID is rejected, because it can’t survive a round
  trip through HTTP path segments no matter how you encode it.
- Not every server implements every EDR verb. `locations`, `position`,
  `cube`, and `area` are common; `radius`, `trajectory`, and `corridor`
  less so. The client supports them all per the
  [spec](https://ogcapi.ogc.org/edr/), but a call against a collection
  that doesn’t implement a given verb returns an HTTP error.
- [`edr_explore()`](https://ksonda.github.io/edr4r/reference/edr_explore.md)
  makes one HTTP call per station. For large collections, pre-filter
  aggressively via `bbox =` (if the server supports it) or `limit =`.
  \`\`\`
