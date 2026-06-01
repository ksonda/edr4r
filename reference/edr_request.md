# Perform a low-level EDR request

Generally you should not need to call this directly: the high-level
verbs
([`edr_locations()`](https://ksonda.github.io/edr4r/reference/edr_locations.md),
[`edr_area()`](https://ksonda.github.io/edr4r/reference/edr_area.md),
etc.) build the path and query string for you. Use `edr_request()` when
you need to hit a bespoke path or a non-standard parameter.

## Usage

``` r
edr_request(
  client,
  path,
  query = list(),
  format = c("json", "geojson", "covjson", "csv", "html", "raw"),
  parse = TRUE
)
```

## Arguments

- client:

  An `edr_client` from
  [`edr_client()`](https://ksonda.github.io/edr4r/reference/edr_client.md).

- path:

  Path under the base URL (with or without leading slash), e.g.
  `"collections/monitoring-locations/locations"`.

- query:

  Named list of query parameters. Values may be scalars or vectors;
  vectors are joined with `","`. `NULL` entries are dropped.

- format:

  Response format: one of `"json"` (default), `"geojson"`, `"covjson"`,
  `"csv"`, `"html"`, or `"raw"`. Passed as `?f=` (except `"covjson"`,
  which is sent as `?f=json` with a CoverageJSON `Accept` hint, since
  EDR servers return CovJSON via JSON).

- parse:

  If `TRUE` (default), parses JSON / GeoJSON / CovJSON bodies into R
  structures. If `FALSE`, returns the raw `httr2` response.

## Value

The parsed body (list / tibble / sf) or an `httr2_response` when
`parse = FALSE`.
