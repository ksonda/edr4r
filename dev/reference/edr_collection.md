# Get a single collection's metadata

Get a single collection's metadata

## Usage

``` r
edr_collection(client, collection_id)
```

## Arguments

- client:

  An `edr_client`.

- collection_id:

  Collection identifier as advertised by the server – e.g.
  `"monitoring-locations"` or `"daily-values"`.

## Value

A list with the raw collection document.
