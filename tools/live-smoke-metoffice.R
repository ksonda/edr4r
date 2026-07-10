#!/usr/bin/env Rscript

# Live interoperability probe for the Met Office Labs EDR demonstrator.
#
# This script is intentionally outside tests/testthat: the endpoint is a
# non-operational technical demonstrator and must never be contacted by CRAN
# checks or the regular package test suite. The scheduled/manual GitHub Actions
# workflow is the only automated caller.

suppressPackageStartupMessages(library(edr4r))

base_url <- "https://labs.metoffice.gov.uk/edr"
request_timeout <- 10

message("Checking collection discovery at ", base_url, " ...")
client <- edr_client(
  base_url,
  timeout = request_timeout,
  max_tries = 1
)

collections <- edr_collections(client)
if (!is.data.frame(collections) || nrow(collections) < 1L) {
  stop("Collection discovery returned no collections.", call. = FALSE)
}

terrain_row <- collections[collections$id == "terrain_tiles", , drop = FALSE]
if (nrow(terrain_row) != 1L) {
  stop("The terrain_tiles collection was not advertised exactly once.", call. = FALSE)
}
if (!"position" %in% terrain_row$data_queries[[1L]]) {
  stop("terrain_tiles no longer advertises a position query.", call. = FALSE)
}

message("Checking one terrain position (timeout ", request_timeout, "s) ...")
terrain <- edr_position(
  client,
  "terrain_tiles",
  coords = c(-0.1276, 51.5072),
  parameter_name = "Height"
)
terrain_data <- covjson_to_tibble(terrain)

if (nrow(terrain_data) < 1L) {
  stop("The terrain position query returned no rows.", call. = FALSE)
}
if (!"Height" %in% terrain_data$parameter) {
  stop("The terrain response did not contain the Height parameter.", call. = FALSE)
}
if (!any(is.finite(terrain_data$value))) {
  stop("The terrain response contained no finite height value.", call. = FALSE)
}

message(
  "Met Office Labs smoke check passed: ", nrow(collections),
  " collections; terrain height = ",
  format(terrain_data$value[which(is.finite(terrain_data$value))[1L]], digits = 6),
  " ", terrain_data$unit[which(is.finite(terrain_data$value))[1L]], "."
)
