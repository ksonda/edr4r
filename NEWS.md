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
