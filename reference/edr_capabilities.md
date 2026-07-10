# Inspect advertised EDR capabilities

`edr_capabilities()` gathers discovery metadata without probing any data
query endpoint. With neither id it returns a service snapshot. With a
`collection_id` it returns a collection snapshot, and with both a
`collection_id` and `instance_id` it returns an instance snapshot.

## Usage

``` r
edr_capabilities(
  client,
  collection_id = NULL,
  instance_id = NULL,
  refresh = FALSE
)
```

## Arguments

- client:

  An
  [`edr_client()`](https://ksonda.github.io/edr4r/reference/edr_client.md).

- collection_id:

  Optional collection identifier.

- instance_id:

  Optional instance identifier. Requires `collection_id`.

- refresh:

  If `TRUE`, bypass and replace cached discovery metadata.

## Value

An `edr_capabilities` object with a scope-specific subclass:
`edr_service_capabilities`, `edr_collection_capabilities`, or
`edr_instance_capabilities`. Service snapshots contain `landing`,
`conformance`, and `collections`. Collection and instance snapshots
contain raw metadata, a normalized one-row `summary`, `queries`,
`parameters`, `output_formats`, and `output_crs`.

## Details

Discovery responses use the client's process-local in-memory cache. Set
`refresh = TRUE` to bypass matching entries, or call
[`edr_cache_clear()`](https://ksonda.github.io/edr4r/reference/edr_cache_clear.md).
Capability values report what the server advertises; they do not prove
that the corresponding query succeeds.
