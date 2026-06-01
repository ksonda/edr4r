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

  Collection identifier, e.g. `"rise-edr"`.

## Value

A list with the queryables document.
