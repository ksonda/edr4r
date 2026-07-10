# Items (OGC API Features) helpers

Many EDR servers expose an OGC API Features `/items` endpoint alongside
the EDR queries. Behaviour varies: some deployments implement `items` as
a full Features endpoint, others as a thin stub used only to register
the collection as both EDR and Features. In the stub case, non-trivial
data is usually obtained via the EDR queries
([`edr_locations()`](https://ksonda.github.io/edr4r/reference/edr_locations.md),
[`edr_area()`](https://ksonda.github.io/edr4r/reference/edr_area.md),
[`edr_cube()`](https://ksonda.github.io/edr4r/reference/edr_cube.md),
etc.).

## Usage

``` r
edr_items(
  client,
  collection_id,
  bbox = NULL,
  datetime = NULL,
  limit = NULL,
  format = c("geojson", "json"),
  ...,
  instance_id = NULL
)

edr_item(
  client,
  collection_id,
  item_id,
  format = c("geojson", "json"),
  ...,
  instance_id = NULL
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

- limit:

  Maximum number of features to return.

- format:

  `"geojson"` (default) or `"json"`.

- ...:

  Additional query parameters passed through verbatim.

- instance_id:

  Optional instance identifier. When supplied, the request is sent
  beneath `/collections/{collection_id}/instances/{instance_id}`. This
  keyword-only argument leaves existing positional calls unchanged.

- item_id:

  Identifier of a single feature.

## Value

An `sf` object when `sf` is installed and the server returns GeoJSON;
otherwise an `edr_response` wrapping the GeoJSON document.
