# Add station layers to an EDR map

Adds monitoring-location markers and the same interactive chart, CSV,
and attribute popups used by
[`edr_map()`](https://ksonda.github.io/edr4r/reference/edr_map.md) to an
existing Leaflet widget. This is useful for composing station
observations over a gridded coverage map: start with `edr_map(grid)` and
add one or more station groups.

## Usage

``` r
edr_add_stations(
  map,
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
  marker_radius = 6,
  matched_color = "#2C7FB8",
  unmatched_color = "#BBBBBB",
  show_unmatched = TRUE,
  legend = TRUE,
  max_match_distance = NULL,
  group = "Stations",
  fit = FALSE
)
```

## Arguments

- map:

  A `leaflet` htmlwidget, typically returned by
  [`edr_map()`](https://ksonda.github.io/edr4r/reference/edr_map.md).

- locations:

  An `sf` object from
  [`edr_locations()`](https://ksonda.github.io/edr4r/reference/edr_locations.md),
  an `edr_response` wrapping GeoJSON, or a GeoJSON `FeatureCollection`.

- data:

  Optional station observations: a tidy tibble with a location-id
  column, a named list of tibbles keyed by feature id, or `NULL` for
  attribute-only popups.

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

  Optional character vector restricting the rows of `data` used in
  popups. Filtered rows also determine whether a station is marked as
  having data.

- plot_width, plot_height:

  Popup chart dimensions in inches. Display size in pixels is
  `plot_width * plot_dpi` by `plot_height * plot_dpi`, with a larger
  minimum size for readable interactive popups.

- plot_dpi:

  Display dots-per-inch for popup charts. Default 72; bump to 90+ if
  popups look small on hi-DPI displays.

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

- max_match_distance:

  Optional maximum coordinate distance for spatially matching `data`
  rows with `x` / `y` columns to stations. Units are those of the
  station coordinates. `NULL` (default) keeps the nearest-station
  fallback unlimited.

- group:

  Optional Leaflet layer-group name. The default, `"Stations"`, makes
  the added markers available to
  [`leaflet::addLayersControl()`](https://rstudio.github.io/leaflet/reference/addLayersControl.html).
  Pass `NULL` to retain the status groups used by a standalone station
  map (`"Has data"` and `"No data in window"`).

- fit:

  If `TRUE`, fit the map to the added station extent. Defaults to
  `FALSE` so adding stations does not replace an existing coverage
  extent.

## Value

The updated `leaflet` htmlwidget.

## Details

Multiple calls can add independently styled or toggleable source groups.
Coverage maps place their cells in a lower Leaflet pane so these station
markers remain visible and clickable.
