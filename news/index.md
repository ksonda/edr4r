# Changelog

## edr4r (development version)

- Preserve mixed numeric/text CoverageJSON values as character instead
  of silently converting text values to `NA`.
- Make `edr_explore(method = "auto")` choose bulk spatial queries only
  when the matching spatial input is supplied.
- Warn when per-station
  [`edr_explore()`](https://ksonda.github.io/edr4r/reference/edr_explore.md)
  fallback fetches fail.
- Tighten collection-id, coordinate, and WKT validation.
- Add `max_match_distance` to
  [`edr_map()`](https://ksonda.github.io/edr4r/reference/edr_map.md) for
  bounded spatial matching.

## edr4r 0.1.0

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
