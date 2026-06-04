# List the data parameters a collection serves

Pulls the `parameter_names` block out of the collection document
(`GET /collections/{id}`) and flattens it into a tidy tibble. These are
the observed properties you can pass to `parameter_name =` on the query
verbs
([`edr_location()`](https://ksonda.github.io/edr4r/dev/reference/edr_location.md),
[`edr_cube()`](https://ksonda.github.io/edr4r/dev/reference/edr_cube.md),
etc.).

## Usage

``` r
edr_parameters(client, collection_id)
```

## Arguments

- client:

  An `edr_client`.

- collection_id:

  Collection identifier as advertised by the server – e.g.
  `"monitoring-locations"` or `"daily-values"`.

## Value

A tibble with one row per parameter. Columns: `id`, `name`,
`description`, `unit_symbol`, `unit_label`, `observed_property`.

## Details

EDR servers vary in how they key the `parameter_names` dictionary
(numeric IDs, short codes, etc.). The `id` column in the returned tibble
is the value to pass back as `parameter_name`; the `name` column is the
human-readable label.
