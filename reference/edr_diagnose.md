# Diagnose an EDR endpoint's discovery surface

Performs small, read-only metadata requests and reports each check
rather than stopping at the first network or schema failure. No data
query is issued. Argument errors still stop immediately.

## Usage

``` r
edr_diagnose(client, collection_id = NULL, instance_id = NULL, refresh = TRUE)
```

## Arguments

- client:

  An
  [`edr_client()`](https://ksonda.github.io/edr4r/reference/edr_client.md).

- collection_id:

  Optional collection identifier.

- instance_id:

  Optional instance identifier. Requires `collection_id`.

- refresh:

  If `TRUE` (default), perform fresh probes and replace successful cache
  entries. Use `FALSE` to permit cached metadata.

## Value

A tibble with stable `check`, `status` (`"pass"`, `"warn"`, `"fail"`, or
`"skip"`), and `detail` columns.
