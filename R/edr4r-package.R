#' edr4r: A tidy R client for OGC API - Environmental Data Retrieval
#'
#' `edr4r` talks to
#' [OGC API - Environmental Data Retrieval](https://ogcapi.ogc.org/edr/)
#' services with JSON discovery metadata and CoverageJSON, GeoJSON, or CSV
#' query responses. It's general-purpose, but most testing and real-world use to
#' date has been against in-situ monitoring networks -- the kind of
#' service that exposes stream gauges, weather stations, snow telemetry,
#' or reservoir telemetry as EDR collections.
#'
#' Two operational endpoints worth pointing it at:
#'
#' * [USGS waterdata OGC API](https://api.waterdata.usgs.gov/ogcapi/beta/)
#' * [Western Water Datahub](https://api.wwdh.internetofwater.app)
#'   (a [pygeoapi](https://pygeoapi.io) deployment)
#'
#' The [Met Office Labs EDR demonstrator](https://labs.metoffice.gov.uk/edr/collections?f=html)
#' is also useful for cross-server compatibility experiments. It is a
#' technical demonstrator, not an operational service, so its availability
#' and advertised data may change without notice.
#'
#' A typical session looks like:
#'
#' 1. Build a client with [edr_client()].
#' 2. Discover what's on offer with [edr_collections()],
#'    [edr_capabilities()], and [edr_queryables()].
#' 3. Pull data with [edr_locations()] / [edr_location()], bounded explicit
#'    station sets with [edr_location_batch()], [edr_cube()], [edr_area()],
#'    [edr_position()], or the less common
#'    [edr_radius()] / [edr_trajectory()] / [edr_corridor()]. Instance-scoped
#'    collections can be inspected with [edr_instances()].
#' 4. Flatten the response with [covjson_to_tibble()] (for CoverageJSON)
#'    or [geojson_to_sf()] (for GeoJSON).
#'
#' For everything the high-level verbs don't cover, [edr_request()] is
#' the raw escape hatch.
#'
#' @keywords internal
"_PACKAGE"

#' @importFrom rlang %||% .data
NULL
