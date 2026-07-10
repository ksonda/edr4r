# List instances of an EDR collection

Retrieves metadata for the versions or runs advertised beneath
`GET /collections/{collection_id}/instances`. Discovery responses use
the client's in-memory cache; set `refresh = TRUE` to bypass and replace
the cached value.

Retrieves the raw instance document from
`GET /collections/{collection_id}/instances/{instance_id}`.

## Usage

``` r
edr_instances(client, collection_id, refresh = FALSE)

edr_instance(client, collection_id, instance_id, refresh = FALSE)
```

## Arguments

- client:

  An
  [`edr_client()`](https://ksonda.github.io/edr4r/reference/edr_client.md).

- collection_id:

  Collection identifier as advertised by the server.

- refresh:

  If `TRUE`, bypass and replace cached instance metadata.

- instance_id:

  Instance identifier as advertised by `edr_instances()`. Reserved
  characters are percent-encoded. A literal `/` is rejected because it
  cannot safely round-trip as one HTTP path segment.

## Value

`edr_instances()` returns a tibble with one row per instance. It adds
`collection_id` to the normalized metadata columns returned by
[`edr_collections()`](https://ksonda.github.io/edr4r/reference/edr_collections.md),
keeping extent and output CRS semantics aligned.

`edr_instance()` returns the parsed instance metadata as a list.
