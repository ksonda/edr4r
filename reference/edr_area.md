# Area query (data inside a polygon)

Calls `GET /collections/{collection_id}/area` with a WKT POLYGON in the
`coords` parameter.

## Usage

``` r
edr_area(
  client,
  collection_id,
  coords,
  datetime = NULL,
  parameter_name = NULL,
  z = NULL,
  crs = NULL,
  format = c("covjson", "json"),
  ...
)
```

## Arguments

- client:

  An `edr_client`.

- collection_id:

  Collection identifier.

- coords:

  WKT polygon string, or a matrix / data.frame of `(lon, lat)` rows that
  will be closed into a POLYGON. May also be an `sf` / `sfc` polygon if
  `sf` is installed.

- datetime:

  ISO-8601 instant or interval, e.g. `"2024-01-01/2024-12-31"` or
  `"2024-01-01/.."`.

- parameter_name:

  Character vector of parameter names to filter on. Sent as a
  comma-separated `parameter-name=` query.

- z:

  Vertical level filter.

- crs:

  Optional CRS URI for the response.

- format:

  `"covjson"` (default) or `"json"`.

- ...:

  Additional query parameters passed through verbatim.

## Value

An `edr_response` containing the server's CoverageJSON response. Convert
it with
[`covjson_to_tibble()`](https://ksonda.github.io/edr4r/reference/covjson_to_tibble.md).
