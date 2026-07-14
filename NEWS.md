# edr4r 0.3.0

* Supersede the GitHub-only `v0.2.0-rc.1` and `v0.3.0-rc.1` previews with the
  final 0.3.0 release.
* Preserve the id and properties of a top-level GeoJSON `Feature` when
  geometry conversion is unavailable, instead of returning an empty fallback
  tibble. An `id` property continues to take precedence over the top-level id,
  matching `sf`/GDAL conversion behavior.
* Add structured service and collection capability discovery, support checks,
  endpoint diagnostics, and per-client TTL caching for discovery metadata.
* Add collection-instance discovery and optional instance-scoped paths across
  all query verbs and `edr_explore()`.
* Add a documented compatibility contract plus frozen Met Office Labs
  metadata/terrain fixtures for deterministic cross-server tests.
* Preserve nonstandard CoverageJSON coordinates as appended `.axis_*` columns
  instead of silently discarding their identity. Batch deduplication now keeps
  distinct members, plots group/facet them, and coverage maps expose selectors
  and dimension-aware popups. A versioned `edr_covjson_metadata` attribute
  retains effective domain, axis, and referencing metadata across package
  binding and checkpoint/resume paths.
* Harden spatial visualization around CRS semantics. Coverage maps reject
  declared projected or other known non-WGS 84 CRSs and coordinates or
  inferred cell bounds outside Leaflet longitude/latitude ranges;
  missing/custom CoverageJSON references warn before a range-checked fallback.
  Station `sf` geometries are transformed to WGS 84 for display without
  changing source-CRS matching-distance behavior, and missing station CRS
  metadata warns before plausible coordinates are used as-is. Projected source
  coordinates remain valid in `edr_plot()` grids.
* Advance the location-batch checkpoint schema to version 2 so checkpoints
  written before custom-axis identity and CoverageJSON metadata preservation
  cannot be mixed with newly parsed rows.
* Add explicit `include_parameters = TRUE` support to
  `edr_location_batch()`. A full collection- or instance-scoped parameter
  catalog is attached once as `result$parameters`, without duplicating
  definitions on observation rows or silently adding discovery calls to the
  default batch path. Resumed checkpoints validate before metadata access and
  can attach fresh cached metadata without repeating completed data requests.
* Expand parameter discovery with instance-scoped `edr_parameters()`, explicit
  unit-definition and symbol-type fields, official EDR 1.1 `data-type`
  metadata, and preserved custom collection dimensions.
* Add EDR 1.1-compatible WKT `MULTIPOINT`, `MULTIPOLYGON`, and
  `MULTILINESTRING` query inputs, including Z/M/ZM dimensional markers. Named
  custom-dimension query parameters continue through `...`, and explicit
  advertised `f` tokens can override the pygeoapi-compatible `f=json` default.
* Add opt-in, bounded GeoJSON pagination to `edr_locations()` and
  `edr_items()`. The client follows server-advertised `rel = "next"` links,
  supports cursor- and offset-based servers, and refuses unsafe cross-origin
  continuations or silent partial results at configured caps.
* Add `edr_location_batch()` for safe, finite, sequential multi-station pulls
  with stable request/data/error tables, explicit station provenance, and
  stop-or-collect failure handling.
* Add bounded calendar time-window planning to `edr_location_batch()` with
  station-by-window request caps, month-end/leap-year handling, normalized
  window provenance, and optional exact boundary-row deduplication. Requests
  remain sequential so the existing retry and throttling policy stays in
  control.
* Add opt-in checkpoint/resume support for `edr_location_batch()`. Parsed
  successful and empty responses are installed atomically per request, so an
  interrupted bounded pull can reuse terminal windows while retrying only
  unresolved work. Checkpoints are locked, plan-fingerprinted, and reject
  incompatible or corrupt state before network activity.
* Reuse the batch execution engine inside per-location `edr_explore()` while
  preserving its existing output and summary-warning contract.
* Accept finite, safely representable numeric strings in CoverageJSON ranges
  that declare a numeric `dataType`, as currently emitted by USGS waterdata,
  while rejecting text, overflow/underflow, and unsafe declared integers.
* Add `edr_add_stations()` for composing one or more independently styled
  station groups over an existing coverage map, reusing interactive chart and
  CSV popups. Coverage layers now render in a lower Leaflet pane, grid legends
  identify the active parameter/unit, and grid colour scales support identity,
  square-root, and `log1p` transforms.
* Upgrade the cross-endpoint Lake Mead vignette to a precomputed interactive
  map that switches between Met Office population and Copernicus elevation
  grids beneath toggleable USGS and USBR/WWDH station groups with time-series
  popups. A companion plot facets discharge, gage height, and reservoir
  storage by parameter and unit. The full widget is deployed only on the
  pkgdown site; package builds retain a small faceted static fallback.
* Remove a precomputed base64 map from the USGS vignette, reducing that source
  file by about 1 MB while retaining the runnable interactive-map example.

# edr4r 0.1.1

* Harden CoverageJSON parsing: honor `NdArray$dataType`, preserve textual
  identifiers and invalid/mixed timestamps, validate array shape and axes,
  support tuple/composite trajectory axes, merge child parameter metadata,
  and fail clearly for tiled or externally referenced data.
* Return typed empty results for HTTP 204 responses, report single Coverage
  and Feature documents correctly, and reject JSON error bodies when CSV was
  requested.
* Retry transient transport failures by default, with a client option to
  disable them, and exercise retries against a real local HTTP server.
* Make `corridor_height` required, validate radius/corridor distances and
  units, and reject non-finite or reversed bounding boxes consistently.
* Make `edr_explore(method = "auto")` choose bulk spatial queries only when
  the matching spatial input is supplied. Capability discovery failures now
  stop before an accidental per-station request fan-out.
* Add a `max_requests` safety cap to per-location exploration, preserve
  station identity in combined plots, and avoid optional location discovery
  calls for grid/profile and data-only bulk results.
* Add grid and vertical-profile plot views to `edr_plot()`, with automatic
  view detection.
* Allow `edr_explore()` to return plots or data for gridded/profile coverage
  queries, including `method = "position"` for profile-style responses.
* Add interactive coverage maps to `edr_map()` and `edr_explore()`, with
  in-map selectors for gridded coverage slices (`parameter`, `datetime`, `z`)
  and profile selectors for `parameter` / `datetime`.
* Materialize CoverageJSON regular-grid axes declared with `start`, `stop`,
  and `num`.
* Warn when per-station `edr_explore()` fallback fetches fail.
* Tighten collection-id, coordinate, and WKT validation.
* Add `max_match_distance` to `edr_map()` for bounded spatial matching.
* Fix map filtering and matching so blank JavaScript values remain missing,
  requested parameters determine station availability, and all coverage
  groups assigned to the same station are retained.
* Run R CMD check and coverage workflows on the `dev` branch as well as the
  release branch.
* Add a real headless-Chrome smoke test for coverage-map controls, redraws,
  popups, and uncaught JavaScript errors.
* Document the non-operational Met Office Labs EDR demonstrator and probe one
  tiny terrain query in a weekly/manual, non-blocking interoperability job.

# edr4r 0.1.0

* Initial release.
* Discovery: `edr_landing()`, `edr_conformance()`, `edr_collections()`,
  `edr_collection()`, `edr_queryables()`.
* Query verbs: `edr_locations()` / `edr_location()`, `edr_items()` /
  `edr_item()`, `edr_position()`, `edr_area()`, `edr_cube()`, `edr_radius()`,
  `edr_trajectory()`, `edr_corridor()`.
* Low-level escape hatch: `edr_request()`.
* Parsers: `covjson_to_tibble()` for CoverageJSON, `geojson_to_sf()` for
  GeoJSON.
