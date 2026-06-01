#' One-shot fetch + plot + map for a collection
#'
#' Convenience wrapper that calls [edr_locations()] to find stations,
#' fetches one time series per station via [edr_location()], and hands
#' the lot to [edr_map()] for rendering. Optionally writes the map to a
#' selfcontained HTML file.
#'
#' This is intentionally simple: one HTTP call per station. For
#' collections that advertise `cube` or `area` you may prefer to fetch
#' all stations in a single bbox query and call [edr_map()] directly.
#' Pre-filter with `bbox =` (and/or `limit`) so you're not fetching
#' more stations than you want.
#'
#' @param client An `edr_client`.
#' @param collection_id Collection identifier.
#' @param bbox Optional numeric length-4 bbox passed to
#'   [edr_locations()]. Pre-filter when the collection is large.
#' @param datetime ISO-8601 interval forwarded to [edr_location()].
#' @param parameter_name Character vector of parameter ids; forwarded
#'   to [edr_location()]. Use [edr_parameters()] to discover valid
#'   ids.
#' @param limit Optional cap on the number of stations to map (after
#'   bbox filtering). Useful for collections with thousands of
#'   stations.
#' @param file If non-`NULL`, write the map to this HTML path via
#'   [edr_save_html()] and return `file` invisibly. Otherwise return
#'   the `leaflet` map.
#' @param popup Popup mode (forwarded to [edr_map()]).
#' @param quiet If `FALSE` (default), print a cli progress bar while
#'   fetching per-station time series.
#' @param ... Forwarded to [edr_map()].
#'
#' @return A `leaflet` htmlwidget, or `invisible(file)` when `file` is
#'   set.
#' @export
#'
#' @examples
#' \dontrun{
#' cl <- edr_client("https://api.wwdh.internetofwater.app")
#' edr_explore(
#'   cl, "rise-edr",
#'   bbox           = c(-116, 35.5, -114, 36.5),
#'   datetime       = "2023-01-01/2023-03-31",
#'   parameter_name = "3",
#'   limit          = 25,
#'   file           = tempfile(fileext = ".html")
#' )
#' }
edr_explore <- function(client,
                        collection_id,
                        bbox           = NULL,
                        datetime       = NULL,
                        parameter_name = NULL,
                        limit          = NULL,
                        file           = NULL,
                        popup          = "plot+csv",
                        quiet          = FALSE,
                        ...) {
  check_client(client)
  collection_id <- check_collection_id(collection_id)
  check_installed_for("sf", "explore a collection")

  locations <- edr_locations(
    client, collection_id,
    bbox  = bbox,
    limit = limit
  )
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

  ids <- detect_id_column(sf::st_drop_geometry(locations), id_col = NULL)
  data_list <- fetch_per_station(
    client, collection_id, ids,
    datetime = datetime,
    parameter_name = parameter_name,
    quiet = quiet
  )

  m <- edr_map(
    locations,
    data  = data_list,
    popup = popup,
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

fetch_per_station <- function(client, collection_id, ids,
                              datetime, parameter_name, quiet) {
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
  for (i in seq_along(ids)) {
    out[[i]] <- tryCatch(
      {
        resp <- edr_location(
          client, collection_id,
          location_id    = ids[[i]],
          datetime       = datetime,
          parameter_name = parameter_name
        )
        covjson_to_tibble(resp)
      },
      error = function(e) NULL  # 404 / no-data: silently skipped
    )
    if (!quiet && n > 5L) cli::cli_progress_update(.envir = parent.frame())
  }
  out
}
