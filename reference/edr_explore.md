# One-shot fetch + plot + map for a collection

Convenience wrapper that calls
[`edr_locations()`](https://ksonda.github.io/edr4r/reference/edr_locations.md)
to find stations, fetches one time series per station via
[`edr_location()`](https://ksonda.github.io/edr4r/reference/edr_location.md),
and hands the lot to
[`edr_map()`](https://ksonda.github.io/edr4r/reference/edr_map.md) for
rendering. Optionally writes the map to a selfcontained HTML file.

## Usage

``` r
edr_explore(
  client,
  collection_id,
  bbox = NULL,
  datetime = NULL,
  parameter_name = NULL,
  limit = NULL,
  file = NULL,
  popup = "plot+csv",
  quiet = FALSE,
  ...
)
```

## Arguments

- client:

  An `edr_client`.

- collection_id:

  Collection identifier.

- bbox:

  Optional numeric length-4 bbox passed to
  [`edr_locations()`](https://ksonda.github.io/edr4r/reference/edr_locations.md).
  Pre-filter when the collection is large.

- datetime:

  ISO-8601 interval forwarded to
  [`edr_location()`](https://ksonda.github.io/edr4r/reference/edr_location.md).

- parameter_name:

  Character vector of parameter ids; forwarded to
  [`edr_location()`](https://ksonda.github.io/edr4r/reference/edr_location.md).
  Use
  [`edr_parameters()`](https://ksonda.github.io/edr4r/reference/edr_parameters.md)
  to discover valid ids.

- limit:

  Optional cap on the number of stations to map (after bbox filtering).
  Useful for collections with thousands of stations.

- file:

  If non-`NULL`, write the map to this HTML path via
  [`edr_save_html()`](https://ksonda.github.io/edr4r/reference/edr_save_html.md)
  and return `file` invisibly. Otherwise return the `leaflet` map.

- popup:

  Popup mode (forwarded to
  [`edr_map()`](https://ksonda.github.io/edr4r/reference/edr_map.md)).

- quiet:

  If `FALSE` (default), print a cli progress bar while fetching
  per-station time series.

- ...:

  Forwarded to
  [`edr_map()`](https://ksonda.github.io/edr4r/reference/edr_map.md).

## Value

A `leaflet` htmlwidget, or `invisible(file)` when `file` is set.

## Details

This is intentionally simple: one HTTP call per station. For collections
that advertise `cube` or `area` you may prefer to fetch all stations in
a single bbox query and call
[`edr_map()`](https://ksonda.github.io/edr4r/reference/edr_map.md)
directly. Pre-filter with `bbox =` (and/or `limit`) so you're not
fetching more stations than you want.

## Examples

``` r
if (FALSE) { # \dontrun{
cl <- edr_client("https://api.wwdh.internetofwater.app")
edr_explore(
  cl, "rise-edr",
  bbox           = c(-116, 35.5, -114, 36.5),
  datetime       = "2023-01-01/2023-03-31",
  parameter_name = "3",
  limit          = 25,
  file           = tempfile(fileext = ".html")
)
} # }
```
