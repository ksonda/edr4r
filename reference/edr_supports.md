# Test an advertised EDR capability

Query names are matched case-insensitively. Format matching recognizes
common names and media types, including MIME parameters. With `query`
and `format`, query-specific formats take precedence and
collection-level formats are used only when the query advertises none.
With `format` alone, all top-level and query-specific formats are
searched.

## Usage

``` r
edr_supports(
  x,
  collection_id = NULL,
  instance_id = NULL,
  query = NULL,
  format = NULL,
  conformance = NULL,
  refresh = FALSE
)
```

## Arguments

- x:

  An
  [`edr_client()`](https://ksonda.github.io/edr4r/reference/edr_client.md)
  or an `edr_capabilities` snapshot.

- collection_id:

  Collection to inspect when `x` is a client. Required for query or
  format checks unless `x` is already collection/instance scoped.

- instance_id:

  Optional instance to inspect. Requires `collection_id` when `x` is a
  client.

- query:

  Optional scalar query type, such as `"cube"` or `"position"`.

- format:

  Optional scalar output format or media type.

- conformance:

  Optional conformance URI, namespace shorthand, or unambiguous final
  URI component.

- refresh:

  If `TRUE`, bypass and replace cached discovery metadata.

## Value

A single logical value. Multiple criteria use AND semantics. `FALSE`
means the capability was not advertised in the inspected metadata; it
does not prove the server cannot implement it.

## Details

Conformance checks accept full URIs, unambiguous final components such
as `"covjson"`, and namespace shorthand such as `"edr/core"` or
`"common/core"`. Bare `"core"` is rejected because multiple OGC API
standards advertise a core conformance class.
