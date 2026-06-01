# List queryable parameters for a collection

Returns the JSON Schema describing parameters the collection accepts.
Useful for discovering valid `parameter_name` values.

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

A list with the queryables document.
