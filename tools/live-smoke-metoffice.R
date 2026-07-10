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

service_capabilities <- edr_capabilities(client)
if (!edr_supports(service_capabilities, conformance = "edr/core")) {
  stop("The service no longer advertises the EDR core conformance class.",
       call. = FALSE)
}

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

terrain_capabilities <- edr_capabilities(client, "terrain_tiles")
if (!edr_supports(
  terrain_capabilities,
  query = "position",
  format = "CoverageJSON"
)) {
  stop("terrain_tiles no longer advertises position as CoverageJSON.",
       call. = FALSE)
}

message("Checking forecast-instance discovery ...")
forecast_collection <- "moglobal-station-level"
runs <- edr_instances(client, forecast_collection)
valid_run_ids <- if (is.data.frame(runs) && "id" %in% names(runs)) {
  runs$id[!is.na(runs$id) & nzchar(trimws(runs$id))]
} else {
  character()
}
if (length(valid_run_ids) == 0L) {
  stop("Forecast instance discovery returned no usable instance ids.",
       call. = FALSE)
}
run_id <- valid_run_ids[[1L]]
run_capabilities <- edr_capabilities(
  client,
  forecast_collection,
  instance_id = run_id
)
if (!edr_supports(
  run_capabilities,
  query = "locations"
)) {
  stop("The forecast instance no longer advertises a locations query.",
       call. = FALSE)
}
run_locations <- edr_locations(
  client,
  forecast_collection,
  instance_id = run_id
)
run_location_count <- if (is.data.frame(run_locations)) {
  nrow(run_locations)
} else if (inherits(run_locations, "edr_geojson")) {
  features <- run_locations$geojson$features
  if (is.null(features)) 0L else length(features)
} else {
  0L
}
if (run_location_count < 1L) {
  stop("The forecast instance locations query returned no features.",
       call. = FALSE)
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

message("Checking a bounded population-density grid ...")
population_capabilities <- edr_capabilities(client, "global_pop_density")
if (!edr_supports(
  population_capabilities,
  query = "area",
  format = "CoverageJSON"
)) {
  stop("global_pop_density no longer advertises area as CoverageJSON.",
       call. = FALSE)
}

population_ring <- rbind(
  c(-115.20, 36.12),
  c(-115.10, 36.12),
  c(-115.10, 36.22),
  c(-115.20, 36.22)
)
population <- edr_area(
  client,
  "global_pop_density",
  coords = population_ring,
  parameter_name = "Pop_Density",
  crs = "EPSG:4326"
)
population_data <- covjson_to_tibble(population)

if (!identical(population$covjson$domain$domainType, "Grid")) {
  stop("The population area response is no longer a Grid coverage.",
       call. = FALSE)
}
if (nrow(population_data) < 1L ||
    !"Pop_Density" %in% population_data$parameter ||
    !any(is.finite(population_data$value))) {
  stop("The population area response contained no finite density grid.",
       call. = FALSE)
}

message(
  "Met Office Labs smoke check passed: ", nrow(collections),
  " collections; forecast instance ", run_id,
  " with ", run_location_count, " locations",
  "; terrain height = ",
  format(terrain_data$value[which(is.finite(terrain_data$value))[1L]], digits = 6),
  " ", terrain_data$unit[which(is.finite(terrain_data$value))[1L]],
  "; population grid rows = ", nrow(population_data), "."
)
