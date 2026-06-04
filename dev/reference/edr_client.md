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
  headers = NULL,
  verbose = FALSE
)
```

## Arguments

- base_url:

  Base URL of an [OGC API - EDR](https://ogcapi.ogc.org/edr/) service.
  Examples: the [USGS waterdata OGC
  API](https://api.waterdata.usgs.gov/ogcapi/beta/) at
  `"https://api.waterdata.usgs.gov/ogcapi/beta"`, the [Western Water
  Datahub](https://api.wwdh.internetofwater.app) at
  `"https://api.wwdh.internetofwater.app"`, or `"http://localhost:5005"`
  for a local [pygeoapi](https://pygeoapi.io) dev server. A trailing
  slash is optional.

- user_agent:

  String sent in the `User-Agent` header. Defaults to
  `"edr4r/<version> (+https://github.com/ksonda/edr4r)"`.

- timeout:

  Request timeout in seconds. Defaults to 60.

- max_tries:

  Maximum number of attempts per request. The client retries on 408,
  429, and 5xx responses with exponential backoff. Defaults to 3.

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
usgs <- edr_client("https://api.waterdata.usgs.gov/ogcapi/beta")
usgs
#> <edr_client>
#>   base_url:   <https://api.waterdata.usgs.gov/ogcapi/beta>
#>   user_agent: edr4r/0.1.0 (+https://github.com/ksonda/edr4r)
#>   timeout:    60s
#>   max_tries:  3
```
