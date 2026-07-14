#!/usr/bin/env Rscript

# Execute edr_map's generated JavaScript in a real headless browser. This is
# intentionally outside tests/testthat so CRAN checks remain browser-free.

suppressPackageStartupMessages(library(edr4r))

# When invoked from a development checkout, always test the checkout rather
# than an older installed release. CI installs local::. first, so this is
# mainly a convenience for contributors running the script directly.
if (file.exists("DESCRIPTION") &&
    requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all(".", quiet = TRUE, export_all = FALSE)
}
if (!exists("edr_map", mode = "function")) {
  stop("The loaded edr4r does not export edr_map().", call. = FALSE)
}
if (!exists("edr_add_stations", mode = "function")) {
  stop("The loaded edr4r does not export edr_add_stations().", call. = FALSE)
}

for (package in c("chromote", "htmlwidgets", "leaflet", "sf")) {
  if (!requireNamespace(package, quietly = TRUE)) {
    stop("Browser smoke test requires package '", package, "'.", call. = FALSE)
  }
}

grid <- expand.grid(
  x = c(-110, -109),
  y = c(40, 41),
  parameter = c("temperature", "precipitation"),
  datetime = c("2024-01-01", "2024-01-02"),
  KEEP.OUT.ATTRS = FALSE
)
grid$value <- as.numeric(seq_len(nrow(grid)))
grid$value[[1L]] <- NA_real_

widget <- edr_map(
  tibble::as_tibble(grid),
  mode = "grid",
  initial = list(parameter = "temperature", datetime = "2024-01-01")
)

html <- tempfile(fileext = ".html")
on.exit(unlink(html), add = TRUE)
edr_save_html(widget, html, selfcontained = TRUE)

browser <- chromote::ChromoteSession$new()
on.exit(browser$close(), add = TRUE)
browser$set_viewport_size(width = 1100, height = 800)

invisible(browser$Page$addScriptToEvaluateOnNewDocument(
  source = paste0(
    "window.__edrBrowserErrors = [];",
    "window.addEventListener('error', function(event) {",
    "  if (event.error || event.message) {",
    "    window.__edrBrowserErrors.push(String(event.message || event.error));",
    "  }",
    "});",
    "window.addEventListener('unhandledrejection', function(event) {",
    "  window.__edrBrowserErrors.push(String(event.reason));",
    "});"
  )
))

evaluate <- function(expression) {
  result <- browser$Runtime$evaluate(
    expression = expression,
    returnByValue = TRUE,
    awaitPromise = TRUE
  )
  if (!is.null(result$exceptionDetails)) {
    stop("Browser evaluation failed: ", result$exceptionDetails$text, call. = FALSE)
  }
  result$result$value
}

wait_until <- function(expression, description, timeout = 20) {
  deadline <- Sys.time() + timeout
  repeat {
    value <- tryCatch(evaluate(expression), error = function(e) FALSE)
    if (isTRUE(value)) return(invisible(TRUE))
    if (Sys.time() >= deadline) {
      stop("Timed out waiting for ", description, ".", call. = FALSE)
    }
    Sys.sleep(0.1)
  }
}

url <- paste0("file://", normalizePath(html, winslash = "/", mustWork = TRUE))
browser$go_to(url, wait_ = TRUE)

wait_until(
  "document.readyState === 'complete' && document.querySelector('.leaflet-container') !== null",
  "the Leaflet map"
)
wait_until(
  "document.querySelectorAll('.leaflet-interactive').length > 0",
  "coverage grid layers"
)

control_count <- evaluate(
  "document.querySelectorAll('.edr-coverage-control select').length"
)
if (!identical(control_count, 2L)) {
  stop("Expected two coverage selectors; found ", control_count, ".", call. = FALSE)
}

invisible(evaluate(paste0(
  "(function() {",
  "  var select = document.querySelector('.edr-coverage-control select');",
  "  select.value = select.options[select.options.length - 1].value;",
  "  select.dispatchEvent(new Event('change', { bubbles: true }));",
  "  return true;",
  "})()"
)))
wait_until(
  "document.querySelectorAll('.leaflet-interactive').length > 0",
  "grid redraw after changing a selector"
)

invisible(evaluate(paste0(
  "(function() {",
  "  var layer = document.querySelector('.leaflet-interactive');",
  "  layer.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));",
  "  return true;",
  "})()"
)))
wait_until(
  "document.querySelector('.leaflet-popup-content') !== null",
  "a grid-cell popup"
)

popup_text <- evaluate("document.querySelector('.leaflet-popup-content').innerText")
if (!grepl("temperature|precipitation", popup_text)) {
  stop("Coverage popup did not contain a parameter label.", call. = FALSE)
}

errors <- evaluate("window.__edrBrowserErrors")
if (length(errors) > 0L) {
  stop(
    "JavaScript error(s) in edr_map: ",
    paste(unique(unlist(errors, use.names = FALSE)), collapse = "; "),
    call. = FALSE
  )
}

message("edr_map browser smoke test passed: controls, redraw, popup, no JS errors.")

# Exercise the composable path used by the Lake Mead vignette: coverage cells
# in a lower pane, two independently grouped station layers, and interactive
# station charts/CSV links above the grid.
layered_grid <- expand.grid(
  x = c(-115.20, -115.10),
  y = c(36.00, 36.10),
  KEEP.OUT.ATTRS = FALSE
)
layered_grid$parameter <- "Population density"
layered_grid$unit <- "people/km2"
layered_grid$value <- c(5, 50, 500, 5000)

stations <- sf::st_as_sf(
  data.frame(
    id = c("usbr", "usgs"),
    name = c("USBR reservoir", "USGS gauge"),
    longitude = c(-115.15, -115.14),
    latitude = c(36.05, 36.06)
  ),
  coords = c("longitude", "latitude"),
  crs = 4326
)
station_series <- function(id, parameter, unit, x, y) {
  tibble::tibble(
    coverage_id = id,
    parameter = parameter,
    unit = unit,
    datetime = as.POSIXct("2026-01-01", tz = "UTC") + 0:4 * 86400,
    value = seq_len(5),
    x = x,
    y = y
  )
}

# A single station previously left names on the X/Y scalars passed to
# leaflet::setView(), which could serialize into an unusable widget.
single_station_widget <- edr_map(
  stations[1, , drop = FALSE],
  popup = "table",
  id_col = "id",
  label_col = "name"
)
single_station_html <- tempfile(fileext = ".html")
on.exit(unlink(single_station_html), add = TRUE)
edr_save_html(single_station_widget, single_station_html, selfcontained = TRUE)
browser$go_to(
  paste0(
    "file://",
    normalizePath(single_station_html, winslash = "/", mustWork = TRUE)
  ),
  wait_ = TRUE
)
wait_until(
  paste0(
    "document.readyState === 'complete' && ",
    "document.querySelectorAll('.edr-station-marker').length === 1"
  ),
  "the single-station map"
)
errors <- evaluate("window.__edrBrowserErrors")
if (length(errors) > 0L) {
  stop(
    "JavaScript error(s) in the single-station map: ",
    paste(unique(unlist(errors, use.names = FALSE)), collapse = "; "),
    call. = FALSE
  )
}
message("Single-station browser regression passed.")

# On a coverage widget, fit = TRUE must win over the coverage render hook's
# default extent. Put the station far from the grid and verify it finishes in
# the centre of the rendered map.
far_station <- sf::st_as_sf(
  data.frame(
    id = "far-station",
    name = "Far station",
    longitude = -90,
    latitude = 30
  ),
  coords = c("longitude", "latitude"),
  crs = 4326
)
fit_widget <- edr_map(tibble::as_tibble(layered_grid), mode = "grid")
fit_widget <- edr_add_stations(
  fit_widget,
  far_station,
  popup = "table",
  id_col = "id",
  label_col = "name",
  fit = TRUE
)
fit_html <- tempfile(fileext = ".html")
on.exit(unlink(fit_html), add = TRUE)
edr_save_html(fit_widget, fit_html, selfcontained = TRUE)
browser$go_to(
  paste0("file://", normalizePath(fit_html, winslash = "/", mustWork = TRUE)),
  wait_ = TRUE
)
wait_until(
  paste0(
    "document.readyState === 'complete' && ",
    "document.querySelectorAll('.edr-station-marker').length === 1"
  ),
  "the station-fitted coverage map"
)
centre_offset <- evaluate(paste0(
  "(function() {",
  "  var marker = document.querySelector('.edr-station-marker');",
  "  var map = document.querySelector('.leaflet-container');",
  "  var markerRect = marker.getBoundingClientRect();",
  "  var mapRect = map.getBoundingClientRect();",
  "  return {",
  "    x: Math.abs((markerRect.left + markerRect.width / 2) - ",
  "      (mapRect.left + mapRect.width / 2)),",
  "    y: Math.abs((markerRect.top + markerRect.height / 2) - ",
  "      (mapRect.top + mapRect.height / 2))",
  "  };",
  "})()"
))
if (centre_offset$x > 40 || centre_offset$y > 40) {
  stop("fit = TRUE was overwritten by the coverage-map extent.", call. = FALSE)
}
message("Coverage station-fit browser regression passed.")

layered_widget <- edr_map(
  tibble::as_tibble(layered_grid),
  mode = "grid",
  grid_opacity = 0.55,
  grid_transform = "sqrt"
)
layered_widget <- edr_add_stations(
  layered_widget,
  stations[1, , drop = FALSE],
  data = list(usbr = station_series(
    "usbr", "Storage", "af", -115.15, 36.05
  )),
  popup = "plot+csv",
  id_col = "id",
  label_col = "name",
  group = "USBR",
  matched_color = "#0072B2",
  marker_radius = 8
)
layered_widget <- edr_add_stations(
  layered_widget,
  stations[2, , drop = FALSE],
  data = list(usgs = station_series(
    "usgs", "Discharge", "ft3/s", -115.14, 36.06
  )),
  popup = "plot+csv",
  id_col = "id",
  label_col = "name",
  group = "USGS",
  matched_color = "#D55E00",
  marker_radius = 6
)
layered_widget <- leaflet::addLayersControl(
  layered_widget,
  overlayGroups = c("USBR", "USGS")
)

layered_html <- tempfile(fileext = ".html")
on.exit(unlink(layered_html), add = TRUE)
edr_save_html(layered_widget, layered_html, selfcontained = TRUE)
layered_url <- paste0(
  "file://", normalizePath(layered_html, winslash = "/", mustWork = TRUE)
)
browser$go_to(layered_url, wait_ = TRUE)

wait_until(
  paste0(
    "document.readyState === 'complete' && ",
    "document.querySelectorAll('.edr-coverage-cell').length === 4 && ",
    "document.querySelectorAll('.edr-station-marker').length === 2"
  ),
  "the layered coverage and station map"
)

pane_state <- evaluate(paste0(
  "(function() {",
  "  var coverage = document.querySelector('.edr-coverage-pane');",
  "  var overlay = document.querySelector('.leaflet-overlay-pane');",
  "  return {",
  "    coverage: coverage ? Number(getComputedStyle(coverage).zIndex) : null,",
  "    overlay: overlay ? Number(getComputedStyle(overlay).zIndex) : null",
  "  };",
  "})()"
))
if (is.null(pane_state$coverage) || is.null(pane_state$overlay) ||
    pane_state$coverage >= pane_state$overlay) {
  stop("Coverage pane was not below the station overlay pane.", call. = FALSE)
}

layer_groups <- evaluate(paste0(
  "Array.from(document.querySelectorAll(",
  "'.leaflet-control-layers-overlays label')).map(function(label) {",
  "  return label.textContent.trim();",
  "})"
))
if (!all(c("USBR", "USGS") %in% layer_groups)) {
  stop("Layer control did not contain both station groups.", call. = FALSE)
}

open_station_popup <- function(index, expected_label) {
  invisible(evaluate(paste0(
    "(function() {",
    "  var close = document.querySelector('.leaflet-popup-close-button');",
    "  if (close) close.click();",
    "  return true;",
    "})()"
  )))
  wait_until(
    "document.querySelector('.leaflet-popup-content') === null",
    "the previous station popup to close"
  )
  invisible(evaluate(paste0(
    "(function() {",
    "  var markers = document.querySelectorAll('.edr-station-marker');",
    "  if (!markers[", index, "]) return false;",
    "  markers[", index, "].dispatchEvent(new MouseEvent('click', ",
    "    { bubbles: true, cancelable: true }));",
    "  return true;",
    "})()"
  )))
  expected_json <- jsonlite::toJSON(expected_label, auto_unbox = TRUE)
  wait_until(
    paste0(
      "(function() {",
      "  var popup = document.querySelector('.leaflet-popup-content');",
      "  return popup !== null && ",
      "    popup.innerText.indexOf(", expected_json, ") >= 0 && ",
      "    popup.querySelector('.edr-popup-chart-svg') !== null;",
      "})()"
    ),
    paste0(expected_label, " popup chart")
  )
  popup_text <- evaluate(
    "document.querySelector('.leaflet-popup-content').innerText"
  )
  if (!grepl(expected_label, popup_text, fixed = TRUE) ||
      !grepl("Download CSV", popup_text, fixed = TRUE)) {
    stop(expected_label, " popup did not contain its chart and CSV link.",
         call. = FALSE)
  }
}

open_station_popup(0L, "USBR reservoir")
open_station_popup(1L, "USGS gauge")

errors <- evaluate("window.__edrBrowserErrors")
if (length(errors) > 0L) {
  stop(
    "JavaScript error(s) in layered edr_map: ",
    paste(unique(unlist(errors, use.names = FALSE)), collapse = "; "),
    call. = FALSE
  )
}

message(
  "Layered map browser smoke passed: coverage pane, station groups, ",
  "chart/CSV popups, no JS errors."
)

# Finally load the committed vignette artifact itself. This catches stale or
# corrupt generated HTML even when the synthetic composability test succeeds.
sidecar <- file.path(
  "vignettes", "cross-endpoint-water-context-full", "lake-mead-map.html"
)
if (!file.exists(sidecar)) {
  stop("Committed Lake Mead widget is missing: ", sidecar, call. = FALSE)
}
invisible(browser$go_to(
  paste0("file://", normalizePath(sidecar, winslash = "/", mustWork = TRUE)),
  wait_ = FALSE
))
wait_until(
  paste0(
    "document.readyState === 'complete' && ",
    "document.querySelectorAll('.edr-coverage-cell').length === 5940 && ",
    "document.querySelectorAll('.edr-station-marker').length === 3 && ",
    "document.querySelectorAll('.edr-coverage-control select').length === 1"
  ),
  "the committed Lake Mead widget",
  timeout = 30
)
sidecar_parameters <- evaluate(paste0(
  "Array.from(document.querySelector(",
  "'.edr-coverage-control select').options).map(function(option) {",
  "  return option.value;",
  "})"
))
expected_parameters <- c(
  "2015 population density",
  "Elevation above mean sea level"
)
if (!all(expected_parameters %in% sidecar_parameters)) {
  stop("Committed Lake Mead widget is missing a grid facet.", call. = FALSE)
}
sidecar_initial <- evaluate(
  "document.querySelector('.edr-coverage-control select').value"
)
if (!identical(sidecar_initial, "2015 population density")) {
  stop("Committed Lake Mead widget did not open on population.", call. = FALSE)
}

invisible(evaluate(paste0(
  "(function() {",
  "  var select = document.querySelector('.edr-coverage-control select');",
  "  select.value = 'Elevation above mean sea level';",
  "  select.dispatchEvent(new Event('change', { bubbles: true }));",
  "  return true;",
  "})()"
)))
wait_until(
  paste0(
    "document.querySelector('.edr-coverage-control select').value === ",
    "'Elevation above mean sea level' && ",
    "document.querySelectorAll('.edr-coverage-cell').length === 5940"
  ),
  "the Lake Mead elevation facet"
)
invisible(evaluate(paste0(
  "(function() {",
  "  var cell = document.querySelector('.edr-coverage-cell');",
  "  if (!cell) return false;",
  "  cell.dispatchEvent(new MouseEvent('click', ",
  "    { bubbles: true, cancelable: true }));",
  "  return true;",
  "})()"
)))
wait_until(
  paste0(
    "(function() {",
    "  var popup = document.querySelector('.leaflet-popup-content');",
    "  return popup !== null && ",
    "    popup.innerText.indexOf('Elevation above mean sea level') >= 0;",
    "})()"
  ),
  "an elevation-cell popup"
)
sidecar_groups <- evaluate(paste0(
  "Array.from(document.querySelectorAll(",
  "'.leaflet-control-layers-overlays label')).map(function(label) {",
  "  return label.textContent.trim();",
  "})"
))
if (!all(c("USBR / WWDH", "USGS") %in% sidecar_groups)) {
  stop("Committed Lake Mead widget is missing a station group.", call. = FALSE)
}

for (index in 0:2) {
  invisible(evaluate(paste0(
    "(function() {",
    "  var close = document.querySelector('.leaflet-popup-close-button');",
    "  if (close) close.click();",
    "  var marker = document.querySelectorAll('.edr-station-marker')[", index, "];",
    "  if (!marker) return false;",
    "  marker.dispatchEvent(new MouseEvent('click', ",
    "    { bubbles: true, cancelable: true }));",
    "  return true;",
    "})()"
  )))
  wait_until(
    paste0(
      "(function() {",
      "  var popup = document.querySelector('.leaflet-popup-content');",
      "  return popup !== null && ",
      "    popup.querySelector('.edr-popup-chart-svg') !== null && ",
      "    popup.innerText.indexOf('Download CSV') >= 0;",
      "})()"
    ),
    paste0("Lake Mead station popup ", index + 1L)
  )
}

errors <- evaluate("window.__edrBrowserErrors")
if (length(errors) > 0L) {
  stop(
    "JavaScript error(s) in the committed Lake Mead widget: ",
    paste(unique(unlist(errors, use.names = FALSE)), collapse = "; "),
    call. = FALSE
  )
}
message(
  "Committed Lake Mead widget browser smoke passed: facet switch, ",
  "station groups, chart/CSV popups, no JS errors."
)
