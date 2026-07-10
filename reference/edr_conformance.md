# Declared OGC API conformance classes

Declared OGC API conformance classes

## Usage

``` r
edr_conformance(client, refresh = FALSE)
```

## Arguments

- client:

  An `edr_client`.

- refresh:

  If `TRUE`, bypass and replace any cached response. Discovery responses
  otherwise use the client's `cache_ttl`; see
  [`edr_client()`](https://ksonda.github.io/edr4r/reference/edr_client.md).

## Value

A character vector of conformance class URIs.
