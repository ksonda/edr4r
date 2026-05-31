#' edr4r: Client for OGC API - Environmental Data Retrieval
#'
#' An R client for OGC API - EDR endpoints. Designed against the
#' Western Water Datahub (WWDH) pygeoapi deployment, but works with any
#' compliant EDR service. Build a client with [edr_client()], discover
#' resources with [edr_collections()], and query data with
#' [edr_locations()], [edr_area()], [edr_cube()], [edr_position()], and
#' related verbs. Parse responses with [covjson_to_tibble()] and
#' [geojson_to_sf()].
#'
#' @keywords internal
"_PACKAGE"

#' @importFrom rlang %||%
NULL

# Avoid R CMD check NOTEs about undefined globals used inside
# parser pipelines.
utils::globalVariables(c(
  "location_id", "parameter", "value", "datetime", "x", "y", "z", "unit"
))
