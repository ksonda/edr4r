# Internal helpers for the visualization functions (edr_plot, edr_map,
# edr_explore). Not exported.

# Coerce an edr_response / edr_covjson / raw CovJSON list to a tidy tibble.
# Pass-through for data frames.
as_tidy_data <- function(x, call = rlang::caller_env()) {
  if (inherits(x, "edr_covjson") || inherits(x, "edr_response")) {
    return(covjson_to_tibble(x))
  }
  if (is.data.frame(x)) return(x)
  if (is.list(x) && (!is.null(x$type) || !is.null(x$coverages) || !is.null(x$domain))) {
    return(covjson_to_tibble(x))
  }
  cli::cli_abort(
    "{.arg data} must be a tidy tibble from {.fn covjson_to_tibble} or an {.cls edr_response}.",
    call = call
  )
}

# Coerce an edr_response / edr_geojson / GeoJSON list to an sf object.
# Pass-through for sf.
as_locations_sf <- function(x, call = rlang::caller_env()) {
  if (inherits(x, "sf")) return(x)
  if (inherits(x, "edr_geojson") || inherits(x, "edr_response") ||
      (is.list(x) && !is.null(x$type) && identical(x$type, "FeatureCollection"))) {
    return(geojson_to_sf(x))
  }
  cli::cli_abort(
    "{.arg locations} must be an {.cls sf} object or a GeoJSON {.cls edr_response}.",
    call = call
  )
}

# Render a ggplot to an inline SVG data URI. svglite preferred for output
# quality; grDevices::svg as a fallback so popups still work if svglite
# isn't installed.
plot_to_svg_uri <- function(plot, width = 6, height = 4) {
  check_installed_for("base64enc", "embed plots in popups")
  tmp <- tempfile(fileext = ".svg")
  on.exit(unlink(tmp), add = TRUE)

  if (rlang::is_installed("svglite")) {
    svglite::svglite(tmp, width = width, height = height)
  } else {
    grDevices::svg(tmp, width = width, height = height)
  }
  # Close the device unconditionally, even if print() throws.
  dev_id <- grDevices::dev.cur()
  on.exit(
    if (dev_id %in% grDevices::dev.list()) grDevices::dev.off(dev_id),
    add = TRUE, after = FALSE
  )
  print(plot)
  grDevices::dev.off(dev_id)

  svg <- paste(readLines(tmp, warn = FALSE), collapse = "\n")
  paste0(
    "data:image/svg+xml;base64,",
    base64enc::base64encode(charToRaw(svg))
  )
}

# Encode a data frame as a CSV data URI. The HTML side adds a
# download="..." attribute so browsers offer the right filename on click.
csv_data_uri <- function(df) {
  check_installed_for("base64enc", "embed CSV downloads in popups")
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp), add = TRUE)
  utils::write.csv(df, tmp, row.names = FALSE)
  csv <- paste(readLines(tmp, warn = FALSE), collapse = "\n")
  paste0(
    "data:text/csv;base64,",
    base64enc::base64encode(charToRaw(csv))
  )
}

# Build popup HTML for one feature. `mode` selects content:
#   "plot"     - just the interactive chart
#   "csv"      - just a download link
#   "plot+csv" - both (default)
#   "table"    - just the attributes table
#   "all"      - attribute table + plot + csv
feature_popup_html <- function(plot_uri     = NULL,
                               chart_payload = NULL,
                               csv_uri      = NULL,
                               attrs        = NULL,
                               label        = NULL,
                               mode         = "plot+csv",
                               csv_filename = "data.csv",
                               plot_width   = 560,
                               plot_height  = 300) {
  pieces <- character(0)
  if (!is.null(label)) {
    pieces <- c(pieces, sprintf(
      "<div style='font-weight:600; margin-bottom:4px'>%s</div>",
      escape_html(label)
    ))
  }
  if (mode %in% c("table", "all") && length(attrs) > 0L) {
    pieces <- c(pieces, attrs_to_table_html(attrs))
  }
  if (mode %in% c("plot", "plot+csv", "all") && !is.null(chart_payload)) {
    pieces <- c(pieces, interactive_chart_html(
      chart_payload,
      width = plot_width,
      height = plot_height
    ))
  } else if (mode %in% c("plot", "plot+csv", "all") && !is.null(plot_uri)) {
    pieces <- c(pieces, sprintf(
      "<img src='%s' style='width:%dpx; max-width:100%%; display:block' alt='time series' />",
      plot_uri, as.integer(plot_width)
    ))
  }
  if (mode %in% c("csv", "plot+csv", "all") && !is.null(csv_uri)) {
    pieces <- c(pieces, sprintf(
      "<div style='margin-top:6px'><a href='%s' download='%s'>Download CSV</a></div>",
      csv_uri, escape_html(csv_filename)
    ))
  }
  paste0(
    "<div style='font-family:system-ui,sans-serif; font-size:12px; max-width:",
    plot_width + 32, "px'>",
    paste(pieces, collapse = ""),
    "</div>"
  )
}

popup_chart_width_px <- function(plot_width, plot_dpi) {
  max(as.integer(plot_width * plot_dpi), 560L)
}

popup_chart_height_px <- function(plot_height, plot_dpi) {
  max(as.integer(plot_height * plot_dpi), 300L)
}

interactive_chart_payload <- function(df, title = NULL, width = 560, height = 300) {
  rows <- lapply(seq_len(nrow(df)), function(i) {
    list(
      x = if ("datetime" %in% names(df)) as.character(df$datetime[[i]]) else as.character(i),
      value = numeric_or_null(df$value[[i]]),
      parameter = if ("parameter" %in% names(df)) as.character(df$parameter[[i]]) else "value",
      unit = if ("unit" %in% names(df)) as.character(df$unit[[i]]) else "",
      coverage_id = if ("coverage_id" %in% names(df)) as.character(df$coverage_id[[i]]) else "",
      z = if ("z" %in% names(df) && !is.na(df$z[[i]])) as.character(df$z[[i]]) else ""
    )
  })
  list(
    title = title %||% "",
    width = as.integer(width),
    height = as.integer(height),
    rows = rows
  )
}

interactive_chart_html <- function(payload, width = 560, height = 300) {
  json <- jsonlite::toJSON(
    payload,
    auto_unbox = TRUE,
    null = "null",
    na = "null",
    POSIXt = "ISO8601"
  )
  encoded <- utils::URLencode(json, reserved = TRUE, repeated = TRUE)
  sprintf(
    paste0(
      "<div class='edr-popup-chart' data-edr-chart='%s' ",
      "style='width:%dpx;max-width:100%%;height:%dpx'></div>"
    ),
    escape_html(encoded),
    as.integer(width),
    as.integer(height)
  )
}

numeric_or_null <- function(x) {
  out <- suppressWarnings(as.numeric(x))
  if (length(out) != 1L || !is.finite(out)) NA_real_ else out
}

attrs_to_table_html <- function(attrs) {
  if (length(attrs) == 0L) return("")
  rows <- vapply(
    names(attrs),
    function(k) sprintf(
      "<tr><td style='padding:2px 6px 2px 0; color:#666'>%s</td><td style='padding:2px'>%s</td></tr>",
      escape_html(k), escape_html(as.character(attrs[[k]]))
    ),
    character(1)
  )
  paste0(
    "<table style='border-collapse:collapse; margin-bottom:6px'>",
    paste(rows, collapse = ""),
    "</table>"
  )
}

escape_html <- function(x) {
  x <- as.character(x)
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;",  x, fixed = TRUE)
  x <- gsub(">", "&gt;",  x, fixed = TRUE)
  x <- gsub("\"", "&quot;", x, fixed = TRUE)
  x <- gsub("'", "&#39;", x, fixed = TRUE)
  x
}

# Friendly install check used by every viz helper.
check_installed_for <- function(pkg, action, call = rlang::caller_env()) {
  if (!rlang::is_installed(pkg)) {
    cli::cli_abort(
      c("The {.pkg {pkg}} package is required to {action}.",
        i = "Install with {.code install.packages({.val {pkg}})}."),
      call = call
    )
  }
  invisible()
}
