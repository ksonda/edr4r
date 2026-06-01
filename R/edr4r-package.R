#' edr4r: A tidy R client for OGC API - Environmental Data Retrieval
#'
#' `edr4r` talks to any service that implements
#' [OGC API - Environmental Data Retrieval](https://ogcapi.ogc.org/edr/).
#' It's general-purpose, but most of the testing and real-world use to
#' date has been against in-situ monitoring networks -- the kind of
#' service that exposes stream gauges, weather stations, snow telemetry,
#' or reservoir telemetry as EDR collections.
#'
#' Two example endpoints worth pointing it at:
#'
#' * [USGS waterdata OGC API](https://api.waterdata.usgs.gov/ogcapi/beta/)
#' * [Western Water Datahub](https://api.wwdh.internetofwater.app)
#'   (a [pygeoapi](https://pygeoapi.io) deployment)
#'
#' A typical session looks like:
#'
#' 1. Build a client with [edr_client()].
#' 2. Discover what's on offer with [edr_collections()] and
#'    [edr_queryables()].
#' 3. Pull data with [edr_locations()] / [edr_location()], [edr_cube()],
#'    [edr_area()], [edr_position()], or the less common
#'    [edr_radius()] / [edr_trajectory()] / [edr_corridor()].
#' 4. Flatten the response with [covjson_to_tibble()] (for CoverageJSON)
#'    or [geojson_to_sf()] (for GeoJSON).
#'
#' For everything the high-level verbs don't cover, [edr_request()] is
#' the raw escape hatch.
#'
#' @keywords internal
"_PACKAGE"

#' @importFrom rlang %||%
NULL
