# edr4r (development version)

* Preserve mixed numeric/text CoverageJSON values as character instead of
  silently converting text values to `NA`.
* Make `edr_explore(method = "auto")` choose bulk spatial queries only when
  the matching spatial input is supplied.
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
