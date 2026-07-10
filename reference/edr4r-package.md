# edr4r: A tidy R client for OGC API - Environmental Data Retrieval

`edr4r` talks to [OGC API - Environmental Data
Retrieval](https://ogcapi.ogc.org/edr/) services with JSON discovery
metadata and CoverageJSON, GeoJSON, or CSV query responses. It's
general-purpose, but most testing and real-world use to date has been
against in-situ monitoring networks – the kind of service that exposes
stream gauges, weather stations, snow telemetry, or reservoir telemetry
as EDR collections.

## Details

Two operational endpoints worth pointing it at:

- [USGS waterdata OGC API](https://api.waterdata.usgs.gov/ogcapi/beta/)

- [Western Water Datahub](https://api.wwdh.internetofwater.app) (a
  [pygeoapi](https://pygeoapi.io) deployment)

The [Met Office Labs EDR
demonstrator](https://labs.metoffice.gov.uk/edr/collections?f=html) is
also useful for cross-server compatibility experiments. It is a
technical demonstrator, not an operational service, so its availability
and advertised data may change without notice.

A typical session looks like:

1.  Build a client with
    [`edr_client()`](https://ksonda.github.io/edr4r/reference/edr_client.md).

2.  Discover what's on offer with
    [`edr_collections()`](https://ksonda.github.io/edr4r/reference/edr_collections.md),
    [`edr_capabilities()`](https://ksonda.github.io/edr4r/reference/edr_capabilities.md),
    and
    [`edr_queryables()`](https://ksonda.github.io/edr4r/reference/edr_queryables.md).

3.  Pull data with
    [`edr_locations()`](https://ksonda.github.io/edr4r/reference/edr_locations.md)
    /
    [`edr_location()`](https://ksonda.github.io/edr4r/reference/edr_location.md),
    bounded explicit station sets with
    [`edr_location_batch()`](https://ksonda.github.io/edr4r/reference/edr_location_batch.md),
    [`edr_cube()`](https://ksonda.github.io/edr4r/reference/edr_cube.md),
    [`edr_area()`](https://ksonda.github.io/edr4r/reference/edr_area.md),
    [`edr_position()`](https://ksonda.github.io/edr4r/reference/edr_position.md),
    or the less common
    [`edr_radius()`](https://ksonda.github.io/edr4r/reference/edr_radius.md)
    /
    [`edr_trajectory()`](https://ksonda.github.io/edr4r/reference/edr_trajectory.md)
    /
    [`edr_corridor()`](https://ksonda.github.io/edr4r/reference/edr_corridor.md).
    Instance-scoped collections can be inspected with
    [`edr_instances()`](https://ksonda.github.io/edr4r/reference/edr_instances.md).

4.  Flatten the response with
    [`covjson_to_tibble()`](https://ksonda.github.io/edr4r/reference/covjson_to_tibble.md)
    (for CoverageJSON) or
    [`geojson_to_sf()`](https://ksonda.github.io/edr4r/reference/geojson_to_sf.md)
    (for GeoJSON).

For everything the high-level verbs don't cover,
[`edr_request()`](https://ksonda.github.io/edr4r/reference/edr_request.md)
is the raw escape hatch.

## See also

Useful links:

- <https://github.com/ksonda/edr4r>

- <https://ksonda.github.io/edr4r/>

- Report bugs at <https://github.com/ksonda/edr4r/issues>

## Author

**Maintainer**: Kyle Onda <konda@lincolninst.edu> \[copyright holder\]
