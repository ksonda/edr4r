#' One-shot fetch + plot + map for a collection
#'
#' Convenience wrapper that finds stations via [edr_locations()],
#' fetches time series with **one** bulk request via [edr_cube()] or
#' [edr_area()] when the collection supports it, and hands the lot to
#' [edr_map()] for rendering. Optionally writes the map to a
#' selfcontained HTML file.
#'
#' The default `method = "auto"` picks the cheapest route the
#' collection advertises in its `data_queries`:
#'
#' * **cube** -- one HTTP call returning a CoverageCollection across
#'   the whole bbox. Fast. Used when the collection supports `cube`
#'   *and* a `bbox` is supplied.
#' * **area** -- like cube but uses a polygon. Used when `coords` is
#'   supplied and the collection supports `area`.
#' * **per-location** -- the fallback: one HTTP call per station via
#'   [edr_location()]. Slower (N+1), used when neither spatial bulk
#'   query is supported or the matching spatial input was not supplied.
#'
#' Force a specific path by setting `method`. `coords` is required for
#' `area`; if `method = "cube"` and `bbox` is omitted, the bbox is
#' derived from the returned locations.
#'
#' @param client An `edr_client`.
#' @param collection_id Collection identifier.
#' @param bbox Optional numeric length-4 bbox. Used both to filter
#'   the locations index (if the server honours it) and as the bbox
#'   for the cube fetch in `method = "auto"`. If omitted with
#'   `method = "cube"`, derived from the bounding box of the returned
#'   locations sf.
#' @param coords Polygon coords for `area`. Forwarded to [edr_area()].
#' @param datetime ISO-8601 interval forwarded to the data fetch.
#' @param parameter_name Character vector of parameter ids; forwarded
#'   to the data fetch. Use [edr_parameters()] to discover valid ids.
#' @param limit Optional cap on the number of stations to map.
#' @param record_limit Optional per-station record cap, passed through
#'   to [edr_location()] in the per-location path. Useful for servers
#'   (e.g. USGS waterdata) that cap responses at ~10 records by
#'   default. Ignored on the cube and area paths.
#' @param file If non-`NULL`, write the map to this HTML path via
#'   [edr_save_html()] and return `file` invisibly. Otherwise return
#'   the `leaflet` map.
#' @param popup Popup mode (forwarded to [edr_map()]).
#' @param method One of `"auto"` (default), `"cube"`, `"area"`, or
#'   `"per-location"`. See above.
#' @param quiet If `FALSE` (default), print a cli progress bar when
#'   falling back to per-location fetches.
#' @param ... Forwarded to [edr_map()].
#'
#' @return A `leaflet` htmlwidget, or `invisible(file)` when `file` is
#'   set.
#' @export
#'
#' @examples
#' \dontrun{
#' cl <- edr_client("https://api.wwdh.internetofwater.app")
#'
#' # One /cube call across a bbox -- fast.
#' edr_explore(
#'   cl, "rise-edr",
#'   bbox           = c(-116, 35.5, -114, 36.5),
#'   datetime       = "2023-01-01/2023-03-31",
#'   parameter_name = "3",
#'   file           = tempfile(fileext = ".html")
#' )
#' }
edr_explore <- function(client,
                        collection_id,
                        bbox           = NULL,
                        coords         = NULL,
                        datetime       = NULL,
                        parameter_name = NULL,
                        limit          = NULL,
                        record_limit   = NULL,
                        file           = NULL,
                        popup          = "plot+csv",
                        method         = c("auto", "cube", "area", "per-location"),
                        quiet          = FALSE,
                        ...) {
  check_client(client)
  collection_id <- check_collection_id(collection_id)
  check_installed_for("sf", "explore a collection")
  method <- match.arg(method)

  locations <- edr_locations(client, collection_id, bbox = bbox, limit = limit)
  if (!inherits(locations, "sf")) {
    cli::cli_abort(
      "The {.field locations} endpoint did not return a spatial result; install {.pkg sf} or use {.fn edr_map} directly."
    )
  }
  if (!is.null(limit)) {
    locations <- utils::head(locations, n = as.integer(limit))
  }
  if (nrow(locations) == 0L) {
    cli::cli_abort("No stations found for collection {.val {collection_id}}.")
  }

  method <- resolve_explore_method(client, collection_id, method, bbox, coords)

  data <- switch(method,
    cube = {
      bb <- bbox %||% sf_bbox_vec(locations)
      resp <- edr_cube(
        client, collection_id,
        bbox = bb,
        datetime = datetime,
        parameter_name = parameter_name
      )
      covjson_to_tibble(resp)
    },
    area = {
      if (is.null(coords)) {
        cli::cli_abort('{.code method = "area"} requires {.arg coords}.')
      }
      resp <- edr_area(
        client, collection_id,
        coords = coords,
        datetime = datetime,
        parameter_name = parameter_name
      )
      covjson_to_tibble(resp)
    },
    `per-location` = {
      ids <- detect_id_column(sf::st_drop_geometry(locations), id_col = NULL)
      fetch_per_station(
        client, collection_id, ids,
        datetime       = datetime,
        parameter_name = parameter_name,
        record_limit   = record_limit,
        quiet          = quiet
      )
    }
  )

  m <- edr_map(
    locations,
    data      = data,
    popup     = popup,
    parameter = parameter_name,
    ...
  )

  if (!is.null(file)) {
    edr_save_html(m, file)
    return(invisible(file))
  }
  m
}

# ---------------------------------------------------------------------
# internal

# Pick the cheapest data-fetch method the collection supports, taking
# user intent into account.
resolve_explore_method <- function(client, collection_id, method, bbox, coords) {
  if (method != "auto") return(method)
  cols <- tryCatch(edr_collections(client), error = function(e) NULL)
  dq <- if (!is.null(cols)) {
    hit <- cols$data_queries[cols$id == collection_id]
    if (length(hit) == 1L) hit[[1]] else character(0)
  } else character(0)
  if (!is.null(coords) && "area" %in% dq) return("area")
  if (!is.null(bbox) && "cube" %in% dq) return("cube")
  "per-location"
}

# Return c(minx, miny, maxx, maxy) from an sf object.
sf_bbox_vec <- function(x) {
  bb <- sf::st_bbox(x)
  as.numeric(bb[c("xmin", "ymin", "xmax", "ymax")])
}

# N+1 fallback: one /locations/{id} call per station, with a cli
# progress bar for larger batches.
fetch_per_station <- function(client, collection_id, ids,
                              datetime, parameter_name,
                              record_limit = NULL, quiet = FALSE) {
  n <- length(ids)
  if (!quiet && n > 5L) {
    cli::cli_progress_bar(
      "Fetching time series",
      total = n, .envir = parent.frame()
    )
    on.exit(cli::cli_progress_done(.envir = parent.frame()), add = TRUE)
  }
  out <- vector("list", n)
  names(out) <- as.character(ids)
  failures <- list()
  for (i in seq_along(ids)) {
    result <- tryCatch(
      {
        args <- list(
          client, collection_id,
          location_id    = ids[[i]],
          datetime       = datetime,
          parameter_name = parameter_name
        )
        if (!is.null(record_limit)) args$limit <- record_limit
        resp <- do.call(edr_location, args)
        covjson_to_tibble(resp)
      },
      error = function(e) {
        failures[[as.character(ids[[i]])]] <<- conditionMessage(e)
        NULL
      }
    )
    out[i] <- list(result)
    if (!quiet && n > 5L) cli::cli_progress_update(.envir = parent.frame())
  }
  warn_fetch_failures(failures, n)
  out
}

warn_fetch_failures <- function(failures, n) {
  if (length(failures) == 0L) return(invisible())
  ids <- names(failures)
  details <- paste0(ids, ": ", unlist(failures, use.names = FALSE))
  details <- paste(utils::head(details, 3L), collapse = "; ")
  cli::cli_warn(c(
    "Failed to fetch data for {length(failures)} of {n} stations.",
    i = "First failures: {details}"
  ))
  invisible()
}
