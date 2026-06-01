# Convert a GeoJSON EDR response to an `sf` object

Convert a GeoJSON EDR response to an `sf` object

## Usage

``` r
geojson_to_sf(x)
```

## Arguments

- x:

  An `edr_response` wrapping GeoJSON (e.g. from
  [`edr_locations()`](https://ksonda.github.io/edr4r/reference/edr_locations.md))
  or a raw parsed GeoJSON list.

## Value

An `sf` object. Requires the `sf` package. If `sf` is not installed,
returns a tibble of feature properties (without geometry) and warns.
