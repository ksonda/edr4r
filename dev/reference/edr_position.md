# Position query (data at a point)

Calls `GET /collections/{collection_id}/position` with a WKT POINT in
the `coords` parameter.

## Usage

``` r
edr_position(
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

  Either a length-2 numeric vector `c(lon, lat)`, a length-3 vector
  `c(lon, lat, z)`, or a WKT POINT string.

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
