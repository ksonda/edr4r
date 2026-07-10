# Corridor query (data along a path with a width)

Calls `GET /collections/{collection_id}/corridor`.

## Usage

``` r
edr_corridor(
  client,
  collection_id,
  coords,
  corridor_width,
  corridor_height,
  width_units = "km",
  height_units = "m",
  datetime = NULL,
  parameter_name = NULL,
  z = NULL,
  crs = NULL,
  format = c("covjson", "json"),
  ...,
  instance_id = NULL
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

- corridor_width:

  Width of the corridor.

- corridor_height:

  Vertical extent of the corridor. Required by the EDR corridor query
  requirements.

- width_units:

  Units for `corridor_width`.

- height_units:

  Units for `corridor_height`.

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

- instance_id:

  Optional instance identifier. When supplied, the request is sent
  beneath `/collections/{collection_id}/instances/{instance_id}`. This
  keyword-only argument leaves existing positional calls unchanged.

## Value

An `edr_response` containing the server's CoverageJSON response. Convert
it with
[`covjson_to_tibble()`](https://ksonda.github.io/edr4r/reference/covjson_to_tibble.md).
