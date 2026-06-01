# Map EDR locations with optional per-station popups

Builds a
[leaflet::leaflet](https://rstudio.github.io/leaflet/reference/leaflet.html)
map of station features. When `data` is supplied, each marker gets a
popup containing a small inline plot of the station's time series and a
"Download CSV" link (the CSV is embedded as a `data:` URI so the
resulting HTML is selfcontained).

## Usage

``` r
edr_map(
  locations,
  data = NULL,
  popup = c("plot+csv", "plot", "csv", "table", "all"),
  location_col = "coverage_id",
  id_col = NULL,
  label_col = NULL,
  parameter = NULL,
  plot_width = 7,
  plot_height = 3.5,
  plot_dpi = 72,
  tile_provider = "CartoDB.Positron",
  marker_radius = 6,
  matched_color = "#2C7FB8",
  unmatched_color = "#BBBBBB",
  show_unmatched = TRUE,
  legend = TRUE
)
```

## Arguments

- locations:

  An `sf` object from
  [`edr_locations()`](https://ksonda.github.io/edr4r/reference/edr_locations.md)
  or an `edr_response` wrapping GeoJSON.

- data:

  See above. Defaults to `NULL`.

- popup:

  One of `"plot+csv"` (default), `"plot"`, `"csv"`, `"table"`, or
  `"all"`.

- location_col:

  Column in `data` carrying the location id when `data` is a single
  tibble. Default `"coverage_id"`.

- id_col:

  Column in `locations` to join on. If `NULL`, the function looks for
  `"id"` then `"_id"` then the first character column.

- label_col:

  Column in `locations` used for the popup heading. If `NULL`, tries
  `"name"`, `"locationName"`, `"title"`, then the detected id column.

- parameter:

  Optional character vector restricting which parameters get plotted in
  each popup.

- plot_width, plot_height:

  Popup plot dimensions in inches (passed to the underlying SVG device).
  Display size in pixels is `plot_width * plot_dpi` by
  `plot_height * plot_dpi`.

- plot_dpi:

  Display dots-per-inch for the inline SVG. Default 72; bump to 90+ if
  popups look small on hi-DPI displays.

- tile_provider:

  Leaflet basemap. Default `"CartoDB.Positron"`.

- marker_radius:

  Marker radius in pixels for stations that have time-series data.
  Data-less stations are drawn one pixel smaller.

- matched_color:

  Marker colour for stations that joined to a coverage in `data`.
  Default deep blue.

- unmatched_color:

  Marker colour for stations without data (only relevant when `data` is
  supplied and `show_unmatched = TRUE`). Default light grey.

- show_unmatched:

  If `TRUE` (default), data-less stations are drawn in `unmatched_color`
  so the user can see the full station network. Set to `FALSE` to drop
  them entirely. Ignored when `data` is `NULL`.

- legend:

  If `TRUE` (default), add a legend distinguishing stations with data
  from those without. Suppressed automatically when there are no
  unmatched markers to label.

## Value

A `leaflet` htmlwidget. Pass it to
[`edr_save_html()`](https://ksonda.github.io/edr4r/reference/edr_save_html.md)
to write a selfcontained HTML file.

## Details

`data` can be one of:

- `NULL` – just markers with the sf attribute table as a popup (when
  `popup = "table"` or `popup = "all"`).

- A long tibble (the output of
  [`covjson_to_tibble()`](https://ksonda.github.io/edr4r/reference/covjson_to_tibble.md))
  with one column matching the locations' id column. Set
  `location_col =` to the column in `data` that holds the location id
  and `id_col =` to the column in `locations`.

- A named list of tibbles, keyed by feature id. This is what
  [`edr_explore()`](https://ksonda.github.io/edr4r/reference/edr_explore.md)
  passes when it fetches one time series per station — and the right
  shape when each station has its own CovJSON response, because
  server-assigned `coverage_id`s like `"1"` won't naturally match the
  feature id.
