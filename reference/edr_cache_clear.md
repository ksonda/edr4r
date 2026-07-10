# Clear cached EDR discovery metadata

Removes landing-page, conformance, collection, instance, and queryables
responses cached by a client. Data-query responses are never cached. The
cache is process-local and stored on the client. Copies of the same
client share that cache because they share its backing environment.

## Usage

``` r
edr_cache_clear(client)
```

## Arguments

- client:

  An
  [`edr_client()`](https://ksonda.github.io/edr4r/reference/edr_client.md).

## Value

`client`, invisibly. The client's cache is mutated in place.
