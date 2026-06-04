# Internal utilities: coordinate coercion to WKT and small helpers.
# Not exported.

# Format a number for WKT without scientific notation or trailing noise.
fmt_coord <- function(x) {
  formatC(x, format = "f", digits = 6, drop0trailing = TRUE)
}

is_wkt <- function(x) {
  is.character(x) && length(x) == 1L &&
    grepl("^\\s*(POINT|LINESTRING|POLYGON|MULTIPOINT|MULTILINESTRING|MULTIPOLYGON|GEOMETRYCOLLECTION)",
          x, ignore.case = TRUE)
}

is_wkt_type <- function(x, types) {
  is.character(x) && length(x) == 1L &&
    grepl(
      paste0("^\\s*(", paste(types, collapse = "|"), ")\\s*\\("),
      x,
      ignore.case = TRUE
    )
}

# Coerce an sf/sfc object to a single WKT string if sf is available.
sf_to_wkt <- function(x, call = rlang::caller_env()) {
  if (!rlang::is_installed("sf")) {
    cli::cli_abort(
      "An {.cls {class(x)[1]}} was supplied but the {.pkg sf} package is not installed.",
      call = call
    )
  }
  geom <- if (inherits(x, "sf")) sf::st_geometry(x) else x
  if (inherits(geom, "sfg")) {
    return(sf::st_as_text(geom))
  }
  if (length(geom) != 1L) {
    cli::cli_abort("Expected a single geometry, got {length(geom)}.", call = call)
  }
  sf::st_as_text(geom)
}

#' @keywords internal
to_wkt_point <- function(coords, call = rlang::caller_env()) {
  if (is_wkt_type(coords, "POINT")) return(coords)
  if (is_wkt(coords)) {
    cli::cli_abort("{.arg coords} must be a WKT POINT string.", call = call)
  }
  if (inherits(coords, c("sf", "sfc", "sfg"))) {
    wkt <- sf_to_wkt(coords, call = call)
    if (is_wkt_type(wkt, "POINT")) return(wkt)
    cli::cli_abort("{.arg coords} must be an sf POINT geometry.", call = call)
  }
  if (is.numeric(coords) && length(coords) %in% c(2L, 3L)) {
    check_coord_values(coords, call = call)
    return(sprintf("POINT(%s)", paste(fmt_coord(coords), collapse = " ")))
  }
  cli::cli_abort(
    "{.arg coords} must be a WKT POINT string, a length-2/3 numeric vector, or an sf point.",
    call = call
  )
}

#' @keywords internal
to_wkt_polygon <- function(coords, call = rlang::caller_env()) {
  if (is_wkt_type(coords, "POLYGON")) return(coords)
  if (is_wkt(coords)) {
    cli::cli_abort("{.arg coords} must be a WKT POLYGON string.", call = call)
  }
  if (inherits(coords, c("sf", "sfc", "sfg"))) {
    wkt <- sf_to_wkt(coords, call = call)
    if (is_wkt_type(wkt, "POLYGON")) return(wkt)
    cli::cli_abort("{.arg coords} must be an sf POLYGON geometry.", call = call)
  }
  ring <- as_coord_matrix(coords, min_rows = 3L, call = call)
  # Close the ring if needed.
  if (!isTRUE(all.equal(ring[1, ], ring[nrow(ring), ]))) {
    ring <- rbind(ring, ring[1, , drop = FALSE])
  }
  verts <- apply(ring, 1L, function(r) paste(fmt_coord(r), collapse = " "))
  sprintf("POLYGON((%s))", paste(verts, collapse = ", "))
}

#' @keywords internal
to_wkt_linestring <- function(coords, call = rlang::caller_env()) {
  if (is_wkt_type(coords, "LINESTRING")) return(coords)
  if (is_wkt(coords)) {
    cli::cli_abort("{.arg coords} must be a WKT LINESTRING string.", call = call)
  }
  if (inherits(coords, c("sf", "sfc", "sfg"))) {
    wkt <- sf_to_wkt(coords, call = call)
    if (is_wkt_type(wkt, "LINESTRING")) return(wkt)
    cli::cli_abort("{.arg coords} must be an sf LINESTRING geometry.", call = call)
  }
  m <- as_coord_matrix(coords, min_rows = 2L, call = call)
  verts <- apply(m, 1L, function(r) paste(fmt_coord(r), collapse = " "))
  sprintf("LINESTRING(%s)", paste(verts, collapse = ", "))
}

as_coord_matrix <- function(coords, min_rows = 1L, call = rlang::caller_env()) {
  if (is.data.frame(coords)) coords <- as.matrix(coords)
  if (is.matrix(coords) && ncol(coords) >= 2L) {
    out <- coords[, 1:2, drop = FALSE]
    if (!is.numeric(out)) {
      cli::cli_abort(
        "{.arg coords} must contain numeric coordinate columns.",
        call = call
      )
    }
    if (nrow(out) < min_rows) {
      cli::cli_abort(
        "{.arg coords} must have at least {min_rows} rows.",
        call = call
      )
    }
    check_coord_values(out, call = call)
    return(out)
  }
  cli::cli_abort(
    "{.arg coords} must be a 2-column matrix/data.frame of lon,lat, a WKT string, or an sf geometry.",
    call = call
  )
}

check_coord_values <- function(coords, call = rlang::caller_env()) {
  if (any(!is.finite(coords))) {
    cli::cli_abort(
      "{.arg coords} must contain only finite coordinate values.",
      call = call
    )
  }
  invisible(coords)
}

# If a GeoJSON edr_response can be promoted to sf, do so; else return it.
promote_geojson <- function(resp) {
  if (inherits(resp, "edr_geojson") && rlang::is_installed("sf")) {
    return(geojson_to_sf(resp))
  }
  resp
}
