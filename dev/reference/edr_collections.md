# List collections offered by the service

List collections offered by the service

## Usage

``` r
edr_collections(client)
```

## Arguments

- client:

  An `edr_client`.

## Value

A tibble with one row per collection. Always includes `id`, `title`,
`description`, `extent_bbox`, `crs`, `data_queries`, and `links`
columns.
