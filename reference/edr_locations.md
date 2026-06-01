# List locations in a collection

Calls `GET /collections/{collection_id}/locations`. With no extra
filters, EDR servers typically return a GeoJSON `FeatureCollection` of
available locations.

## Usage

``` r
edr_locations(
  client,
  collection_id,
  bbox = NULL,
  datetime = NULL,
  parameter_name = NULL,
  crs = NULL,
  limit = NULL,
  format = c("geojson", "json"),
  ...
)
```

## Arguments

- client:

  An `edr_client`.

- collection_id:

  Collection identifier.

- bbox:

  Numeric vector of length 4 or 6 (`c(minx, miny, maxx, maxy)` or with
  z).

- datetime:

  ISO-8601 instant or interval, e.g. `"2024-01-01/2024-12-31"` or
  `"2024-01-01/.."`.

- parameter_name:

  Character vector of parameter names to filter on. Sent as a
  comma-separated `parameter-name=` query.

- crs:

  Optional CRS URI for the response.

- limit:

  Maximum number of features to return.

- format:

  `"geojson"` (default) or `"json"`.

- ...:

  Additional query parameters passed through verbatim.

## Value

When the server returns GeoJSON, an `sf` object if the `sf` package is
installed, otherwise an `edr_response` wrapping the raw GeoJSON. When
the server returns CoverageJSON, an `edr_response`.
