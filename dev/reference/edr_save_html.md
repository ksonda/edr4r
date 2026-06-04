# Save a map to a standalone HTML file

Thin wrapper around
[`htmlwidgets::saveWidget()`](https://rdrr.io/pkg/htmlwidgets/man/saveWidget.html)
for the leaflet map returned by
[`edr_map()`](https://ksonda.github.io/edr4r/dev/reference/edr_map.md)
or
[`edr_explore()`](https://ksonda.github.io/edr4r/dev/reference/edr_explore.md).
With `selfcontained = TRUE` (the default), popup chart data and CSV
download links live inside the file – no sidecar directory.

## Usage

``` r
edr_save_html(map, file, selfcontained = TRUE, ...)
```

## Arguments

- map:

  A `leaflet` or `htmlwidget`.

- file:

  Path to write to.

- selfcontained:

  If `TRUE`, embed all assets in the file.

- ...:

  Forwarded to
  [`htmlwidgets::saveWidget()`](https://rdrr.io/pkg/htmlwidgets/man/saveWidget.html).

## Value

Invisibly returns `file`.
