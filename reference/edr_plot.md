# Plot an EDR time-series response as a ggplot

Convenience wrapper around
[`ggplot2::ggplot()`](https://ggplot2.tidyverse.org/reference/ggplot.html)
for the long tibble returned by
[`covjson_to_tibble()`](https://ksonda.github.io/edr4r/reference/covjson_to_tibble.md).
By default each parameter gets its own facet (so different units don't
share a y-axis), and each location is drawn in its own colour.

## Usage

``` r
edr_plot(
  data,
  parameter = NULL,
  group = "coverage_id",
  facet = "parameter",
  scales = "free_y",
  geom = c("line", "point", "both"),
  facet_labels = TRUE
)
```

## Arguments

- data:

  Either a tidy tibble from
  [`covjson_to_tibble()`](https://ksonda.github.io/edr4r/reference/covjson_to_tibble.md)
  or an `edr_response` / `edr_covjson` object (which we flatten with
  [`covjson_to_tibble()`](https://ksonda.github.io/edr4r/reference/covjson_to_tibble.md)
  for you).

- parameter:

  Optional character vector restricting to a subset of parameters.

- group:

  Column in `data` used for the colour aesthetic. Defaults to
  `"coverage_id"` (one colour per location). Set to `NULL` to disable.

- facet:

  Column to facet by. Defaults to `"parameter"` so each variable gets
  its own panel; pass `NULL` to plot everything on one axis.

- scales:

  `facet_wrap()` scales argument. Default `"free_y"` gives each
  parameter its own y-axis range.

- geom:

  One of `"line"`, `"point"`, or `"both"`.

- facet_labels:

  If `TRUE` (default), facet strip labels include the unit (e.g.
  `"discharge (ft3/s)"`).

## Value

A `ggplot` object.

## Examples

``` r
if (FALSE) { # \dontrun{
cl <- edr_client("https://api.wwdh.internetofwater.app")
resp <- edr_location(cl, "rise-edr",
                     location_id    = 3514,
                     datetime       = "2023-01-01/2023-06-30",
                     parameter_name = "3")
edr_plot(resp)
} # }
```
