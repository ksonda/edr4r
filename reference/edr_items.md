# Items (OGC API Features) helpers

Many EDR servers expose an OGC API Features `/items` endpoint alongside
the EDR queries. The Western Water Datahub providers implement `items`
as a thin stub used to register the collection as both EDR and Features;
non-trivial data is usually obtained via the EDR queries.

## Usage

``` r
edr_items(
  client,
  collection_id,
  bbox = NULL,
  datetime = NULL,
  limit = NULL,
  format = c("geojson", "json"),
  ...
)

edr_item(client, collection_id, item_id, format = c("geojson", "json"), ...)
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

- item_id:

  Identifier of a single feature.
