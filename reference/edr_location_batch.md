# Fetch data for multiple EDR locations

Runs one
[`edr_location()`](https://ksonda.github.io/edr4r/reference/edr_location.md)
request for each explicitly supplied location id. Requests are made
sequentially and in input order. The complete request plan is validated
before any network activity, and `max_requests` provides a finite guard
against accidental fan-out.

## Usage

``` r
edr_location_batch(
  client,
  collection_id,
  location_id,
  datetime = NULL,
  parameter_name = NULL,
  z = NULL,
  crs = NULL,
  format = c("covjson", "csv"),
  ...,
  max_requests = 100L,
  on_error = c("stop", "collect"),
  progress = interactive(),
  instance_id = NULL
)
```

## Arguments

- client:

  An
  [`edr_client()`](https://ksonda.github.io/edr4r/reference/edr_client.md).

- collection_id:

  Collection identifier.

- location_id:

  A non-empty character vector of unique location ids.

- datetime:

  Optional ISO-8601 instant or interval shared by every request.

- parameter_name:

  Optional character vector of parameter names shared by every request.

- z:

  Optional vertical level filter.

- crs:

  Optional CRS URI for the response.

- format:

  Either `"covjson"` (default) or `"csv"`.

- ...:

  Additional query parameters forwarded to every
  [`edr_location()`](https://ksonda.github.io/edr4r/reference/edr_location.md)
  request, such as `limit`.

- max_requests:

  Finite positive integer limiting the number of HTTP requests. Defaults
  to 100.

- on_error:

  Either `"stop"` (default), which re-signals the original condition
  immediately, or `"collect"`, which records failures and continues
  through the bounded request plan.

- progress:

  If `TRUE`, display a cli progress bar for multi-request batches.
  Defaults to
  [`interactive()`](https://rdrr.io/r/base/interactive.html).

- instance_id:

  Optional collection instance identifier. Every request remains beneath
  that instance path.

## Value

An object of class `edr_location_batch` and `edr_batch`. It contains
`requests`, a typed request-status tibble; `data`, a combined data
tibble; and `errors`, a typed tibble of collected conditions. The object
also records `collection_id`, `instance_id`, and `format`.

## Details

`format = "covjson"` responses are converted with
[`covjson_to_tibble()`](https://ksonda.github.io/edr4r/reference/covjson_to_tibble.md).
CSV responses are already parsed as tibbles by
[`edr_location()`](https://ksonda.github.io/edr4r/reference/edr_location.md).
Successful rows are combined with `.request_id` and `.location_id`
provenance columns.
