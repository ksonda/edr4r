# List the data parameters a collection serves

Pulls the `parameter_names` block out of a collection or instance
document and flattens it into a tidy tibble. These are the observed
properties you can pass to `parameter_name =` on the query verbs
([`edr_location()`](https://ksonda.github.io/edr4r/reference/edr_location.md),
[`edr_cube()`](https://ksonda.github.io/edr4r/reference/edr_cube.md),
etc.).

## Usage

``` r
edr_parameters(client, collection_id, refresh = FALSE, instance_id = NULL)
```

## Arguments

- client:

  An `edr_client`.

- collection_id:

  Collection identifier as advertised by the server – e.g.
  `"monitoring-locations"` or `"daily-values"`.

- refresh:

  If `TRUE`, bypass and replace any cached response. Discovery responses
  otherwise use the client's `cache_ttl`; see
  [`edr_client()`](https://ksonda.github.io/edr4r/reference/edr_client.md).

- instance_id:

  Optional collection instance identifier. When supplied, parameter
  metadata is read from that instance document rather than the parent
  collection document.

## Value

A tibble with one row per parameter. Columns include `id`, `name`,
`description`, `parameter_type`, `unit_symbol`, `unit_symbol_type`,
`unit_label`, `unit_definition`, `unit_id`, observed-property metadata,
`data_type`, `measurement_type`, `extent`, category metadata, and `raw`.

## Details

EDR servers vary in how they key the `parameter_names` dictionary
(numeric IDs, short codes, etc.). The `id` column in the returned tibble
is the value to pass back as `parameter_name`; the `name` column is the
human-readable label.
