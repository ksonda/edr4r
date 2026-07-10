#!/usr/bin/env Rscript

# Execute edr_map's generated JavaScript in a real headless browser. This is
# intentionally outside tests/testthat so CRAN checks remain browser-free.

suppressPackageStartupMessages(library(edr4r))

# When invoked from a development checkout that also has an older CRAN release
# installed, test the checkout. CI installs local::. first, so this is mainly a
# convenience for contributors running the script directly.
if (!exists("edr_map", mode = "function") && file.exists("DESCRIPTION") &&
    requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all(".", quiet = TRUE, export_all = FALSE)
}
if (!exists("edr_map", mode = "function")) {
  stop("The loaded edr4r does not export edr_map().", call. = FALSE)
}

for (package in c("chromote", "htmlwidgets", "leaflet")) {
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
