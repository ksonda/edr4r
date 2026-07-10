# EDR compatibility and supported scope

`edr4r` targets the JSON ecosystem around OGC API - Environmental Data
Retrieval. The EDR standard permits more encodings and deployment
patterns than this package promises to parse. This article makes that
boundary explicit so that a server advertising an EDR conformance class
is not mistaken for a guarantee that every `edr4r` workflow will work
unchanged.

## Client support

| Capability | Status in edr4r | Notes |
|----|----|----|
| Landing page, conformance, collections, parameters, queryables | Supported | JSON discovery documents |
| Collection instances | Supported | Discovery and instance-scoped query paths |
| `locations`, `items`, `position`, `area`, `cube`, `radius`, `trajectory`, `corridor` | Supported | Read-only HTTP GET helpers; the server may implement only a subset |
| CoverageJSON | Supported subset | Inline `Coverage`/`CoverageCollection` with primitive, regular, or tuple axes and inline `NdArray` ranges |
| GeoJSON | Supported | Converted to `sf` when installed; otherwise retained as an `edr_response` |
| CSV | Limited | Parsed by the low-level client and supported directly by location queries |
| NetCDF, GeoTIFF, GRIB and other native encodings | Download only | Use `edr_request(..., parse = FALSE)` with the server’s advertised `f` value; no native R conversion yet |
| External CoverageJSON domains/ranges and `TiledNdArray` | Not supported | Rejected explicitly rather than partially or silently parsed |
| Pagination/link following | Not yet supported | A single locations/items response is returned |
| HTTP 202/308 asynchronous polling | Not yet supported | HTTP 204 empty responses are supported |
| POST queries and EDR Part 2 Pub/Sub | Out of current scope | The package is a synchronous, read-only client |

CRS values are passed to the server as requested. `edr4r` does not
silently reproject CoverageJSON coordinates; GeoJSON reprojection is
available after conversion through `sf`.

## Return and failure contract

Discovery tables
([`edr_collections()`](https://ksonda.github.io/edr4r/reference/edr_collections.md),
[`edr_parameters()`](https://ksonda.github.io/edr4r/reference/edr_parameters.md),
and
[`edr_instances()`](https://ksonda.github.io/edr4r/reference/edr_instances.md))
return tibbles with stable scalar columns and list columns for metadata
that cannot be flattened without loss. Raw collection/instance documents
remain available in a `raw` list column. Detailed discovery calls return
the parsed JSON list.

CoverageJSON query verbs return an `edr_response`; convert it explicitly
with
[`covjson_to_tibble()`](https://ksonda.github.io/edr4r/reference/covjson_to_tibble.md).
GeoJSON collection verbs return `sf` when `sf` is installed and
otherwise retain an `edr_response`. CSV responses return a tibble. HTTP
204 produces a typed empty result rather than a parser failure.

Local argument and parser failures are raised before issuing unsafe
follow-up requests. HTTP failures retain their `httr2_http_*` status
classes and include a useful server error body when one is available.
[`edr_diagnose()`](https://ksonda.github.io/edr4r/reference/edr_diagnose.md)
is the exception: after validating its arguments, it records
metadata/network failures as `fail`, `warn`, or `skip` rows so one
broken discovery endpoint does not hide the rest of the report.

## Inspect before querying

The 0.2 discovery layer retains query-specific formats, units, CRS
details, extents, and parameter metadata instead of flattening them
away.

``` r

client <- edr_client("https://labs.metoffice.gov.uk/edr")

service <- edr_capabilities(client)
terrain <- edr_capabilities(client, "terrain_tiles")

edr_supports(client, "terrain_tiles", query = "position")
edr_supports(
  client, "terrain_tiles",
  query = "position", format = "CoverageJSON"
)

# Fresh, metadata-only probes; no data query is issued.
edr_diagnose(client, "terrain_tiles")
```

Discovery responses are cached per client for a bounded period. Use
`refresh = TRUE` on a discovery call when current server state matters,
or clear that client’s metadata with `edr_cache_clear(client)`.

## Verified endpoints

The table records direct compatibility checks, not a permanent
availability promise. Server metadata was last inspected on 2026-07-09.

| Endpoint | Role | Advertised query types observed | edr4r coverage |
|----|----|----|----|
| [USGS waterdata](https://api.waterdata.usgs.gov/ogcapi/beta/) | Operational U.S. streamgage service | `locations` | Collection/location discovery, station time series, CoverageJSON parsing, per-location exploration |
| [Western Water Datahub](https://api.wwdh.internetofwater.app) | Operational multi-network pygeoapi deployment | `locations`, `items`, `position`, `area`, `cube` | Discovery, parameters, station and bulk queries, plotting and mapping |
| [Met Office Labs](https://labs.metoffice.gov.uk/edr/collections?f=html) | Non-operational technical demonstrator | `locations`, `items`, `instances`, `position`, `area`, `cube`, `radius`, `trajectory` | Cross-implementation metadata, instances, query-specific formats, and small terrain CoverageJSON fixtures |

The Met Office service describes itself as an example rather than an
operational API. It is useful for interoperability testing because its
metadata exercises instances and richer query variables, but production
workflows must not depend on its availability.

## Frozen and live checks

Tests use small, reviewed fixtures so CRAN and pull-request checks are
deterministic and offline. Met Office fixtures retain the response
shapes needed for capability, instance, and single-Coverage parsing
tests while omitting large payloads and verbose WKT definitions.

A separate scheduled/manual workflow performs a tiny, non-blocking live
probe. An outage there does not fail package CI; it is evidence of
interoperability drift to investigate.

## What “supports EDR” means here

`edr4r` can construct every EDR Part 1 query path listed above, but a
particular server may not advertise or implement each path or encoding.
Use capability discovery rather than treating the existence of an R
function as a server guarantee. For an unfamiliar endpoint, start with
[`edr_diagnose()`](https://ksonda.github.io/edr4r/reference/edr_diagnose.md),
inspect collection capabilities, and then issue the smallest
representative query.
