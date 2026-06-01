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
