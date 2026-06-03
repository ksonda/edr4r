# One-shot fetch + plot + map for a collection

Convenience wrapper that finds stations via
[`edr_locations()`](https://ksonda.github.io/edr4r/reference/edr_locations.md),
fetches time series with **one** bulk request via
[`edr_cube()`](https://ksonda.github.io/edr4r/reference/edr_cube.md) or
[`edr_area()`](https://ksonda.github.io/edr4r/reference/edr_area.md)
when the collection supports it, and hands the lot to
[`edr_map()`](https://ksonda.github.io/edr4r/reference/edr_map.md) for
rendering. Optionally writes the map to a selfcontained HTML file.

## Usage

``` r
edr_explore(
  client,
  collection_id,
  bbox = NULL,
  coords = NULL,
  datetime = NULL,
  parameter_name = NULL,
  limit = NULL,
  record_limit = NULL,
  file = NULL,
  popup = "plot+csv",
  method = c("auto", "cube", "area", "position", "per-location"),
  output = c("auto", "map", "plot", "data"),
  plot_view = c("auto", "time", "profile", "grid"),
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

  Optional numeric length-4 bbox. Used both to filter the locations
  index (if the server honours it) and as the bbox for the cube fetch in
  `method = "auto"`. If omitted with `method = "cube"`, derived from the
  bounding box of the returned locations sf.

- coords:

  Point coords for `position`, or polygon coords for `area`. Forwarded
  to
  [`edr_position()`](https://ksonda.github.io/edr4r/reference/edr_position.md)
  /
  [`edr_area()`](https://ksonda.github.io/edr4r/reference/edr_area.md).

- datetime:

  ISO-8601 interval forwarded to the data fetch.

- parameter_name:

  Character vector of parameter ids; forwarded to the data fetch. Use
  [`edr_parameters()`](https://ksonda.github.io/edr4r/reference/edr_parameters.md)
  to discover valid ids.

- limit:

  Optional cap on the number of stations to map.

- record_limit:

  Optional per-station record cap, passed through to
  [`edr_location()`](https://ksonda.github.io/edr4r/reference/edr_location.md)
  in the per-location path. Useful for servers (e.g. USGS waterdata)
  that cap responses at ~10 records by default. Ignored on the cube and
  area paths.

- file:

  If non-`NULL`, write the map to this HTML path via
  [`edr_save_html()`](https://ksonda.github.io/edr4r/reference/edr_save_html.md)
  and return `file` invisibly. Otherwise return the `leaflet` map.

- popup:

  Popup mode (forwarded to
  [`edr_map()`](https://ksonda.github.io/edr4r/reference/edr_map.md)).

- method:

  One of `"auto"` (default), `"cube"`, `"area"`, `"position"`, or
  `"per-location"`. See above.

- output:

  One of `"auto"` (default), `"map"`, `"plot"`, or `"data"`. `"auto"`
  returns a station map for station time-series results and an
  interactive coverage map for gridded/profile results.

- plot_view:

  Plot view passed to
  [`edr_plot()`](https://ksonda.github.io/edr4r/reference/edr_plot.md)
  when returning a plot. Defaults to `"auto"`.

- quiet:

  If `FALSE` (default), print a cli progress bar when falling back to
  per-location fetches.

- ...:

  Forwarded to
  [`edr_map()`](https://ksonda.github.io/edr4r/reference/edr_map.md)
  when returning a map.

## Value

A `leaflet` htmlwidget, a `ggplot`, a tidy tibble/list when
`output = "data"`, or `invisible(file)` when a map is saved.

## Details

The default `method = "auto"` picks the cheapest route the collection
advertises in its `data_queries`:

- **cube** – one HTTP call returning a CoverageCollection across the
  whole bbox. Fast. Used when the collection supports `cube` *and* a
  `bbox` is supplied.

- **area** – like cube but uses a polygon. Used when `coords` is
  supplied and the collection supports `area`.

- **position** – one HTTP call at a point. Useful for vertical profiles
  returned by position queries.

- **per-location** – the fallback: one HTTP call per station via
  [`edr_location()`](https://ksonda.github.io/edr4r/reference/edr_location.md).
  Slower (N+1), used when neither spatial bulk query is supported or the
  matching spatial input was not supplied.

Force a specific path by setting `method`. `coords` is required for
`area` and `position`; if `method = "cube"` and `bbox` is omitted, the
bbox is derived from the returned locations.

## Examples

``` r
if (FALSE) { # \dontrun{
cl <- edr_client("https://api.wwdh.internetofwater.app")

# One /cube call across a bbox -- fast.
edr_explore(
  cl, "rise-edr",
  bbox           = c(-116, 35.5, -114, 36.5),
  datetime       = "2023-01-01/2023-03-31",
  parameter_name = "3",
  file           = tempfile(fileext = ".html")
)
} # }
```
