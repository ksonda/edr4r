# edr4r

<!-- badges: start -->
[![R-CMD-check](https://github.com/ksonda/edr4r/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/ksonda/edr4r/actions/workflows/R-CMD-check.yaml)
[![Codecov test coverage](https://codecov.io/gh/ksonda/edr4r/graph/badge.svg)](https://app.codecov.io/gh/ksonda/edr4r)
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
<!-- badges: end -->

An R client for **OGC API - Environmental Data Retrieval (EDR)** services,
built for the [Western Water Datahub (WWDH)](https://github.com/internetofwater/WWDH)
pygeoapi deployment but usable against any compliant EDR server.

It handles the boring parts — URL construction, comma-separated parameter
lists, WKT coordinate encoding, retries, and content negotiation — and parses
responses into tidy structures:

- **CoverageJSON** → a long [`tibble`](https://tibble.tidyverse.org/) (one row per coverage × parameter × time-step), via `covjson_to_tibble()`.
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

```r
library(edr4r)

# Point at a running WWDH server: local dev, or the hosted instance
# at "https://api.wwdh.internetofwater.app".
wwdh <- edr_client("http://localhost:5005")

# What collections are available?
edr_collections(wwdh)
#> # A tibble: 7 × 7
#>   id                 title                         description  extent_bbox crs   data_queries links
#>   <chr>              <chr>                         <chr>        <list>      <chr> <list>       <list>
#> 1 rise-edr           USBR RISE                     ...          <dbl [4]>   ...   <chr [3]>    ...
#> 2 snotel-edr         USDA SNOTEL                   ...          <dbl [4]>   ...   <chr [3]>    ...
#> ...
```

### List locations (returns an `sf` object)

```r
locs <- edr_locations(wwdh, "rise-edr")
locs                       # sf POINTs with station attributes
plot(sf::st_geometry(locs))
```

### Pull a time series for one location (CoverageJSON → tibble)

```r
resp <- edr_location(
  wwdh, "rise-edr",
  location_id    = 247,
  datetime       = "2020-01-01/2020-12-31",
  parameter_name = c("storage", "elevation")
)

df <- covjson_to_tibble(resp)
df
#> # A tibble: 732 × 9
#>   coverage_id parameter parameter_label   unit       datetime                x     y     z value
#>   <chr>       <chr>     <chr>             <chr>      <dttm>              <dbl> <dbl> <dbl> <dbl>
#> 1 247         storage   Reservoir Storage acre-feet  2020-01-01 00:00:00 -104.  40.4    NA  100.5
#> ...
```

### Bounding-box (cube) and polygon (area) queries

```r
# Everything in a bbox over a date range
cube <- edr_cube(
  wwdh, "snotel-edr",
  bbox           = c(-120, 39, -118, 41),
  datetime       = "2023-01-01/2023-03-31",
  parameter_name = "WTEQ"
)
covjson_to_tibble(cube)

# Inside an arbitrary polygon (matrix of lon/lat, an sf polygon, or WKT)
ring <- matrix(
  c(-109, 47, -104, 47, -104, 49, -109, 49),
  ncol = 2, byrow = TRUE
)
area <- edr_area(wwdh, "rise-edr", coords = ring, datetime = "2022-01-01/..")
covjson_to_tibble(area)
```

### Station triplets, CSV, and escape hatches

```r
# AWDB forecast station triplets work as-is (encoded for you)
edr_location(wwdh, "awdb-forecasts-edr", "1185:CO:SNTL", datetime = "2024-01-01/..")

# Ask the server for CSV instead of CovJSON
edr_location(wwdh, "snotel-edr", "1175", datetime = "2010-01-01/..", format = "csv")

# Drop down to a raw request for anything not wrapped by a helper
edr_request(wwdh, "collections/rise-edr/instances", format = "json")
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

> **Note on WWDH coverage:** The WWDH providers currently implement
> `locations`, `cube`, and `area` (plus a stub `items`). `position`, `radius`,
> `trajectory`, and `corridor` are part of the EDR spec and supported by this
> client, but will return an error from collections that don't implement them.

## Common parameters

Every query verb accepts the standard EDR filters:

- `datetime` — an ISO-8601 instant or interval. Accepts `"2020-01-01/2020-12-31"`, an open interval `"2020-01-01/.."`, or a length-2 character vector `c("2020-01-01", "2020-12-31")`.
- `parameter_name` — a character vector of parameter names; sent as a comma-separated `parameter-name=` query. Use `edr_queryables()` to discover valid names.
- `bbox` — numeric length-4 (`minx, miny, maxx, maxy`) or length-6 (with z).
- `coords` — for `position`/`area`/`radius`/`trajectory`/`corridor`: a WKT string, a numeric vector / 2-column matrix of lon-lat, or an `sf`/`sfc` geometry.
- `z`, `crs`, `limit` — passed through when supplied.
- `...` — any extra query parameter is forwarded verbatim.

## License

MIT
