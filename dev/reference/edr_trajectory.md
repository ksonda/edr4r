# Trajectory query (data along a path)

Calls `GET /collections/{collection_id}/trajectory`.

## Usage

``` r
edr_trajectory(
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

  WKT LINESTRING, a matrix / data.frame of `(lon, lat)` rows, or an
  `sfc` linestring.

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

  `"covjson"` (default), `"geojson"`, `"csv"`, or `"json"`.

- ...:

  Additional query parameters passed through verbatim.
