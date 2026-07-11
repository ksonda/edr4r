#' One-shot fetch + plot + map for a collection
#'
#' Convenience wrapper that plans a supported query, fetches data with
#' **one** bulk request via [edr_cube()] or [edr_area()] when possible,
#' and hands the result to [edr_map()] or [edr_plot()]. Station locations
#' are requested only when the result needs a station map or a per-location
#' fallback. Optionally writes a map to a self-contained HTML file.
#'
#' The default `method = "auto"` picks the cheapest route the
#' collection advertises in its `data_queries`:
#'
#' * **cube** -- one HTTP call returning a CoverageCollection across
#'   the whole bbox. Fast. Used when the collection supports `cube`
#'   *and* a `bbox` is supplied.
#' * **area** -- like cube but uses a polygon. Used when `coords` is
#'   supplied and the collection supports `area`.
#' * **position** -- one HTTP call at a point. Useful for vertical
#'   profiles returned by position queries.
#' * **per-location** -- the fallback: one HTTP call per station via
#'   [edr_location()]. Slower (N+1), used when neither spatial bulk
#'   query is supported or the matching spatial input was not supplied.
#'
#' Force a specific path by setting `method`. `coords` is required for
#' `area` and `position`; if `method = "cube"` and `bbox` is omitted,
#' the bbox is derived from the returned locations.
#'
#' @param client An `edr_client`.
#' @param collection_id Collection identifier.
#' @param bbox Optional numeric length-4 bbox. Used both to filter
#'   the locations index (if the server honours it) and as the bbox
#'   for the cube fetch in `method = "auto"`. If omitted with
#'   `method = "cube"`, derived from the bounding box of the returned
#'   locations sf.
#' @param coords Point coords for `position`, or polygon coords for
#'   `area`. Forwarded to [edr_position()] / [edr_area()].
#' @param datetime ISO-8601 interval forwarded to the data fetch.
#' @param parameter_name Character vector of parameter ids; forwarded
#'   to the data fetch. Use [edr_parameters()] to discover valid ids.
#' @param limit Optional cap on the number of stations to map.
#' @param record_limit Optional per-station record cap, passed through
#'   to [edr_location()] in the per-location path. Useful for servers
#'   (e.g. USGS waterdata) that cap responses at ~10 records by
#'   default. Ignored on the cube and area paths.
#' @param max_requests Maximum number of per-location data requests permitted
#'   in one call. Defaults to 100. Set to `Inf` only when an intentionally
#'   unbounded batch is acceptable. Ignored by bulk methods.
#' @param file If non-`NULL`, write the map to this HTML path via
#'   [edr_save_html()] and return `file` invisibly. Otherwise return
#'   the `leaflet` map.
#' @param popup Popup mode (forwarded to [edr_map()]).
#' @param method One of `"auto"` (default), `"cube"`, `"area"`,
#'   `"position"`, or `"per-location"`. See above.
#' @param output One of `"auto"` (default), `"map"`, `"plot"`, or
#'   `"data"`. `"auto"` returns a station map for station time-series
#'   results and an interactive coverage map for gridded/profile
#'   results.
#' @param plot_view Plot view passed to [edr_plot()] when returning a
#'   plot. Defaults to `"auto"`.
#' @param quiet If `FALSE` (default), print a cli progress bar when
#'   falling back to per-location fetches.
#' @param ... Forwarded to [edr_map()] when returning a map.
#' @param instance_id Optional collection instance identifier. When supplied,
#'   capability planning and every locations/data request use that instance.
#'   This keyword-only argument leaves existing positional calls unchanged.
#'
#' @return A `leaflet` htmlwidget, a `ggplot`, a tidy tibble/list when
#'   `output = "data"`, or `invisible(file)` when a map is saved.
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
                        max_requests   = 100L,
                        file           = NULL,
                        popup          = "plot+csv",
                        method         = c("auto", "cube", "area", "position", "per-location"),
                        output         = c("auto", "map", "plot", "data"),
                        plot_view      = c("auto", "time", "profile", "grid"),
                        quiet          = FALSE,
                        ...,
                        instance_id    = NULL) {
  check_client(client)
  collection_id <- check_collection_id(collection_id)
  method <- match.arg(method)
  output <- match.arg(output)
  plot_view <- match.arg(plot_view)

  if (!is.null(file) && output %in% c("plot", "data")) {
    cli::cli_abort(
      "{.arg file} is only supported when {.fn edr_explore} returns a map."
    )
  }
  check_max_requests(max_requests)

  method <- resolve_explore_method(
    client, collection_id, method, bbox, coords,
    instance_id = instance_id
  )
  # Fetch data first whenever the query already has enough spatial input.
  # This lets gridded/profile results return without probing an optional
  # /locations endpoint. Station locations are loaded lazily below only if
  # the parsed result actually needs a station map.
  needs_locations <- explore_needs_locations(method, bbox)
  locations <- if (needs_locations) {
    fetch_explore_locations(
      client, collection_id,
      bbox = bbox, limit = limit,
      instance_id = instance_id,
      required = method == "per-location" ||
        (method == "cube" && is.null(bbox))
    )
  } else {
    NULL
  }

  data <- fetch_explore_data(
    method, client, collection_id,
    bbox = bbox, coords = coords, locations = locations,
    datetime = datetime, parameter_name = parameter_name,
    record_limit = record_limit, max_requests = max_requests, quiet = quiet,
    instance_id = instance_id
  )

  if (output == "data") return(data)

  if (output == "plot") {
    plot_data <- explore_plot_data(data)
    plot_group <- if (".location_id" %in% names(plot_data)) {
      ".location_id"
    } else {
      "coverage_id"
    }
    return(edr_plot(
      plot_data,
      parameter = parameter_name,
      group = plot_group,
      view = plot_view
    ))
  }

  coverage_mode <- explore_coverage_map_mode(data, plot_view)
  if (!is.null(coverage_mode)) {
    m <- edr_map(
      data,
      mode = coverage_mode,
      initial = explore_initial_selection(parameter_name),
      ...
    )
    if (!is.null(file)) {
      edr_save_html(m, file)
      return(invisible(file))
    }
    return(m)
  }

  if (is.null(locations)) {
    locations <- fetch_explore_locations(
      client, collection_id,
      bbox = bbox, limit = limit,
      instance_id = instance_id,
      required = FALSE
    )
  }

  if (is.null(locations)) {
    cli::cli_abort(
      c("Could not build a station map for collection {.val {collection_id}}.",
        i = "Use {.code output = \"plot\"} or supply a collection with a spatial locations endpoint.")
    )
  }

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
resolve_explore_method <- function(client, collection_id, method, bbox, coords,
                                   instance_id = NULL) {
  if (method != "auto") return(method)
  if (!is.null(instance_id)) {
    instance <- tryCatch(
      edr_instance(client, collection_id, instance_id),
      error = function(e) {
        cli::cli_abort(
          c("Could not discover query capabilities for instance {.val {instance_id}} of collection {.val {collection_id}}.",
            i = "Automatic fallback was stopped before issuing per-location requests.",
            i = "Choose {.arg method} explicitly only if the endpoint's capabilities are known."),
          parent = e
        )
      }
    )
    dq <- query_names_best_effort(instance$data_queries)
  } else {
    cols <- tryCatch(
      edr_collections(client),
      error = function(e) {
        cli::cli_abort(
          c("Could not discover query capabilities for collection {.val {collection_id}}.",
            i = "Automatic fallback was stopped before issuing per-location requests.",
            i = "Choose {.arg method} explicitly only if the endpoint's capabilities are known."),
          parent = e
        )
      }
    )
    hit <- cols$data_queries[cols$id == collection_id]
    dq <- if (length(hit) == 1L) hit[[1]] else character(0)
  }
  if (!is.null(coords) && coords_looks_point(coords) && "position" %in% dq) {
    return("position")
  }
  if (!is.null(coords) && "area" %in% dq) return("area")
  if (!is.null(bbox) && "cube" %in% dq) return("cube")
  "per-location"
}

explore_needs_locations <- function(method, bbox) {
  method == "per-location" ||
    (method == "cube" && is.null(bbox))
}

fetch_explore_locations <- function(client, collection_id, bbox, limit,
                                    required = FALSE,
                                    instance_id = NULL) {
  if (!rlang::is_installed("sf")) {
    if (required) {
      cli::cli_abort(
        c("The {.pkg sf} package is required to enumerate locations for this exploration method.",
          i = "Install it or choose a bulk method with explicit spatial input.")
      )
    }
    return(NULL)
  }
  locations <- tryCatch(
    edr_locations(
      client, collection_id,
      bbox = bbox, limit = limit,
      instance_id = instance_id
    ),
    error = function(e) e
  )
  if (inherits(locations, "error")) {
    if (required) {
      cli::cli_abort(
        "Failed to retrieve locations for collection {.val {collection_id}}.",
        parent = locations
      )
    }
    return(NULL)
  }
  if (!inherits(locations, "sf")) {
    return(NULL)
  }
  if (!is.null(limit)) {
    locations <- utils::head(locations, n = as.integer(limit))
  }
  if (nrow(locations) == 0L) {
    return(NULL)
  }
  locations
}

fetch_explore_data <- function(method, client, collection_id,
                               bbox, coords, locations,
                               datetime, parameter_name,
                               record_limit, max_requests, quiet,
                               instance_id = NULL) {
  switch(method,
    cube = {
      bb <- bbox %||% {
        if (is.null(locations)) {
          cli::cli_abort(
            '{.code method = "cube"} requires {.arg bbox} when locations are unavailable.'
          )
        }
        sf_bbox_vec(locations)
      }
      resp <- edr_cube(
        client, collection_id,
        bbox = bb,
        datetime = datetime,
        parameter_name = parameter_name,
        instance_id = instance_id
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
        parameter_name = parameter_name,
        instance_id = instance_id
      )
      covjson_to_tibble(resp)
    },
    position = {
      if (is.null(coords)) {
        cli::cli_abort('{.code method = "position"} requires {.arg coords}.')
      }
      resp <- edr_position(
        client, collection_id,
        coords = coords,
        datetime = datetime,
        parameter_name = parameter_name,
        instance_id = instance_id
      )
      covjson_to_tibble(resp)
    },
    `per-location` = {
      if (is.null(locations)) {
        cli::cli_abort(
          c("Per-location exploration requires a spatial locations endpoint.",
            i = "Use a collection with locations, or supply spatial input for a supported bulk method.")
        )
      }
      ids <- detect_id_column(sf::st_drop_geometry(locations), id_col = NULL)
      fetch_per_station(
        client, collection_id, ids,
        datetime       = datetime,
        parameter_name = parameter_name,
        record_limit   = record_limit,
        max_requests   = max_requests,
        quiet          = quiet,
        instance_id    = instance_id
      )
    }
  )
}

coords_looks_point <- function(coords) {
  is_wkt_type(coords, "POINT") ||
    (is.numeric(coords) && length(coords) %in% c(2L, 3L)) ||
    (inherits(coords, c("sf", "sfc", "sfg")) &&
       rlang::is_installed("sf") &&
       is_wkt_type(sf_to_wkt(coords), "POINT"))
}

explore_coverage_map_mode <- function(data, plot_view) {
  if (is.data.frame(data)) {
    view <- detect_plot_view(data, plot_view)
    if (view %in% c("grid", "profile")) return(view)
  }
  NULL
}

explore_initial_selection <- function(parameter_name) {
  if (!is.null(parameter_name) && length(parameter_name) == 1L) {
    return(list(parameter = as.character(parameter_name)))
  }
  list()
}

explore_plot_data <- function(data) {
  if (is.data.frame(data)) return(data)
  if (is.list(data)) {
    pieces <- data[!vapply(data, is.null, logical(1))]
    if (length(pieces) == 0L) {
      cli::cli_abort("No fetched station data is available to plot.")
    }
    ids <- names(pieces)
    if (is.null(ids)) ids <- as.character(seq_along(pieces))
    pieces <- Map(function(piece, id) {
      piece$.location_id <- rep(as.character(id), nrow(piece))
      piece
    }, pieces, ids)
    return(vctrs::vec_rbind(!!!pieces))
  }
  data
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
                              record_limit = NULL,
                              max_requests = Inf,
                              quiet = FALSE,
                              instance_id = NULL) {
  n <- length(ids)
  check_max_requests(max_requests)
  if (is.finite(max_requests) && n > max_requests) {
    cli::cli_abort(c(
      "Per-location exploration would issue {n} data requests, exceeding {.arg max_requests} = {max_requests}.",
      i = "Reduce {.arg limit}, use a bulk query, or explicitly raise {.arg max_requests}."
    ))
  }
  if (!quiet && n > 1L) {
    cli::cli_inform(
      "Using per-location exploration: {n} data request{?s}."
    )
  }
  query <- common_query(datetime = datetime)
  plan <- tibble::tibble(
    request_id = seq_len(n),
    location_id = as.character(ids),
    datetime = rep(batch_datetime_label(query$datetime), n),
    status = rep("pending", n),
    n_rows = rep(NA_integer_, n)
  )
  dots <- list()
  if (!is.null(record_limit)) dots$limit <- record_limit

  executed <- run_location_batch_plan(
    client = client,
    collection_id = collection_id,
    plan = plan,
    parameter_name = parameter_name,
    z = NULL,
    crs = NULL,
    format = "covjson",
    dots = dots,
    on_error = "collect",
    progress = !quiet && n > 5L,
    instance_id = instance_id
  )

  out <- executed$results
  names(out) <- as.character(ids)
  failures <- as.list(executed$errors$message)
  names(failures) <- executed$errors$location_id
  warn_fetch_failures(failures, n)
  out
}

check_max_requests <- function(x, call = rlang::caller_env()) {
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || x <= 0 ||
      (!is.infinite(x) &&
       (x > .Machine$integer.max || x %% 1 != 0))) {
    cli::cli_abort(
      "{.arg max_requests} must be a positive integer or {.code Inf}.",
      call = call
    )
  }
  invisible(x)
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
