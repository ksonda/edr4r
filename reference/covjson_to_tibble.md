# Convert a CoverageJSON response to a tidy tibble

Flattens a CoverageJSON `Coverage` or `CoverageCollection` into a long
tibble with one row per (coverage, parameter, domain position). Handles
primitive, regularly spaced, and composite tuple axes, including the
axes used by `Grid`, `PointSeries`, `MultiPointSeries`, and `Trajectory`
domains. Additional coordinate dimensions are appended as `.axis_*`
columns. Inline `NdArray` ranges are validated before they are
flattened.

## Usage

``` r
covjson_to_tibble(x, datetime_as_posix = TRUE)
```

## Arguments

- x:

  A CoverageJSON object: either an `edr_response` returned by
  [`edr_location()`](https://ksonda.github.io/edr4r/reference/edr_location.md)
  / [`edr_area()`](https://ksonda.github.io/edr4r/reference/edr_area.md)
  / [`edr_cube()`](https://ksonda.github.io/edr4r/reference/edr_cube.md)
  (etc.) with `format = "covjson"`, or the raw parsed list.

- datetime_as_posix:

  If `TRUE` (default), attempts to parse the time axis to `POSIXct`
  (UTC). Falls back to character on failure.

## Value

A tibble whose first columns are `coverage_id`, `parameter`,
`parameter_label`, `unit`, `datetime`, `x`, `y`, `z`, and `value`.
Columns that are absent from the source are filled with `NA`.
Nonstandard CoverageJSON coordinates are appended without changing row
cardinality, using names such as `.axis_realisations`. The tibble
carries an `edr_covjson_metadata` attribute with versioned, per-coverage
domain, axis, and effective referencing metadata.
