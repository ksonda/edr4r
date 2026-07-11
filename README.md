# edr4r

<!-- badges: start -->
[![CRAN status](https://www.r-pkg.org/badges/version/edr4r)](https://CRAN.R-project.org/package=edr4r)
[![R-CMD-check](https://github.com/ksonda/edr4r/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/ksonda/edr4r/actions/workflows/R-CMD-check.yaml)
[![Codecov test coverage](https://codecov.io/gh/ksonda/edr4r/graph/badge.svg)](https://app.codecov.io/gh/ksonda/edr4r)
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
<!-- badges: end -->

An R client for
[OGC API - Environmental Data Retrieval](https://ogcapi.ogc.org/edr/) (EDR)
services that expose JSON discovery metadata and CoverageJSON, GeoJSON, or
CSV query responses.
The spec is general, but in practice this package gets the most use against
**in-situ monitoring networks** — stream gauges, weather stations, snow
telemetry, reservoir telemetry — that expose their stations and time series
through EDR.

Two known-good places to point it:

- [USGS waterdata OGC API](https://api.waterdata.usgs.gov/ogcapi/beta/) — stream gauges and water-quality stations from the U.S. Geological Survey.
- [Western Water Datahub](https://api.wwdh.internetofwater.app) — a [pygeoapi](https://pygeoapi.io) deployment that wraps RISE, SNOTEL, USACE, AWDB and other monitoring sources behind a single EDR endpoint.

For cross-server experiments, the
[Met Office Labs EDR demonstrator](https://labs.metoffice.gov.uk/edr/collections?f=html)
is another useful endpoint. It is a **technical demonstrator, not an
operational service**: availability, collections, and response details can
change without notice, so do not build production workflows around it.
The cross-endpoint Lake Mead vignette shows its 2015 population grid alongside
USGS river discharge and Western Water Datahub reservoir storage without
mixing their provenance or units.

The goal is to take the tedious parts of EDR off your hands — URL
construction, comma-separated parameter lists, WKT coordinate encoding,
retries, content negotiation — and hand back something you can actually do
data analysis with:

- **CoverageJSON** → a long [`tibble`](https://tibble.tidyverse.org/) (one row per coverage × parameter × time step), via `covjson_to_tibble()`.
- **GeoJSON** → an [`sf`](https://r-spatial.github.io/sf/) object, via `geojson_to_sf()`.
- **CSV** → a `tibble`, parsed directly by the query helper.

## Installation

CRAN currently provides the stable `0.1.1` release:

```r
install.packages("edr4r")
```

The upcoming `0.2.0` API is available as a GitHub-only release candidate. It
has not been submitted to CRAN:

```r
# install.packages("pak")
pak::pak("ksonda/edr4r@v0.2.0-rc.1")

# Follow the mutable development branch instead:
pak::pak("ksonda/edr4r")

# or
# install.packages("remotes")
remotes::install_github("ksonda/edr4r@v0.2.0-rc.1")
```

The release-candidate package intentionally reports development version
`0.1.1.9000` inside R. The final version will become `0.2.0` only when that
release is prepared for CRAN. The mutable default branch may also contain
post-candidate `0.3.0` development and currently reports `0.2.0.9000`; use the
tag when you need the frozen `0.2.0-rc.1` code.

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

collections <- edr_collections(client)
collections[, c("id", "title", "data_queries", "output_formats")]
```

Collection IDs are service-specific. The first thing to do against a new
service is run `edr_collections()` and read the `data_queries` column to see
which EDR endpoints each collection supports.

For a new or unfamiliar implementation, inspect its advertised support before
issuing data queries:

```r
edr_capabilities(client, "daily-edr")
edr_supports(client, "daily-edr", query = "locations")
edr_diagnose(client, "daily-edr")
```

`edr_supports()` reports what metadata advertises; `FALSE` is not proof that a
partially conformant server cannot handle the request.

Discovery metadata is cached per client for a short, configurable period.
Use `refresh = TRUE` when current server state matters, or
`edr_cache_clear(client)` to clear it explicitly.

To try the non-operational Met Office demonstrator with a deliberately small
request, query one terrain point rather than a forecast collection:

```r
met <- edr_client(
  "https://labs.metoffice.gov.uk/edr",
  timeout = 10,
  max_tries = 1
)

terrain <- edr_position(
  met,
  "terrain_tiles",
  coords = c(-0.1276, 51.5072),
  parameter_name = "Height"
)
covjson_to_tibble(terrain)
```

This example is also exercised by a scheduled, non-blocking live smoke check;
it is never run as part of CRAN checks or the regular test suite.

Collections representing model runs may advertise instances. The same query
verbs work below an instance when `instance_id` is named explicitly:

```r
runs <- edr_instances(met, "moglobal-station-level")
run_id <- runs$id[[1]]

run_capabilities <- edr_capabilities(
  met, "moglobal-station-level", instance_id = run_id
)
edr_supports(
  run_capabilities, query = "locations"
)
run_locations <- edr_locations(
  met, "moglobal-station-level",
  instance_id = run_id
)
```

### Find stations

`edr_locations()` returns one server response by default. If the response is
GeoJSON and [`sf`](https://r-spatial.github.io/sf/) is installed, it is
promoted to an `sf` object automatically. For a complete result from a server
that advertises `rel = "next"`, opt into bounded pagination:

```r
locs <- edr_locations(
  client, "monitoring-locations",
  limit = 500,              # server page size
  paginate = TRUE,
  max_pages = 20,
  max_features = 10000
)
locs                            # sf POINTs with station attributes
plot(sf::st_geometry(locs))
```

Pagination follows the server's next URL as an opaque cursor or offset. It
stops with a typed error if a page/feature cap is reached while another page
still exists, so a bounded result is never presented as complete.

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

### Pull several station time series safely

When you already have station IDs, `edr_location_batch()` makes one bounded,
sequential `edr_location()` request per ID and keeps request provenance and
failures visible:

```r
pull <- edr_location_batch(
  client, "daily-values",
  location_id    = locs$id[1:10],
  datetime       = "2020-01-01/2020-12-31",
  parameter_name = "discharge",
  max_requests   = 10,
  on_error       = "collect"
)

pull$data                  # .request_id and .location_id identify every row
pull$errors                # typed, empty tibble when every request succeeded
pull$requests              # success / empty / error status for every ID
```

The helper deliberately does not discover stations or parallelize requests;
the full request count is known and validated before network activity.

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

It also auto-detects common non-station shapes:

```r
edr_plot(cube)            # x/y grid -> tile map
edr_plot(profile)         # varying z -> vertical profile

# or force the layout
edr_plot(profile, view = "profile")
edr_plot(cube, view = "grid")
```

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

Gridded coverages and vertical profiles can be mapped too. `edr_map()`
detects tidy CoverageJSON grids/profiles and puts slice selectors inside
the leaflet widget when there are multiple parameters or datetimes; grids
also get a `z` selector when multiple vertical levels are present:

```r
grid <- covjson_to_tibble(cube)
edr_map(grid)

profile <- covjson_to_tibble(profile_resp)
edr_map(profile)
```

Coverage and station layers can share one widget. Start with the coverage map,
then add independently styled station groups with their normal chart/CSV
popups:

```r
m <- edr_map(grid, grid_transform = "sqrt")
m <- edr_add_stations(
  m, stations,
  data = data_list,
  popup = "plot+csv",
  group = "USGS"
)
```

`edr_explore()` uses the same behavior for bulk coverage queries. Use
`output = "plot"` when you want a ggplot instead of the interactive map:

```r
edr_explore(client, "gridded-collection",
            bbox = c(-120, 39, -118, 41),
            method = "cube")

edr_explore(client, "profile-collection",
            coords = c(-119, 40),
            method = "position")

edr_explore(client, "profile-collection",
            coords = c(-119, 40),
            method = "position", output = "plot")
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

And if you need to hit an endpoint or encoding the package doesn't wrap,
`edr_request()` is the raw escape
hatch:

```r
service_description <- edr_request(
  client, "api", format = "raw", parse = FALSE
)
```

## API at a glance

| Function | EDR endpoint |
|---|---|
| `edr_client()` | construct a client |
| `edr_landing()` / `edr_conformance()` | `/`, `/conformance` |
| `edr_collections()` / `edr_collection()` | `/collections` |
| `edr_capabilities()` / `edr_supports()` / `edr_diagnose()` | inspect advertised support |
| `edr_cache_clear()` | clear cached discovery metadata |
| `edr_queryables()` | `/collections/{id}/queryables` |
| `edr_instances()` / `edr_instance()` | `/collections/{id}/instances[/{instance}]` |
| `edr_locations()` / `edr_location()` | `/collections/{id}/locations[/{loc}]` |
| `edr_location_batch()` | bounded sequential requests to explicit location IDs |
| `edr_items()` / `edr_item()` | `/collections/{id}/items[/{item}]` |
| `edr_position()` | `/collections/{id}/position` |
| `edr_area()` | `/collections/{id}/area` |
| `edr_cube()` | `/collections/{id}/cube` |
| `edr_radius()` | `/collections/{id}/radius` |
| `edr_trajectory()` | `/collections/{id}/trajectory` |
| `edr_corridor()` | `/collections/{id}/corridor` |
| `edr_request()` | low-level escape hatch |
| `covjson_to_tibble()` / `geojson_to_sf()` | response parsers |

Every collection query helper also accepts named `instance_id =`; when set,
the path becomes `/collections/{id}/instances/{instance_id}/{query}`.

> **What a server actually supports varies.** Every query verb above is in
> the [EDR spec](https://ogcapi.ogc.org/edr/) and supported by the client,
> but most servers implement only a subset. On in-situ monitoring
> deployments, `locations`, `position`, `cube`, and `area` are common;
> `radius`, `trajectory`, and `corridor` less so. Hitting a verb the server
> doesn't implement gives you an HTTP error. Check the `data_queries`
> column from `edr_collections()` before you assume a query will work.

See `vignette("compatibility")` for the precise supported subset, return
formats, known limitations, and the distinction between verified and merely
advertised endpoint behavior.

## Common parameters

Every query verb accepts the standard EDR filters:

- `datetime` — an ISO-8601 instant or interval. Accepts `"2020-01-01/2020-12-31"`, an open interval `"2020-01-01/.."`, or a length-2 character vector `c("2020-01-01", "2020-12-31")`.
- `parameter_name` — a character vector of parameter names; sent as a comma-separated `parameter-name=` query. Use `edr_parameters()` to discover valid names.
- `bbox` — numeric length-4 (`minx, miny, maxx, maxy`) or length-6 (with z).
- `coords` — for `position`/`area`/`radius`/`trajectory`/`corridor`: a WKT string, a numeric vector / 2-column matrix of lon-lat, or an `sf`/`sfc` geometry.
- `z`, `crs`, `limit` — passed through when supplied.
- `instance_id` — named, optional model-run/version identifier; inserts the
  standard `/instances/{id}` path segment before the query type.
- `...` — any extra query parameter is forwarded verbatim.

## License

MIT
