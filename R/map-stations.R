#' Add station layers to an EDR map
#'
#' Adds monitoring-location markers and the same interactive chart, CSV, and
#' attribute popups used by [edr_map()] to an existing Leaflet widget. This is
#' useful for composing station observations over a gridded coverage map:
#' start with `edr_map(grid)` and add one or more station groups.
#'
#' Multiple calls can add independently styled or toggleable source groups.
#' Coverage maps place their cells in a lower Leaflet pane so these station
#' markers remain visible and clickable.
#'
#' @param map A `leaflet` htmlwidget, typically returned by [edr_map()].
#' @inheritParams edr_map
#' @param locations An `sf` object from [edr_locations()], an `edr_response`
#'   wrapping GeoJSON, or a GeoJSON `FeatureCollection`.
#' @param data Optional station observations: a tidy tibble with a location-id
#'   column, a named list of tibbles keyed by feature id, or `NULL` for
#'   attribute-only popups.
#' @param parameter Optional character vector restricting the rows of `data`
#'   used in popups. Filtered rows also determine whether a station is marked
#'   as having data.
#' @param group Optional Leaflet layer-group name. The default, `"Stations"`,
#'   makes the added markers available to [leaflet::addLayersControl()]. Pass
#'   `NULL` to retain the status groups used by a standalone station map
#'   (`"Has data"` and `"No data in window"`).
#' @param fit If `TRUE`, fit the map to the added station extent. Defaults to
#'   `FALSE` so adding stations does not replace an existing coverage extent.
#'
#' @return The updated `leaflet` htmlwidget.
#' @export
edr_add_stations <- function(map,
                             locations,
                             data               = NULL,
                             popup              = c("plot+csv", "plot", "csv", "table", "all"),
                             location_col       = "coverage_id",
                             id_col             = NULL,
                             label_col          = NULL,
                             parameter          = NULL,
                             plot_width         = 7,
                             plot_height        = 3.5,
                             plot_dpi           = 72,
                             marker_radius      = 6,
                             matched_color      = "#2C7FB8",
                             unmatched_color    = "#BBBBBB",
                             show_unmatched     = TRUE,
                             legend             = TRUE,
                             max_match_distance = NULL,
                             group              = "Stations",
                             fit                = FALSE) {
  check_installed_for("leaflet", "render maps")
  check_installed_for("sf", "render maps")
  check_leaflet_map(map)
  popup <- match.arg(popup)
  check_max_match_distance(max_match_distance)
  check_station_group(group)
  check_map_flag(fit, "fit")

  locations <- as_locations_sf(locations)

  needs_data <- popup %in% c("plot", "csv", "plot+csv", "all")
  if (needs_data && is.null(data)) {
    cli::cli_abort(
      c("{.arg data} is required for popup mode {.val {popup}}.",
        i = "Pass a tidy tibble, a named list of tibbles, or use {.val table}.")
    )
  }

  attr_table <- sf::st_drop_geometry(locations)
  ids <- detect_id_column(attr_table, id_col)
  labels <- detect_labels(attr_table, label_col, ids)
  per_feature_data <- per_feature_split(
    data, ids, location_col, locations, max_match_distance
  )
  if (!is.null(parameter)) {
    per_feature_data <- lapply(
      per_feature_data,
      function(df) {
        if (is.null(df)) return(NULL)
        filter_parameter_rows(df, parameter)
      }
    )
  }

  has_data <- if (is.null(data)) {
    rep(TRUE, length(ids))
  } else {
    vapply(
      per_feature_data,
      function(df) !is.null(df) && nrow(df) > 0L,
      logical(1)
    )
  }

  if (!is.null(data) && !show_unmatched) {
    keep <- has_data
    if (!any(keep)) {
      cli::cli_abort(
        c("No stations in {.arg locations} joined to {.arg data}.",
          i = "Check that ids overlap, or set {.code show_unmatched = TRUE}.")
      )
    }
    locations <- locations[keep, , drop = FALSE]
    attr_table <- attr_table[keep, , drop = FALSE]
    ids <- ids[keep]
    labels <- labels[keep]
    per_feature_data <- per_feature_data[keep]
    has_data <- has_data[keep]
  }

  popups <- vapply(
    seq_along(ids),
    function(i) build_feature_popup(
      df = per_feature_data[[i]],
      attrs = if (popup %in% c("table", "all")) {
        as.list(attr_table[i, , drop = FALSE])
      } else {
        NULL
      },
      label = labels[[i]],
      popup_mode = popup,
      plot_width = plot_width,
      plot_height = plot_height,
      plot_dpi = plot_dpi,
      csv_name = paste0("station-", ids[[i]], ".csv")
    ),
    character(1)
  )

  geom <- sf::st_geometry(locations)
  if (!all(sf::st_geometry_type(geom) == "POINT")) {
    geom <- suppressWarnings(sf::st_centroid(geom))
  }
  coords <- sf::st_coordinates(geom)
  lng <- as.numeric(coords[, 1])
  lat <- as.numeric(coords[, 2])

  popup_opts <- leaflet::popupOptions(
    maxWidth = popup_chart_width_px(plot_width, plot_dpi) + 72
  )
  marker_options <- leaflet::pathOptions(className = "edr-station-marker")
  matched_group <- group %||% "Has data"
  unmatched_group <- group %||% "No data in window"

  if (any(!has_data)) {
    idx <- which(!has_data)
    map <- leaflet::addCircleMarkers(
      map,
      lng = lng[idx],
      lat = lat[idx],
      radius = max(marker_radius - 1L, 3L),
      color = unmatched_color,
      stroke = TRUE,
      weight = 1,
      fillOpacity = 0.5,
      opacity = 0.6,
      popup = popups[idx],
      label = labels[idx],
      popupOptions = popup_opts,
      options = marker_options,
      group = unmatched_group
    )
  }
  if (any(has_data)) {
    idx <- which(has_data)
    map <- leaflet::addCircleMarkers(
      map,
      lng = lng[idx],
      lat = lat[idx],
      radius = marker_radius,
      color = matched_color,
      stroke = TRUE,
      weight = 1,
      fillOpacity = 0.9,
      opacity = 1,
      popup = popups[idx],
      label = labels[idx],
      popupOptions = popup_opts,
      options = marker_options,
      group = matched_group
    )
  }

  if (isTRUE(legend) && !is.null(data) && any(has_data) && any(!has_data)) {
    map <- leaflet::addLegend(
      map,
      position = "bottomright",
      colors = c(matched_color, unmatched_color),
      labels = c("Has data", "No data in window"),
      opacity = 0.9,
      title = group %||% "Stations"
    )
  }

  if (isTRUE(fit)) {
    map <- fit_station_extent(map, lng, lat)
  }

  if (popup %in% c("plot", "plot+csv", "all")) {
    check_installed_for("htmlwidgets", "render interactive popup charts")
    map <- ensure_popup_chart_hook(map)
  }

  map
}

fit_station_extent <- function(map, lng, lat) {
  if (length(lng) == 0L) return(map)

  coverage_hook <- coverage_render_hook_index(map)
  if (!is.na(coverage_hook)) {
    station_fit <- if (length(lng) == 1L) {
      list(type = "view", lng = lng[[1]], lat = lat[[1]], zoom = 9)
    } else {
      list(
        type = "bounds",
        xmin = min(lng), ymin = min(lat),
        xmax = max(lng), ymax = max(lat)
      )
    }
    map$jsHooks$render[[coverage_hook]]$data$station_fit <- station_fit
    return(map)
  }

  if (length(lng) > 1L) {
    return(leaflet::fitBounds(
      map,
      lng1 = min(lng), lat1 = min(lat),
      lng2 = max(lng), lat2 = max(lat)
    ))
  }
  leaflet::setView(map, lng = lng[[1]], lat = lat[[1]], zoom = 9)
}

coverage_render_hook_index <- function(map) {
  hooks <- map$jsHooks$render %||% list()
  matches <- which(vapply(
    hooks,
    function(hook) {
      is.list(hook) && is.list(hook$data) &&
        is.character(hook$code) && length(hook$code) == 1L &&
        grepl("edr-coverage-pane", hook$code, fixed = TRUE)
    },
    logical(1)
  ))
  if (length(matches) == 0L) NA_integer_ else matches[[length(matches)]]
}

ensure_popup_chart_hook <- function(map) {
  hooks <- map$jsHooks$render %||% list()
  has_hook <- any(vapply(
    hooks,
    function(hook) {
      code <- hook$code %||% ""
      grepl("edrRenderPopupCharts", code, fixed = TRUE)
    },
    logical(1)
  ))
  if (!has_hook) {
    map <- htmlwidgets::onRender(map, popup_chart_js())
  }
  map
}

check_leaflet_map <- function(map, call = rlang::caller_env()) {
  if (!inherits(map, "leaflet") || !inherits(map, "htmlwidget")) {
    cli::cli_abort(
      "{.arg map} must be a Leaflet htmlwidget.",
      call = call
    )
  }
  invisible(map)
}

check_station_group <- function(group, call = rlang::caller_env()) {
  if (is.null(group)) return(invisible(group))
  if (!is.character(group) || length(group) != 1L || is.na(group) ||
      !nzchar(trimws(group))) {
    cli::cli_abort(
      "{.arg group} must be a non-empty character value or {.code NULL}.",
      call = call
    )
  }
  invisible(group)
}

check_map_flag <- function(x, arg, call = rlang::caller_env()) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) {
    cli::cli_abort(
      "{.arg {arg}} must be {.code TRUE} or {.code FALSE}.",
      call = call
    )
  }
  invisible(x)
}
