# Get the queryables (filter properties) for a collection

Returns the OGC API queryables document for a collection – a JSON Schema
describing the filter properties the server exposes (this is typically
used by OGC API Features for CQL2 / property-based filtering). It is
**not** the right place to look up the data parameters / observed
properties an EDR collection serves; for that, use
[`edr_parameters()`](https://ksonda.github.io/edr4r/dev/reference/edr_parameters.md).

## Usage

``` r
edr_queryables(client, collection_id)
```

## Arguments

- client:

  An `edr_client`.

- collection_id:

  Collection identifier as advertised by the server – e.g.
  `"monitoring-locations"` or `"daily-values"`.

## Value

A list with the parsed queryables document.
