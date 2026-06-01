#' Map EDR locations with optional per-station popups
#'
#' Builds a [leaflet] map of station features. When `data` is supplied,
#' each marker gets a popup containing a small inline plot of the
#' station's time series and a "Download CSV" link (the CSV is
#' embedded as a `data:` URI so the resulting HTML is selfcontained).
#'
#' `data` can be one of:
#'
#' * `NULL` -- just markers with the sf attribute table as a popup
#'   (when `popup = "table"` or `popup = "all"`).
#' * A long tibble (the output of [covjson_to_tibble()]) with one
#'   column matching the locations' id column. Set `location_col =`
#'   to the column in `data` that holds the location id and `id_col =`
#'   to the column in `locations`.
#' * A named list of tibbles, keyed by feature id. This is what
#'   [edr_explore()] passes when it fetches one time series per
#'   station — and the right shape when each station has its own
#'   CovJSON response, because server-assigned `coverage_id`s like
#'   `"1"` won't naturally match the feature id.
#'
#' @param locations An `sf` object from [edr_locations()] or an
#'   `edr_response` wrapping GeoJSON.
#' @param data See above. Defaults to `NULL`.
#' @param popup One of `"plot+csv"` (default), `"plot"`, `"csv"`,
#'   `"table"`, or `"all"`.
#' @param location_col Column in `data` carrying the location id when
#'   `data` is a single tibble. Default `"coverage_id"`.
#' @param id_col Column in `locations` to join on. If `NULL`, the
#'   function looks for `"id"` then `"_id"` then the first character
#'   column.
#' @param label_col Column in `locations` used for the popup heading.
#'   If `NULL`, tries `"name"`, `"locationName"`, `"title"`, then the
#'   detected id column.
#' @param parameter Optional character vector restricting which
#'   parameters get plotted in each popup.
#' @param plot_width,plot_height Popup plot dimensions in inches
#'   (passed to the underlying SVG device). Rendered at ~60 px/in.
#' @param tile_provider Leaflet basemap. Default `"CartoDB.Positron"`.
#' @param marker_radius,marker_color Marker styling.
#'
#' @return A `leaflet` htmlwidget. Pass it to [edr_save_html()] to
#'   write a selfcontained HTML file.
#' @export
edr_map <- function(locations,
                    data         = NULL,
                    popup        = c("plot+csv", "plot", "csv", "table", "all"),
                    location_col = "coverage_id",
                    id_col       = NULL,
                    label_col    = NULL,
                    parameter    = NULL,
                    plot_width   = 6,
                    plot_height  = 3,
                    tile_provider = "CartoDB.Positron",
                    marker_radius = 6,
                    marker_color  = "#2C7FB8") {
  check_installed_for("leaflet", "render maps")
  check_installed_for("sf",      "render maps")
  popup <- match.arg(popup)
  locations <- as_locations_sf(locations)

  needs_data <- popup %in% c("plot", "csv", "plot+csv", "all")
  if (needs_data && is.null(data)) {
    cli::cli_abort(
      c("{.arg data} is required for popup mode {.val {popup}}.",
        i = "Pass a tidy tibble, a named list of tibbles, or use {.val table}.")
    )
  }

  attr_table <- sf::st_drop_geometry(locations)
  ids    <- detect_id_column(attr_table, id_col)
  labels <- detect_labels(attr_table, label_col, ids)
  per_feature_data <- per_feature_split(data, ids, location_col)

  popups <- vapply(
    seq_along(ids),
    function(i) build_feature_popup(
      df          = per_feature_data[[i]],
      attrs       = if (popup %in% c("table", "all")) as.list(attr_table[i, , drop = FALSE]) else NULL,
      label       = labels[[i]],
      popup_mode  = popup,
      parameter   = parameter,
      plot_width  = plot_width,
      plot_height = plot_height,
      csv_name    = paste0("station-", ids[[i]], ".csv")
    ),
    character(1)
  )

  # Reduce non-point geometries (lines, polygons, mixed) to centroids so
  # we can place a single marker per feature. sf warns on lon/lat
  # centroids; suppress that since it's expected for monitoring sites.
  geom <- sf::st_geometry(locations)
  if (!all(sf::st_geometry_type(geom) == "POINT")) {
    geom <- suppressWarnings(sf::st_centroid(geom))
  }
  coords <- sf::st_coordinates(geom)

  m <- leaflet::leaflet() |>
    leaflet::addProviderTiles(tile_provider) |>
    leaflet::addCircleMarkers(
      lng         = coords[, 1],
      lat         = coords[, 2],
      radius      = marker_radius,
      color       = marker_color,
      stroke      = TRUE,
      weight      = 1,
      fillOpacity = 0.85,
      popup       = popups,
      label       = labels,
      popupOptions = leaflet::popupOptions(
        maxWidth = ceiling(plot_width * 60 + 40)
      )
    )

  if (nrow(coords) > 1L) {
    m <- leaflet::fitBounds(
      m,
      lng1 = min(coords[, 1]), lat1 = min(coords[, 2]),
      lng2 = max(coords[, 1]), lat2 = max(coords[, 2])
    )
  } else if (nrow(coords) == 1L) {
    m <- leaflet::setView(m, lng = coords[1, 1], lat = coords[1, 2], zoom = 9)
  }

  m
}

#' Save a map to a standalone HTML file
#'
#' Thin wrapper around [htmlwidgets::saveWidget()] for the leaflet
#' map returned by [edr_map()] or [edr_explore()]. With
#' `selfcontained = TRUE` (the default), embedded plot SVGs and CSV
#' download links live inside the file -- no sidecar directory.
#'
#' @param map A `leaflet` or `htmlwidget`.
#' @param file Path to write to.
#' @param selfcontained If `TRUE`, embed all assets in the file.
#' @param ... Forwarded to [htmlwidgets::saveWidget()].
#'
#' @return Invisibly returns `file`.
#' @export
edr_save_html <- function(map, file, selfcontained = TRUE, ...) {
  check_installed_for("htmlwidgets", "save HTML maps")
  htmlwidgets::saveWidget(map, file = file,
                          selfcontained = selfcontained, ...)
  invisible(file)
}

# ---------------------------------------------------------------------
# internals

detect_id_column <- function(df, id_col) {
  if (!is.null(id_col)) {
    if (!id_col %in% names(df)) {
      cli::cli_abort(
        "{.arg id_col} = {.val {id_col}} is not a column in {.arg locations}."
      )
    }
    return(as.character(df[[id_col]]))
  }
  for (candidate in c("id", "_id", "feature_id")) {
    if (candidate %in% names(df)) return(as.character(df[[candidate]]))
  }
  char_cols <- names(df)[vapply(df,
    function(x) is.character(x) || is.factor(x) || is.integer(x) || is.numeric(x),
    logical(1)
  )]
  if (length(char_cols) >= 1L) return(as.character(df[[char_cols[[1]]]]))
  cli::cli_abort(
    "Could not infer an id column in {.arg locations}; pass {.arg id_col}."
  )
}

detect_labels <- function(df, label_col, ids) {
  if (!is.null(label_col)) {
    if (!label_col %in% names(df)) {
      cli::cli_abort(
        "{.arg label_col} = {.val {label_col}} is not a column in {.arg locations}."
      )
    }
    return(as.character(df[[label_col]]))
  }
  for (candidate in c("name", "locationName", "title", "label")) {
    if (candidate %in% names(df)) return(as.character(df[[candidate]]))
  }
  ids
}

# Returns a list of per-feature data frames (or NULLs) aligned to `ids`.
per_feature_split <- function(data, ids, location_col) {
  if (is.null(data)) return(rep(list(NULL), length(ids)))
  if (is.list(data) && !is.data.frame(data)) {
    # Named list keyed by feature id.
    return(lapply(ids, function(i) data[[as.character(i)]]))
  }
  df <- as_tidy_data(data)
  if (!location_col %in% names(df)) {
    cli::cli_abort(
      "{.arg data} has no column {.field {location_col}}; pass {.arg location_col}."
    )
  }
  split_df <- split(df, as.character(df[[location_col]]))
  lapply(ids, function(i) split_df[[as.character(i)]])
}

build_feature_popup <- function(df,
                                attrs,
                                label,
                                popup_mode,
                                parameter,
                                plot_width,
                                plot_height,
                                csv_name) {
  if (is.null(df) || nrow(df) == 0L) {
    # No time series for this feature — fall back to label + attrs.
    return(feature_popup_html(
      attrs = attrs, label = label, mode = "table",
      plot_width = as.integer(plot_width * 60)
    ))
  }
  if (!is.null(parameter)) {
    df <- df[df$parameter %in% parameter, , drop = FALSE]
  }
  plot_uri <- NULL
  csv_uri  <- NULL
  if (popup_mode %in% c("plot", "plot+csv", "all")) {
    p <- edr_plot(df, parameter = parameter)
    plot_uri <- plot_to_svg_uri(p, width = plot_width, height = plot_height)
  }
  if (popup_mode %in% c("csv", "plot+csv", "all")) {
    csv_uri <- csv_data_uri(df)
  }
  feature_popup_html(
    plot_uri     = plot_uri,
    csv_uri      = csv_uri,
    attrs        = attrs,
    label        = label,
    mode         = popup_mode,
    csv_filename = csv_name,
    plot_width   = as.integer(plot_width * 60)
  )
}
