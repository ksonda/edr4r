# Changelog

## edr4r 0.3.0 (development version)

- Add opt-in, bounded GeoJSON pagination to
  [`edr_locations()`](https://ksonda.github.io/edr4r/reference/edr_locations.md)
  and
  [`edr_items()`](https://ksonda.github.io/edr4r/reference/edr_items.md).
  The client follows server-advertised `rel = "next"` links, supports
  cursor- and offset-based servers, and refuses unsafe cross-origin
  continuations or silent partial results at configured caps.
- Add
  [`edr_location_batch()`](https://ksonda.github.io/edr4r/reference/edr_location_batch.md)
  for safe, finite, sequential multi-station pulls with stable
  request/data/error tables, explicit station provenance, and
  stop-or-collect failure handling.
- Add bounded calendar time-window planning to
  [`edr_location_batch()`](https://ksonda.github.io/edr4r/reference/edr_location_batch.md)
  with station-by-window request caps, month-end/leap-year handling,
  normalized window provenance, and optional exact boundary-row
  deduplication. Requests remain sequential so the existing retry and
  throttling policy stays in control.
- Add opt-in checkpoint/resume support for
  [`edr_location_batch()`](https://ksonda.github.io/edr4r/reference/edr_location_batch.md).
  Parsed successful and empty responses are installed atomically per
  request, so an interrupted bounded pull can reuse terminal windows
  while retrying only unresolved work. Checkpoints are locked,
  plan-fingerprinted, and reject incompatible or corrupt state before
  network activity.
- Reuse the batch execution engine inside per-location
  [`edr_explore()`](https://ksonda.github.io/edr4r/reference/edr_explore.md)
  while preserving its existing output and summary-warning contract.
- Accept finite, safely representable numeric strings in CoverageJSON
  ranges that declare a numeric `dataType`, as currently emitted by USGS
  waterdata, while rejecting text, overflow/underflow, and unsafe
  declared integers.
- Add
  [`edr_add_stations()`](https://ksonda.github.io/edr4r/reference/edr_add_stations.md)
  for composing one or more independently styled station groups over an
  existing coverage map, reusing interactive chart and CSV popups.
  Coverage layers now render in a lower Leaflet pane, grid legends
  identify the active parameter/unit, and grid colour scales support
  identity, square-root, and `log1p` transforms.
- Upgrade the cross-endpoint Lake Mead vignette to a precomputed
  interactive map: a Met Office population `Grid` beneath toggleable
  USGS and USBR/WWDH station groups with time-series popups. The full
  widget is deployed only on the pkgdown site; package builds retain a
  small static fallback.
- Remove a precomputed base64 map from the USGS vignette, reducing that
  source file by about 1 MB while retaining the runnable interactive-map
  example.

## edr4r 0.2.0 (development version)

- Add structured service and collection capability discovery, support
  checks, endpoint diagnostics, and per-client TTL caching for discovery
  metadata.
- Add collection-instance discovery and optional instance-scoped paths
  across all query verbs and
  [`edr_explore()`](https://ksonda.github.io/edr4r/reference/edr_explore.md).
- Add a documented compatibility contract plus frozen Met Office Labs
  metadata/terrain fixtures for deterministic cross-server tests.

## edr4r 0.1.1

CRAN release: 2026-07-10

- Harden CoverageJSON parsing: honor `NdArray$dataType`, preserve
  textual identifiers and invalid/mixed timestamps, validate array shape
  and axes, support tuple/composite trajectory axes, merge child
  parameter metadata, and fail clearly for tiled or externally
  referenced data.
- Return typed empty results for HTTP 204 responses, report single
  Coverage and Feature documents correctly, and reject JSON error bodies
  when CSV was requested.
- Retry transient transport failures by default, with a client option to
  disable them, and exercise retries against a real local HTTP server.
- Make `corridor_height` required, validate radius/corridor distances
  and units, and reject non-finite or reversed bounding boxes
  consistently.
- Make `edr_explore(method = "auto")` choose bulk spatial queries only
  when the matching spatial input is supplied. Capability discovery
  failures now stop before an accidental per-station request fan-out.
- Add a `max_requests` safety cap to per-location exploration, preserve
  station identity in combined plots, and avoid optional location
  discovery calls for grid/profile and data-only bulk results.
- Add grid and vertical-profile plot views to
  [`edr_plot()`](https://ksonda.github.io/edr4r/reference/edr_plot.md),
  with automatic view detection.
- Allow
  [`edr_explore()`](https://ksonda.github.io/edr4r/reference/edr_explore.md)
  to return plots or data for gridded/profile coverage queries,
  including `method = "position"` for profile-style responses.
- Add interactive coverage maps to
  [`edr_map()`](https://ksonda.github.io/edr4r/reference/edr_map.md) and
  [`edr_explore()`](https://ksonda.github.io/edr4r/reference/edr_explore.md),
  with in-map selectors for gridded coverage slices (`parameter`,
  `datetime`, `z`) and profile selectors for `parameter` / `datetime`.
- Materialize CoverageJSON regular-grid axes declared with `start`,
  `stop`, and `num`.
- Warn when per-station
  [`edr_explore()`](https://ksonda.github.io/edr4r/reference/edr_explore.md)
  fallback fetches fail.
- Tighten collection-id, coordinate, and WKT validation.
- Add `max_match_distance` to
  [`edr_map()`](https://ksonda.github.io/edr4r/reference/edr_map.md) for
  bounded spatial matching.
- Fix map filtering and matching so blank JavaScript values remain
  missing, requested parameters determine station availability, and all
  coverage groups assigned to the same station are retained.
- Run R CMD check and coverage workflows on the `dev` branch as well as
  the release branch.
- Add a real headless-Chrome smoke test for coverage-map controls,
  redraws, popups, and uncaught JavaScript errors.
- Document the non-operational Met Office Labs EDR demonstrator and
  probe one tiny terrain query in a weekly/manual, non-blocking
  interoperability job.

## edr4r 0.1.0

CRAN release: 2026-06-18

- Initial release.
- Discovery:
  [`edr_landing()`](https://ksonda.github.io/edr4r/reference/edr_landing.md),
  [`edr_conformance()`](https://ksonda.github.io/edr4r/reference/edr_conformance.md),
  [`edr_collections()`](https://ksonda.github.io/edr4r/reference/edr_collections.md),
  [`edr_collection()`](https://ksonda.github.io/edr4r/reference/edr_collection.md),
  [`edr_queryables()`](https://ksonda.github.io/edr4r/reference/edr_queryables.md).
- Query verbs:
  [`edr_locations()`](https://ksonda.github.io/edr4r/reference/edr_locations.md)
  /
  [`edr_location()`](https://ksonda.github.io/edr4r/reference/edr_location.md),
  [`edr_items()`](https://ksonda.github.io/edr4r/reference/edr_items.md)
  /
  [`edr_item()`](https://ksonda.github.io/edr4r/reference/edr_items.md),
  [`edr_position()`](https://ksonda.github.io/edr4r/reference/edr_position.md),
  [`edr_area()`](https://ksonda.github.io/edr4r/reference/edr_area.md),
  [`edr_cube()`](https://ksonda.github.io/edr4r/reference/edr_cube.md),
  [`edr_radius()`](https://ksonda.github.io/edr4r/reference/edr_radius.md),
  [`edr_trajectory()`](https://ksonda.github.io/edr4r/reference/edr_trajectory.md),
  [`edr_corridor()`](https://ksonda.github.io/edr4r/reference/edr_corridor.md).
- Low-level escape hatch:
  [`edr_request()`](https://ksonda.github.io/edr4r/reference/edr_request.md).
- Parsers:
  [`covjson_to_tibble()`](https://ksonda.github.io/edr4r/reference/covjson_to_tibble.md)
  for CoverageJSON,
  [`geojson_to_sf()`](https://ksonda.github.io/edr4r/reference/geojson_to_sf.md)
  for GeoJSON.
