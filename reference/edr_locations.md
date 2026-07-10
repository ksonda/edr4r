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
  ...,
  instance_id = NULL,
  paginate = FALSE,
  max_pages = 100L,
  max_features = 100000L
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

  Requested server page size. Servers may enforce their own maximum or
  ignore this value; with `paginate = TRUE`, use `max_features` as the
  client-side total feature cap.

- format:

  `"geojson"` (default) or `"json"`.

- ...:

  Additional query parameters passed through verbatim.

- instance_id:

  Optional instance identifier. When supplied, the request is sent
  beneath `/collections/{collection_id}/instances/{instance_id}`. This
  keyword-only argument leaves existing positional calls unchanged.

- paginate:

  If `TRUE`, follow same-origin `rel = "next"` links and combine bounded
  GeoJSON FeatureCollection pages. Defaults to `FALSE`.

- max_pages:

  Maximum number of pages to fetch when `paginate = TRUE`. Must be a
  finite positive integer; defaults to 100.

- max_features:

  Maximum combined feature count when `paginate = TRUE`. Must be a
  finite positive integer; defaults to 100,000.

## Value

When the server returns GeoJSON, an `sf` object if the `sf` package is
installed, otherwise an `edr_response` wrapping the raw GeoJSON. When
the server returns CoverageJSON, an `edr_response`. Successfully
paginated results carry an `edr_pagination` attribute with the completed
page and feature counts.
