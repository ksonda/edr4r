# Fetch data for multiple EDR locations

Runs one or more
[`edr_location()`](https://ksonda.github.io/edr4r/reference/edr_location.md)
requests for each explicitly supplied location id. When `chunk` is
supplied, a bounded datetime interval is split into contiguous closed
windows and the complete station-by-window plan is validated before any
network activity. Requests remain sequential and in input order, and
`max_requests` guards the expanded plan against accidental fan-out.

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
  chunk = NULL,
  deduplicate = TRUE,
  checkpoint = NULL,
  resume = FALSE,
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

  Optional ISO-8601 instant or interval. With `chunk = NULL`, it is
  shared by every request; otherwise the bounded interval is split into
  per-request windows. Timestamp bounds are normalized to UTC before
  calendar arithmetic; up to six fractional-second digits are accepted
  when R can preserve them without loss.

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

- chunk:

  Optional positive-integer calendar interval such as `"1 day"`,
  `"2 weeks"`, `"1 month"`, or `"1 year"`. Requires a bounded `datetime`
  interval. Month/year boundaries use anchored calendar arithmetic, so a
  January 31 start advances to February 28/29 and then March 31.

- deduplicate:

  If `TRUE` (default), exact rows repeated by different time windows for
  the same location are retained only from the earliest request.
  Duplicates within one response, differing observations, and rows from
  different locations are preserved. Ignored when `chunk` is `NULL`.

- checkpoint:

  Optional directory used to persist each terminal successful or empty
  response. A new or empty directory is initialized after the complete
  request plan has passed validation. Checkpoints store parsed response
  data, but not client headers, query URLs, or errors.

- resume:

  If `TRUE`, reuse terminal responses in an existing compatible
  `checkpoint` and request only unresolved rows. If the directory does
  not yet exist, it is initialized, which supports rerunnable scripts.
  An existing checkpoint requires `resume = TRUE`. Defaults to `FALSE`.

- max_requests:

  Finite positive integer limiting the number of logical
  [`edr_location()`](https://ksonda.github.io/edr4r/reference/edr_location.md)
  calls in the complete plan. Transport-level retries do not increase
  this count. Defaults to 100.

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
`requests`, a typed request-status tibble whose `n_rows` values describe
raw responses before cross-window deduplication; `data`, a combined data
tibble; and `errors`, a typed tibble of collected conditions. The object
also records `collection_id`, `instance_id`, and `format`.

## Details

`format = "covjson"` responses are converted with
[`covjson_to_tibble()`](https://ksonda.github.io/edr4r/reference/covjson_to_tibble.md).
CSV responses are already parsed as tibbles by
[`edr_location()`](https://ksonda.github.io/edr4r/reference/edr_location.md).
Successful rows are combined with `.request_id` and `.location_id`
provenance columns.

Checkpoint requests remain sequential. Result files are written
atomically after parsing and before a request is marked complete in
memory. Errors are deliberately not terminal: a later call with
`resume = TRUE` retries them under the client's normal retry policy. A
checkpoint may contain the endpoint's returned observations, so protect
it like any other local data extract and resume it under the same
logical authorization context. Checkpointed clients must use an absolute
HTTP(S) base URL without an embedded query, fragment, username, or
password; rotating credentials belong in `client` headers and are not
written to the checkpoint.
