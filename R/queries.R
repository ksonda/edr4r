#' List locations in a collection
#'
#' Calls `GET /collections/{collection_id}/locations`. With no extra
#' filters, EDR servers typically return a GeoJSON `FeatureCollection`
#' of available locations.
#'
#' @param client An `edr_client`.
#' @param collection_id Collection identifier.
#' @param bbox Numeric vector of length 4 or 6
#'   (`c(minx, miny, maxx, maxy)` or with z).
#' @param datetime ISO-8601 instant or interval, e.g.
#'   `"2024-01-01/2024-12-31"` or `"2024-01-01/.."`.
#' @param parameter_name Character vector of parameter names to filter
#'   on. Sent as a comma-separated `parameter-name=` query.
#' @param crs Optional CRS URI for the response.
#' @param limit Maximum number of features to return.
#' @param format `"geojson"` (default) or `"json"`.
#' @param ... Additional query parameters passed through verbatim.
#'
#' @return When the server returns GeoJSON, an `sf` object if the `sf`
#'   package is installed, otherwise an `edr_response` wrapping the raw
#'   GeoJSON. When the server returns CoverageJSON, an `edr_response`.
#' @export
edr_locations <- function(client,
                          collection_id,
                          bbox = NULL,
                          datetime = NULL,
                          parameter_name = NULL,
                          crs = NULL,
                          limit = NULL,
                          format = c("geojson", "json"),
                          ...) {
  check_client(client)
  collection_id <- check_collection_id(collection_id)
  format <- match.arg(format)

  query <- common_query(
    bbox = bbox, datetime = datetime, parameter_name = parameter_name,
    crs = crs, limit = limit, ...
  )
  resp <- edr_request(
    client,
    paste0("collections/", collection_id, "/locations"),
    query  = query,
    format = format
  )
  promote_geojson(resp)
}

#' Get data for a single location
#'
#' Calls `GET /collections/{collection_id}/locations/{location_id}`.
#' Typically returns CoverageJSON; pass the result to
#' [covjson_to_tibble()] for a tidy data frame.
#'
#' @inheritParams edr_locations
#' @param location_id Identifier of the location. IDs vary by source:
#'   integers for USBR RISE, alphanumeric codes for SNOTEL/USACE,
#'   station triplets for AWDB forecasts (will be URL-encoded).
#' @param z Vertical level filter.
#' @param format `"covjson"` (default), `"geojson"`, `"csv"`, or `"json"`.
#' @export
edr_location <- function(client,
                         collection_id,
                         location_id,
                         datetime = NULL,
                         parameter_name = NULL,
                         z = NULL,
                         crs = NULL,
                         format = c("covjson", "geojson", "csv", "json"),
                         ...) {
  check_client(client)
  collection_id <- check_collection_id(collection_id)
  loc <- check_path_id(location_id, "location_id")
  format <- match.arg(format)

  query <- common_query(
    datetime = datetime, parameter_name = parameter_name,
    z = z, crs = crs, ...
  )
  edr_request(
    client,
    paste0("collections/", collection_id, "/locations/", loc),
    query  = query,
    format = format
  )
}

#' Items (OGC API Features) helpers
#'
#' Many EDR servers expose an OGC API Features `/items` endpoint
#' alongside the EDR queries. The Western Water Datahub providers
#' implement `items` as a thin stub used to register the collection as
#' both EDR and Features; non-trivial data is usually obtained via the
#' EDR queries.
#'
#' @inheritParams edr_locations
#' @export
edr_items <- function(client,
                      collection_id,
                      bbox = NULL,
                      datetime = NULL,
                      limit = NULL,
                      format = c("geojson", "json"),
                      ...) {
  check_client(client)
  collection_id <- check_collection_id(collection_id)
  format <- match.arg(format)

  query <- common_query(
    bbox = bbox, datetime = datetime, limit = limit, ...
  )
  resp <- edr_request(
    client,
    paste0("collections/", collection_id, "/items"),
    query  = query,
    format = format
  )
  promote_geojson(resp)
}

#' @rdname edr_items
#' @param item_id Identifier of a single feature.
#' @export
edr_item <- function(client,
                     collection_id,
                     item_id,
                     format = c("geojson", "json"),
                     ...) {
  check_client(client)
  collection_id <- check_collection_id(collection_id)
  it <- check_path_id(item_id, "item_id")
  format <- match.arg(format)
  resp <- edr_request(
    client,
    paste0("collections/", collection_id, "/items/", it),
    query  = list(...),
    format = format
  )
  promote_geojson(resp)
}

#' Position query (data at a point)
#'
#' Calls `GET /collections/{collection_id}/position` with a WKT POINT
#' in the `coords` parameter.
#'
#' @inheritParams edr_location
#' @param coords Either a length-2 numeric vector `c(lon, lat)`, a
#'   length-3 vector `c(lon, lat, z)`, or a WKT POINT string.
#' @export
edr_position <- function(client,
                         collection_id,
                         coords,
                         datetime = NULL,
                         parameter_name = NULL,
                         z = NULL,
                         crs = NULL,
                         format = c("covjson", "json"),
                         ...) {
  check_client(client)
  collection_id <- check_collection_id(collection_id)
  format <- match.arg(format)

  query <- common_query(
    coords         = to_wkt_point(coords),
    datetime       = datetime,
    parameter_name = parameter_name,
    z              = z,
    crs            = crs,
    ...
  )
  edr_request(
    client,
    paste0("collections/", collection_id, "/position"),
    query  = query,
    format = format
  )
}

#' Area query (data inside a polygon)
#'
#' Calls `GET /collections/{collection_id}/area` with a WKT POLYGON in
#' the `coords` parameter.
#'
#' @inheritParams edr_position
#' @param coords WKT polygon string, or a matrix / data.frame of
#'   `(lon, lat)` rows that will be closed into a POLYGON. May also be
#'   an `sf` / `sfc` polygon if `sf` is installed.
#' @export
edr_area <- function(client,
                     collection_id,
                     coords,
                     datetime = NULL,
                     parameter_name = NULL,
                     z = NULL,
                     crs = NULL,
                     format = c("covjson", "json"),
                     ...) {
  check_client(client)
  collection_id <- check_collection_id(collection_id)
  format <- match.arg(format)

  query <- common_query(
    coords         = to_wkt_polygon(coords),
    datetime       = datetime,
    parameter_name = parameter_name,
    z              = z,
    crs            = crs,
    ...
  )
  edr_request(
    client,
    paste0("collections/", collection_id, "/area"),
    query  = query,
    format = format
  )
}

#' Cube query (data inside a bounding box)
#'
#' Calls `GET /collections/{collection_id}/cube` with a bounding box.
#'
#' @inheritParams edr_area
#' @param bbox Numeric vector of length 4 or 6.
#' @export
edr_cube <- function(client,
                     collection_id,
                     bbox,
                     datetime = NULL,
                     parameter_name = NULL,
                     z = NULL,
                     crs = NULL,
                     format = c("covjson", "json"),
                     ...) {
  check_client(client)
  collection_id <- check_collection_id(collection_id)
  format <- match.arg(format)
  bbox <- check_bbox(bbox)

  query <- common_query(
    bbox           = bbox,
    datetime       = datetime,
    parameter_name = parameter_name,
    z              = z,
    crs            = crs,
    ...
  )
  edr_request(
    client,
    paste0("collections/", collection_id, "/cube"),
    query  = query,
    format = format
  )
}

#' Radius query (data within a radius of a point)
#'
#' Calls `GET /collections/{collection_id}/radius`.
#'
#' @inheritParams edr_position
#' @param within Radius value.
#' @param within_units Units of `within` (e.g. `"km"`, `"mi"`).
#' @export
edr_radius <- function(client,
                       collection_id,
                       coords,
                       within,
                       within_units = "km",
                       datetime = NULL,
                       parameter_name = NULL,
                       z = NULL,
                       crs = NULL,
                       format = c("covjson", "json"),
                       ...) {
  check_client(client)
  collection_id <- check_collection_id(collection_id)
  format <- match.arg(format)
  if (!is.numeric(within) || length(within) != 1L) {
    cli::cli_abort("{.arg within} must be a single numeric value.")
  }

  query <- common_query(
    coords         = to_wkt_point(coords),
    within         = within,
    `within-units` = within_units,
    datetime       = datetime,
    parameter_name = parameter_name,
    z              = z,
    crs            = crs,
    ...
  )
  edr_request(
    client,
    paste0("collections/", collection_id, "/radius"),
    query  = query,
    format = format
  )
}

#' Trajectory query (data along a path)
#'
#' Calls `GET /collections/{collection_id}/trajectory`.
#'
#' @inheritParams edr_position
#' @param coords WKT LINESTRING, a matrix / data.frame of `(lon, lat)`
#'   rows, or an `sfc` linestring.
#' @export
edr_trajectory <- function(client,
                           collection_id,
                           coords,
                           datetime = NULL,
                           parameter_name = NULL,
                           z = NULL,
                           crs = NULL,
                           format = c("covjson", "json"),
                           ...) {
  check_client(client)
  collection_id <- check_collection_id(collection_id)
  format <- match.arg(format)

  query <- common_query(
    coords         = to_wkt_linestring(coords),
    datetime       = datetime,
    parameter_name = parameter_name,
    z              = z,
    crs            = crs,
    ...
  )
  edr_request(
    client,
    paste0("collections/", collection_id, "/trajectory"),
    query  = query,
    format = format
  )
}

#' Corridor query (data along a path with a width)
#'
#' Calls `GET /collections/{collection_id}/corridor`.
#'
#' @inheritParams edr_trajectory
#' @param corridor_width Width of the corridor.
#' @param corridor_height Optional vertical extent.
#' @param width_units Units for `corridor_width`.
#' @param height_units Units for `corridor_height`.
#' @export
edr_corridor <- function(client,
                         collection_id,
                         coords,
                         corridor_width,
                         corridor_height = NULL,
                         width_units = "km",
                         height_units = "m",
                         datetime = NULL,
                         parameter_name = NULL,
                         z = NULL,
                         crs = NULL,
                         format = c("covjson", "json"),
                         ...) {
  check_client(client)
  collection_id <- check_collection_id(collection_id)
  format <- match.arg(format)

  query <- common_query(
    coords            = to_wkt_linestring(coords),
    `corridor-width`  = corridor_width,
    `width-units`     = width_units,
    `corridor-height` = corridor_height,
    `height-units`    = height_units,
    datetime          = datetime,
    parameter_name    = parameter_name,
    z                 = z,
    crs               = crs,
    ...
  )
  edr_request(
    client,
    paste0("collections/", collection_id, "/corridor"),
    query  = query,
    format = format
  )
}

# ---------------------------------------------------------------------
# query plumbing

common_query <- function(...) {
  args <- list(...)
  # Map snake_case R names to EDR kebab-case query params.
  rename <- c(
    parameter_name = "parameter-name",
    parameter      = "parameter-name",
    bbox_crs       = "bbox-crs"
  )
  nm <- names(args)
  hits <- nm %in% names(rename)
  nm[hits] <- unname(rename[nm[hits]])
  names(args) <- nm

  # bbox -> "minx,miny,maxx,maxy"
  if (!is.null(args$bbox)) {
    args$bbox <- paste(args$bbox, collapse = ",")
  }
  # datetime can be a 2-vector or a single string with "/".
  if (!is.null(args$datetime) && length(args$datetime) == 2L) {
    args$datetime <- paste(args$datetime, collapse = "/")
  }
  args
}

# Validate a single path-segment id (location_id / item_id) and return it
# percent-encoded. We pre-encode reserved chars because httr2's
# req_url_path_append() does NOT escape unsafe segment characters (space,
# '?', '#'); the later req_url_query() pass normalises the URL so
# segment-safe reserved chars (':' in AWDB triplets) come back literal.
# '/' is rejected outright: even when pre-encoded as %2F, URL normalisation
# and server-side decoding both turn it back into a path separator, so
# there is no safe round-trip for an id containing a slash.
check_path_id <- function(id, arg, call = rlang::caller_env()) {
  if (length(id) != 1L || is.na(id)) {
    cli::cli_abort("{.arg {arg}} must be a single non-NA value.", call = call)
  }
  id <- as.character(id)
  if (!nzchar(id)) {
    cli::cli_abort("{.arg {arg}} must be a non-empty string.", call = call)
  }
  if (grepl("/", id, fixed = TRUE)) {
    cli::cli_abort(
      c("{.arg {arg}} must not contain {.val /}.",
        i = "Path-segment ids cannot round-trip a literal slash through HTTP."),
      call = call
    )
  }
  utils::URLencode(id, reserved = TRUE)
}

check_bbox <- function(bbox, call = rlang::caller_env()) {
  if (!is.numeric(bbox) || !(length(bbox) %in% c(4L, 6L))) {
    cli::cli_abort(
      "{.arg bbox} must be a numeric vector of length 4 or 6.",
      call = call
    )
  }
  bbox
}
