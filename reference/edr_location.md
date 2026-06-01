# Get data for a single location

Calls `GET /collections/{collection_id}/locations/{location_id}`.
Typically returns CoverageJSON; pass the result to
[`covjson_to_tibble()`](https://ksonda.github.io/edr4r/reference/covjson_to_tibble.md)
for a tidy data frame.

## Usage

``` r
edr_location(
  client,
  collection_id,
  location_id,
  datetime = NULL,
  parameter_name = NULL,
  z = NULL,
  crs = NULL,
  format = c("covjson", "geojson", "csv", "json"),
  ...
)
```

## Arguments

- client:

  An `edr_client`.

- collection_id:

  Collection identifier.

- location_id:

  Identifier of the location. IDs vary by source: integers for USBR
  RISE, alphanumeric codes for SNOTEL/USACE, station triplets for AWDB
  forecasts (will be URL-encoded).

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
