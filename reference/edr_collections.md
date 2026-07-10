# List collections offered by the service

List collections offered by the service

## Usage

``` r
edr_collections(client, refresh = FALSE)
```

## Arguments

- client:

  An `edr_client`.

- refresh:

  If `TRUE`, bypass and replace any cached response. Discovery responses
  otherwise use the client's `cache_ttl`; see
  [`edr_client()`](https://ksonda.github.io/edr4r/reference/edr_client.md).

## Value

A tibble with one row per collection. Always includes `id`, `title`,
`description`, spatial/temporal/vertical extent columns, `extent_crs`
(`crs` is retained as a compatibility alias), `output_crs`,
`output_formats`, `parameters`, `data_queries`, `query_details`,
`query_error`, `has_instances`, and `links` columns. `extent_bbox` is a
convenience view of the first bounding box; all spatial extents are
retained in `extent_bboxes` and `extent_spatial` list columns.
