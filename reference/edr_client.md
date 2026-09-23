# Create an EDR client

Builds a reusable client object that captures the base URL of an OGC
API - EDR service, a default user-agent, and HTTP options that are
applied to every request.

## Usage

``` r
edr_client(
  base_url,
  user_agent = NULL,
  timeout = 60,
  max_tries = 3,
  retry_on_failure = TRUE,
  cache_ttl = 300,
  headers = NULL,
  verbose = FALSE
)
```

## Arguments

- base_url:

  Base URL of an [OGC API - EDR](https://ogcapi.ogc.org/edr/) service.
  Examples: the [USGS waterdata OGC
  API](https://api.waterdata.usgs.gov/ogcapi/v1/) at
  `"https://api.waterdata.usgs.gov/ogcapi/v1"`, the [Western Water
  Datahub](https://api.wwdh.internetofwater.app) at
  `"https://api.wwdh.internetofwater.app"`, or `"http://localhost:5005"`
  for a local [pygeoapi](https://pygeoapi.io) dev server. A trailing
  slash is optional. Supply the service root; for USGS daily values,
  pass `"edr/daily"` as the `collection_id` to discovery and query
  functions.

- user_agent:

  String sent in the `User-Agent` header. Defaults to
  `"edr4r/<version> (+https://github.com/ksonda/edr4r)"`.

- timeout:

  Request timeout in seconds. Defaults to 60.

- max_tries:

  Maximum number of attempts per request. The client retries on 408,
  429, and 5xx responses with exponential backoff. Defaults to 3.

- retry_on_failure:

  If `TRUE` (default), retry low-level transport failures such as
  connection resets and transient DNS / TLS errors. EDR requests made by
  this package are read-only GET requests, so retrying them is safe.

- cache_ttl:

  Number of seconds to retain discovery responses in this client's
  in-memory cache. Defaults to 300 (five minutes). Use `0` to disable
  caching or `Inf` to retain metadata until
  [`edr_cache_clear()`](https://ksonda.github.io/edr4r/reference/edr_cache_clear.md)
  is called. Data-query responses are never cached.

- headers:

  Named character vector of extra headers attached to every request
  (e.g. `c(Authorization = "Bearer ...")`).

- verbose:

  If `TRUE`, prints request URLs to the console as they are made. Useful
  for debugging.

## Value

An object of class `edr_client`.

## Examples

``` r
usgs <- edr_client("https://api.waterdata.usgs.gov/ogcapi/v1")
usgs
#> <edr_client>
#>   base_url:   <https://api.waterdata.usgs.gov/ogcapi/v1>
#>   user_agent: edr4r/0.3.0 (+https://github.com/ksonda/edr4r)
#>   timeout:    60s
#>   max_tries:  3
#>   retry transport failures: TRUE
#>   discovery cache: 300s
```
