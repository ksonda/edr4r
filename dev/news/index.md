# Changelog

## edr4r (development version)

- Preserve mixed numeric/text CoverageJSON values as character instead
  of silently converting text values to `NA`.
- Make `edr_explore(method = "auto")` choose bulk spatial queries only
  when the matching spatial input is supplied.
- Add grid and vertical-profile plot views to
  [`edr_plot()`](https://ksonda.github.io/edr4r/dev/reference/edr_plot.md),
  with automatic view detection.
- Allow
  [`edr_explore()`](https://ksonda.github.io/edr4r/dev/reference/edr_explore.md)
  to return plots or data for gridded/profile coverage queries,
  including `method = "position"` for profile-style responses.
- Add interactive coverage maps to
  [`edr_map()`](https://ksonda.github.io/edr4r/dev/reference/edr_map.md)
  and
  [`edr_explore()`](https://ksonda.github.io/edr4r/dev/reference/edr_explore.md),
  with in-map selectors for gridded coverage slices (`parameter`,
  `datetime`, `z`) and profile selectors for `parameter` / `datetime`.
- Materialize CoverageJSON regular-grid axes declared with `start`,
  `stop`, and `num`, as used by the WWDH `usgs-prism` collection.
- Warn when per-station
  [`edr_explore()`](https://ksonda.github.io/edr4r/dev/reference/edr_explore.md)
  fallback fetches fail.
- Tighten collection-id, coordinate, and WKT validation.
- Add `max_match_distance` to
  [`edr_map()`](https://ksonda.github.io/edr4r/dev/reference/edr_map.md)
  for bounded spatial matching.

## edr4r 0.1.0

- Initial release.
- Discovery:
  [`edr_landing()`](https://ksonda.github.io/edr4r/dev/reference/edr_landing.md),
  [`edr_conformance()`](https://ksonda.github.io/edr4r/dev/reference/edr_conformance.md),
  [`edr_collections()`](https://ksonda.github.io/edr4r/dev/reference/edr_collections.md),
  [`edr_collection()`](https://ksonda.github.io/edr4r/dev/reference/edr_collection.md),
  [`edr_queryables()`](https://ksonda.github.io/edr4r/dev/reference/edr_queryables.md).
- Query verbs:
  [`edr_locations()`](https://ksonda.github.io/edr4r/dev/reference/edr_locations.md)
  /
  [`edr_location()`](https://ksonda.github.io/edr4r/dev/reference/edr_location.md),
  [`edr_items()`](https://ksonda.github.io/edr4r/dev/reference/edr_items.md)
  /
  [`edr_item()`](https://ksonda.github.io/edr4r/dev/reference/edr_items.md),
  [`edr_position()`](https://ksonda.github.io/edr4r/dev/reference/edr_position.md),
  [`edr_area()`](https://ksonda.github.io/edr4r/dev/reference/edr_area.md),
  [`edr_cube()`](https://ksonda.github.io/edr4r/dev/reference/edr_cube.md),
  [`edr_radius()`](https://ksonda.github.io/edr4r/dev/reference/edr_radius.md),
  [`edr_trajectory()`](https://ksonda.github.io/edr4r/dev/reference/edr_trajectory.md),
  [`edr_corridor()`](https://ksonda.github.io/edr4r/dev/reference/edr_corridor.md).
- Low-level escape hatch:
  [`edr_request()`](https://ksonda.github.io/edr4r/dev/reference/edr_request.md).
- Parsers:
  [`covjson_to_tibble()`](https://ksonda.github.io/edr4r/dev/reference/covjson_to_tibble.md)
  for CoverageJSON,
  [`geojson_to_sf()`](https://ksonda.github.io/edr4r/dev/reference/geojson_to_sf.md)
  for GeoJSON.
