# EDR service landing page

Retrieves the service root document, which advertises links to the
collections, conformance, and openapi endpoints.

## Usage

``` r
edr_landing(client, refresh = FALSE)
```

## Arguments

- client:

  An `edr_client`.

- refresh:

  If `TRUE`, bypass and replace any cached response. Discovery responses
  otherwise use the client's `cache_ttl`; see
  [`edr_client()`](https://ksonda.github.io/edr4r/reference/edr_client.md).

## Value

A list with the parsed landing document.
