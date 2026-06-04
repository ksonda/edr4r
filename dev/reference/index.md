# Package index

## Client

Construct and configure an EDR client.

- [`edr_client()`](https://ksonda.github.io/edr4r/dev/reference/edr_client.md)
  : Create an EDR client

## Discovery

List collections, conformance classes, data parameters, and filterable
properties.

- [`edr_landing()`](https://ksonda.github.io/edr4r/dev/reference/edr_landing.md)
  : EDR service landing page
- [`edr_conformance()`](https://ksonda.github.io/edr4r/dev/reference/edr_conformance.md)
  : Declared OGC API conformance classes
- [`edr_collections()`](https://ksonda.github.io/edr4r/dev/reference/edr_collections.md)
  : List collections offered by the service
- [`edr_collection()`](https://ksonda.github.io/edr4r/dev/reference/edr_collection.md)
  : Get a single collection's metadata
- [`edr_parameters()`](https://ksonda.github.io/edr4r/dev/reference/edr_parameters.md)
  : List the data parameters a collection serves
- [`edr_queryables()`](https://ksonda.github.io/edr4r/dev/reference/edr_queryables.md)
  : Get the queryables (filter properties) for a collection

## Query verbs

Standard EDR query types (one helper per endpoint).

- [`edr_locations()`](https://ksonda.github.io/edr4r/dev/reference/edr_locations.md)
  : List locations in a collection
- [`edr_location()`](https://ksonda.github.io/edr4r/dev/reference/edr_location.md)
  : Get data for a single location
- [`edr_items()`](https://ksonda.github.io/edr4r/dev/reference/edr_items.md)
  [`edr_item()`](https://ksonda.github.io/edr4r/dev/reference/edr_items.md)
  : Items (OGC API Features) helpers
- [`edr_position()`](https://ksonda.github.io/edr4r/dev/reference/edr_position.md)
  : Position query (data at a point)
- [`edr_area()`](https://ksonda.github.io/edr4r/dev/reference/edr_area.md)
  : Area query (data inside a polygon)
- [`edr_cube()`](https://ksonda.github.io/edr4r/dev/reference/edr_cube.md)
  : Cube query (data inside a bounding box)
- [`edr_radius()`](https://ksonda.github.io/edr4r/dev/reference/edr_radius.md)
  : Radius query (data within a radius of a point)
- [`edr_trajectory()`](https://ksonda.github.io/edr4r/dev/reference/edr_trajectory.md)
  : Trajectory query (data along a path)
- [`edr_corridor()`](https://ksonda.github.io/edr4r/dev/reference/edr_corridor.md)
  : Corridor query (data along a path with a width)
- [`edr_request()`](https://ksonda.github.io/edr4r/dev/reference/edr_request.md)
  : Perform a low-level EDR request

## Parsers

Convert EDR responses to tidy R objects.

- [`covjson_to_tibble()`](https://ksonda.github.io/edr4r/dev/reference/covjson_to_tibble.md)
  : Convert a CoverageJSON response to a tidy tibble

- [`geojson_to_sf()`](https://ksonda.github.io/edr4r/dev/reference/geojson_to_sf.md)
  :

  Convert a GeoJSON EDR response to an `sf` object

## Visualize

Plot time series, map stations with popups, save to standalone HTML.

- [`edr_plot()`](https://ksonda.github.io/edr4r/dev/reference/edr_plot.md)
  : Plot an EDR response as a ggplot
- [`edr_map()`](https://ksonda.github.io/edr4r/dev/reference/edr_map.md)
  : Map EDR locations or coverage data
- [`edr_save_html()`](https://ksonda.github.io/edr4r/dev/reference/edr_save_html.md)
  : Save a map to a standalone HTML file
- [`edr_explore()`](https://ksonda.github.io/edr4r/dev/reference/edr_explore.md)
  : One-shot fetch + plot + map for a collection
