# edr4r (development version)

* Preserve mixed numeric/text CoverageJSON values as character instead of
  silently converting text values to `NA`.
* Make `edr_explore(method = "auto")` choose bulk spatial queries only when
  the matching spatial input is supplied.
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
