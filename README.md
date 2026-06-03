# edr4r

<!-- badges: start -->
[![R-CMD-check](https://github.com/ksonda/edr4r/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/ksonda/edr4r/actions/workflows/R-CMD-check.yaml)
[![Codecov test coverage](https://codecov.io/gh/ksonda/edr4r/graph/badge.svg)](https://app.codecov.io/gh/ksonda/edr4r)
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
<!-- badges: end -->

An R client for any service that speaks
[OGC API - Environmental Data Retrieval](https://ogcapi.ogc.org/edr/) (EDR).
The spec is general, but in practice this package gets the most use against
**in-situ monitoring networks** — stream gauges, weather stations, snow
telemetry, reservoir telemetry — that expose their stations and time series
through EDR.

Two known-good places to point it:

- [USGS waterdata OGC API](https://api.waterdata.usgs.gov/ogcapi/beta/) — stream gauges and water-quality stations from the U.S. Geological Survey.
- [Western Water Datahub](https://api.wwdh.internetofwater.app) — a [pygeoapi](https://pygeoapi.io) deployment that wraps RISE, SNOTEL, USACE, AWDB and other monitoring sources behind a single EDR endpoint.

The goal is to take the tedious parts of EDR off your hands — URL
construction, comma-separated parameter lists, WKT coordinate encoding,
retries, content negotiation — and hand back something you can actually do
data analysis with:

- **CoverageJSON** → a long [`tibble`](https://tibble.tidyverse.org/) (one row per coverage × parameter × time step), via `covjson_to_tibble()`.
- **GeoJSON** → an [`sf`](https://r-spatial.github.io/sf/) object, via `geojson_to_sf()`.

## Installation

```r
# from GitHub (recommended)
# install.packages("pak")
pak::pak("ksonda/edr4r")

# or
# install.packages("remotes")
remotes::install_github("ksonda/edr4r")
```

For local development:

```sh
git clone https://github.com/ksonda/edr4r.git
cd edr4r
R -e 'devtools::install()'
```

Requires R >= 4.1. The `sf` package is optional but recommended (used to turn
location lists and GeoJSON into spatial objects).

## Quick start

Start by pointing a client at a server. The base URL is the only thing it
really needs:

```r
library(edr4r)

client <- edr_client("https://api.waterdata.usgs.gov/ogcapi/beta")
# or "https://api.wwdh.internetofwater.app"
# or "http://localhost:5005" if you're running pygeoapi locally

edr_collections(client)
#> # A tibble: N × 7
#>   id                   title                description  extent_bbox crs   data_queries links
#>   <chr>                <chr>                <chr>        <list>      <chr> <list>       <list>
#> 1 monitoring-locations Monitoring locations ...          <dbl [4]>   ...   <chr [3]>    ...
#> 2 daily-values         Daily values         ...          <dbl [4]>   ...   <chr [3]>    ...
#> ...
```

The collection IDs above (`monitoring-locations`, `daily-values`) are the
ones I used as placeholders — every server advertises its own. The first
thing to do against a new service is run `edr_collections()` and read the
`data_queries` column to see which EDR endpoints each collection supports.

### Find stations

`edr_locations()` with no filters returns the full station list as
GeoJSON. If you have [`sf`](https://r-spatial.github.io/sf/) installed,
it gets promoted to an `sf` object automatically:

```r
locs <- edr_locations(client, "monitoring-locations")
locs                            # sf POINTs with station attributes
plot(sf::st_geometry(locs))
```

### Pull a time series for one station

Once you know a station ID, ask for its values. The server returns
CoverageJSON; `covjson_to_tibble()` flattens it into one row per
(coverage × parameter × timestamp):

```r
resp <- edr_location(
  client, "daily-values",
  location_id    = "08313000",
  datetime       = "2020-01-01/2020-12-31",
  parameter_name = c("discharge", "gage_height")
)

df <- covjson_to_tibble(resp)
df
#> # A tibble: 732 × 9
#>   coverage_id parameter   parameter_label  unit  datetime                x     y     z value
#>   <chr>       <chr>       <chr>            <chr> <dttm>              <dbl> <dbl> <dbl> <dbl>
#> 1 08313000    discharge   Discharge        ft3/s 2020-01-01 00:00:00 -109.  37.0    NA   240
#> ...
```

### Spatial filters — bbox and polygon

To grab everything inside a rectangle, use `edr_cube()`:

```r
cube <- edr_cube(
  client, "daily-values",
  bbox           = c(-120, 39, -118, 41),
  datetime       = "2023-01-01/2023-03-31",
  parameter_name = "discharge"
)
covjson_to_tibble(cube)
```

For an arbitrary polygon, `edr_area()` takes WKT, an `sf` polygon, or a
matrix of `(lon, lat)` rows (it'll close the ring for you):

```r
ring <- matrix(
  c(-109, 47, -104, 47, -104, 49, -109, 49),
  ncol = 2, byrow = TRUE
)
area <- edr_area(client, "monitoring-locations", coords = ring,
                 datetime = "2022-01-01/..")
covjson_to_tibble(area)
```

### Plot a time series

`edr_plot()` is a small `ggplot2` wrapper over the tidy tibble:

```r
edr_plot(resp)            # accepts an edr_response directly
```

Facets by parameter (so different units don't share a y-axis) and
colours by station. Add layers or themes like any other ggplot.

### Map stations with per-station popups

`edr_map()` puts the stations on a leaflet basemap. Pass `data =` as a
named list keyed by station id (the shape [edr_explore()] produces) and
each marker gets a popup with an inline plot and a "Download CSV" link
for that station's data — embedded as a `data:` URI so the saved HTML
is selfcontained:

```r
stations <- edr_locations(client, "monitoring-locations",
                          bbox = c(-116, 35.5, -114, 36.5))
data_list <- list("3514" = covjson_to_tibble(resp))
m <- edr_map(stations, data = data_list, popup = "plot+csv")
edr_save_html(m, "stations.html")
```

For a quick exploratory pass over a whole collection, `edr_explore()`
does the fetch + plot + map in one call:

```r
edr_explore(
  client, "daily-values",
  bbox           = c(-116, 35.5, -114, 36.5),
  datetime       = "2024-01-01/2024-03-31",
  parameter_name = "discharge",
  limit          = 25,
  file           = "snapshot.html"
)
```

### Weird IDs, CSV, and an escape hatch

Some monitoring networks use compound station IDs — colon-separated
triplets are a common pattern. The client URL-encodes reserved
characters for you:

```r
edr_location(client, "station-network", "1185:CO:SNTL",
             datetime = "2024-01-01/..")
```

If the server advertises CSV, you can ask for it instead of CovJSON:

```r
edr_location(client, "daily-values", "08313000",
             datetime = "2010-01-01/..", format = "csv")
```

And if you need to hit an endpoint the package doesn't wrap (instances,
custom queryables, anything weird), `edr_request()` is the raw escape
hatch:

```r
edr_request(client, "collections/daily-values/instances", format = "json")
```

## API at a glance

| Function | EDR endpoint |
|---|---|
| `edr_client()` | construct a client |
| `edr_landing()` / `edr_conformance()` | `/`, `/conformance` |
| `edr_collections()` / `edr_collection()` | `/collections` |
| `edr_queryables()` | `/collections/{id}/queryables` |
| `edr_locations()` / `edr_location()` | `/collections/{id}/locations[/{loc}]` |
| `edr_items()` / `edr_item()` | `/collections/{id}/items[/{item}]` |
| `edr_position()` | `/collections/{id}/position` |
| `edr_area()` | `/collections/{id}/area` |
| `edr_cube()` | `/collections/{id}/cube` |
| `edr_radius()` | `/collections/{id}/radius` |
| `edr_trajectory()` | `/collections/{id}/trajectory` |
| `edr_corridor()` | `/collections/{id}/corridor` |
| `edr_request()` | low-level escape hatch |
| `covjson_to_tibble()` / `geojson_to_sf()` | response parsers |

> **What a server actually supports varies.** Every query verb above is in
> the [EDR spec](https://ogcapi.ogc.org/edr/) and supported by the client,
> but most servers implement only a subset. On in-situ monitoring
> deployments, `locations`, `position`, `cube`, and `area` are common;
> `radius`, `trajectory`, and `corridor` less so. Hitting a verb the server
> doesn't implement gives you an HTTP error. Check the `data_queries`
> column from `edr_collections()` before you assume a query will work.

## Common parameters

Every query verb accepts the standard EDR filters:

- `datetime` — an ISO-8601 instant or interval. Accepts `"2020-01-01/2020-12-31"`, an open interval `"2020-01-01/.."`, or a length-2 character vector `c("2020-01-01", "2020-12-31")`.
- `parameter_name` — a character vector of parameter names; sent as a comma-separated `parameter-name=` query. Use `edr_parameters()` to discover valid names.
- `bbox` — numeric length-4 (`minx, miny, maxx, maxy`) or length-6 (with z).
- `coords` — for `position`/`area`/`radius`/`trajectory`/`corridor`: a WKT string, a numeric vector / 2-column matrix of lon-lat, or an `sf`/`sfc` geometry.
- `z`, `crs`, `limit` — passed through when supplied.
- `...` — any extra query parameter is forwarded verbatim.

## License

MIT
