test_that("edr_map returns a leaflet htmlwidget", {
  skip_if_not_installed("leaflet")
  skip_if_not_installed("sf")
  gj <- read_fixture("locations.geojson")
  locs <- geojson_to_sf(gj)
  m <- edr_map(locs, popup = "table")
  expect_s3_class(m, "leaflet")
  expect_s3_class(m, "htmlwidget")
})

test_that("popup HTML embeds interactive charts and CSV URIs", {
  skip_if_not_installed("leaflet")
  skip_if_not_installed("sf")
  skip_if_not_installed("base64enc")

  locs <- geojson_to_sf(read_fixture("locations.geojson"))
  # Hand-build a per-feature data list keyed by feature id.
  tb <- covjson_to_tibble(read_fixture("pointseries.covjson"))
  data_list <- list(
    "08313000" = tb,
    "08317400" = tb
  )
  m <- edr_map(locs, data = data_list, popup = "plot+csv")
  # Pull the popup HTML out of the underlying leaflet call. It's stored
  # in the m$x$calls structure.
  popup_blob <- extract_popup_html(m)
  expect_match(popup_blob, "edr-popup-chart")
  expect_match(popup_blob, "data-edr-chart")
  expect_match(popup_blob, "data:text/csv;base64,")
  expect_match(m$jsHooks$render[[1]]$code, "edrRenderPopupCharts")
})

test_that("popup = 'table' works without data", {
  skip_if_not_installed("leaflet")
  skip_if_not_installed("sf")
  locs <- geojson_to_sf(read_fixture("locations.geojson"))
  m <- edr_map(locs, popup = "table")
  expect_s3_class(m, "leaflet")
})

test_that("single-station map extents use unnamed numeric coordinates", {
  skip_if_not_installed("leaflet")
  skip_if_not_installed("sf")
  locs <- geojson_to_sf(read_fixture("locations.geojson"))

  m <- edr_map(locs[1, , drop = FALSE], popup = "table")
  marker_call <- Filter(
    function(call) identical(call$method, "addCircleMarkers"),
    m$x$calls
  )[[1]]

  expect_type(marker_call$args[[1]], "double")
  expect_type(marker_call$args[[2]], "double")
  expect_null(names(marker_call$args[[1]]))
  expect_null(names(marker_call$args[[2]]))
  expect_null(names(m$x$setView[[1]]))
})

test_that("plot/csv popup modes need data", {
  skip_if_not_installed("leaflet")
  skip_if_not_installed("sf")
  locs <- geojson_to_sf(read_fixture("locations.geojson"))
  expect_error(edr_map(locs, popup = "plot+csv"), "required for popup mode")
})

test_that("spatial data matching can enforce a maximum distance", {
  skip_if_not_installed("sf")
  locs <- geojson_to_sf(read_fixture("locations.geojson"))
  ids <- as.character(sf::st_drop_geometry(locs)$id)
  df <- tibble::tibble(
    coverage_id = "server-assigned",
    parameter = "discharge",
    datetime = "2020-01-01",
    value = 1,
    x = -150,
    y = 0
  )

  unlimited <- edr4r:::spatial_split(df, locs, ids)
  expect_true(any(!vapply(unlimited, is.null, logical(1))))

  capped <- edr4r:::spatial_split(df, locs, ids, max_match_distance = 0.01)
  expect_true(all(vapply(capped, is.null, logical(1))))
  expect_error(edr4r:::check_max_match_distance(-1), "non-negative")
  expect_error(edr4r:::check_max_match_distance(Inf), "non-negative")
})

test_that("spatial matching appends every coordinate group assigned to a station", {
  skip_if_not_installed("sf")
  locs <- geojson_to_sf(read_fixture("locations.geojson"))
  ids <- as.character(sf::st_drop_geometry(locs)$id)
  df <- tibble::tibble(
    coverage_id = "server-assigned",
    parameter = "discharge",
    datetime = c("2020-01-01", "2020-01-02", "2020-01-03"),
    value = c(1, 2, 3),
    x = c(-109.82, -109.82, -109.81),
    y = c(37.02, 37.02, 37.02)
  )

  matched <- edr4r:::spatial_split(df, locs, ids)

  expect_equal(nrow(matched[[1]]), 3L)
  expect_equal(matched[[1]]$value, c(1, 2, 3))
  expect_null(matched[[2]])
})

test_that("station parameter filtering determines matched marker status", {
  skip_if_not_installed("leaflet")
  skip_if_not_installed("sf")
  locs <- geojson_to_sf(read_fixture("locations.geojson"))
  station_data <- tibble::tibble(
    coverage_id = c("08313000", "08317400"),
    parameter = c("temp", "oxygen"),
    datetime = "2020-01-01",
    value = c(10, 20)
  )

  m <- edr_map(
    locs,
    data = station_data,
    popup = "plot",
    parameter = "temp"
  )
  marker_calls <- Filter(
    function(call) identical(call$method, "addCircleMarkers"),
    m$x$calls
  )
  groups <- vapply(marker_calls, function(call) call$args[[5]], character(1))

  expect_setequal(groups, c("Has data", "No data in window"))
  expect_length(marker_calls[[match("Has data", groups)]]$args[[1]], 1L)
  expect_length(marker_calls[[match("No data in window", groups)]]$args[[1]], 1L)
})

test_that("edr_map renders gridded coverage data with slice controls", {
  skip_if_not_installed("leaflet")
  skip_if_not_installed("htmlwidgets")

  grid <- expand.grid(
    x = c(-110, -109),
    y = c(40, 41),
    parameter = c("temp", "precip"),
    datetime = c("2020-01-01", "2020-01-02"),
    z = c(0, 10),
    KEEP.OUT.ATTRS = FALSE
  )
  grid$value <- seq_len(nrow(grid))

  expect_silent(
    m <- edr_map(
      tibble::as_tibble(grid),
      initial = list(parameter = "precip", datetime = "2020-01-02", z = 10)
    )
  )
  expect_s3_class(m, "leaflet")
  payload <- extract_render_payload(m)
  expect_equal(payload$mode, "grid")
  expect_identical(payload$transform, "identity")
  expect_setequal(vapply(payload$controls, `[[`, character(1), "key"),
                  c("parameter", "datetime", "z"))
  expect_equal(payload$initial$parameter, "precip")
  expect_equal(payload$initial$datetime, "2020-01-02")
  expect_equal(payload$initial$z, "10")
  expect_true(all(c("xmin", "xmax", "ymin", "ymax", "unit") %in% names(payload$rows[[1]])))
  expect_match(m$jsHooks$render[[1]]$code, "gridTimeSeriesRows")
  expect_match(m$jsHooks$render[[1]]$code, "edrPopupChartHtml")
  expect_match(m$jsHooks$render[[1]]$code, "transformValue")
})

test_that("coverage maps slice custom axes without overlaying members", {
  skip_if_not_installed("leaflet")
  skip_if_not_installed("htmlwidgets")

  data <- covjson_to_tibble(read_fixture("custom-axis.covjson"))
  m <- edr_map(
    data,
    initial = list(realisations = "perturbed")
  )
  payload <- extract_render_payload(m)

  expect_identical(payload$mode, "grid")
  expect_identical(payload$axis_keys, ".axis_realisations")
  expect_identical(
    payload$axis_labels[[".axis_realisations"]],
    "realisations"
  )
  control_keys <- vapply(payload$controls, `[[`, character(1), "key")
  expect_true(".axis_realisations" %in% control_keys)
  expect_identical(
    payload$initial[[".axis_realisations"]],
    "perturbed"
  )
  expect_true(all(vapply(
    payload$rows,
    function(row) ".axis_realisations" %in% names(row),
    logical(1)
  )))
  expect_match(m$jsHooks$render[[1]]$code, "payload.axis_keys")
  expect_match(
    m$jsHooks$render[[1]]$code,
    "candidate[axisKey]",
    fixed = TRUE
  )
})

test_that("coverage maps reject projected or implausible coordinates", {
  skip_if_not_installed("leaflet")
  skip_if_not_installed("htmlwidgets")

  projected <- covjson_to_tibble(read_fixture("projected-grid.covjson"))
  expect_error(
    edr_map(projected),
    "projected CRS.*Leaflet",
    class = "edr_map_crs_error"
  )

  missing_reference <- read_fixture("custom-axis.covjson")
  missing_reference$domain$referencing <- NULL
  expect_warning(
    edr_map(covjson_to_tibble(missing_reference)),
    "does not provide one unambiguous horizontal CRS",
    class = "edr_map_crs_warning"
  )

  missing_reference$domain$axes$x$values <- list(1000, 2000)
  expect_error(
    edr_map(covjson_to_tibble(missing_reference)),
    "outside longitude/latitude bounds",
    class = "edr_map_crs_error"
  )

  edge <- expand.grid(x = c(179, 180), y = c(40, 41))
  edge$value <- seq_len(nrow(edge))
  expect_error(
    edr_map(tibble::as_tibble(edge), mode = "grid"),
    "outside longitude/latitude bounds",
    class = "edr_map_crs_error"
  )

  unsupported <- read_fixture("custom-axis.covjson")
  unsupported$domain$referencing[[1L]]$system$id <- "EPSG:4807"
  expect_error(
    edr_map(covjson_to_tibble(unsupported)),
    "not recognized as WGS 84/CRS84",
    class = "edr_map_crs_error"
  )
})

test_that("coverage CRS checks honor batch provenance after subsetting", {
  geographic_cov <- read_fixture("custom-axis.covjson")
  geographic_cov$id <- "shared"
  projected_cov <- read_fixture("projected-grid.covjson")
  projected_cov$id <- "shared"

  geographic <- covjson_to_tibble(geographic_cov)
  geographic <- tibble::add_column(
    geographic, .request_id = 1L, .location_id = "geographic", .before = 1L
  )
  geographic <- edr4r:::add_covjson_metadata_provenance(
    geographic, .request_id = 1L, .location_id = "geographic"
  )
  projected <- covjson_to_tibble(projected_cov)
  projected <- tibble::add_column(
    projected, .request_id = 2L, .location_id = "projected", .before = 1L
  )
  projected <- edr4r:::add_covjson_metadata_provenance(
    projected, .request_id = 2L, .location_id = "projected"
  )
  combined <- edr4r:::bind_covjson_tibbles(list(geographic, projected))

  expect_error(
    edr4r:::check_covjson_crs_consistency(combined, map = TRUE),
    "projected CRS",
    class = "edr_map_crs_error"
  )
  geographic_only <- combined[combined$.location_id == "geographic", ]
  expect_no_error(
    edr4r:::check_covjson_crs_consistency(geographic_only, map = TRUE)
  )
})

test_that("station maps transform projected sf geometry for Leaflet", {
  skip_if_not_installed("leaflet")
  skip_if_not_installed("sf")

  original <- geojson_to_sf(read_fixture("locations.geojson"))
  projected <- sf::st_transform(original, 3857)
  m <- edr_map(projected, popup = "table")
  marker_calls <- Filter(
    function(call) identical(call$method, "addCircleMarkers"),
    m$x$calls
  )
  expect_length(marker_calls, 1L)

  expected <- sf::st_coordinates(original)
  expect_equal(marker_calls[[1L]]$args[[2L]], expected[, 1L], tolerance = 1e-6)
  expect_equal(marker_calls[[1L]]$args[[1L]], expected[, 2L], tolerance = 1e-6)

  missing <- sf::st_set_crs(projected, NA)
  expect_error(
    edr_map(missing, popup = "table"),
    "outside Leaflet longitude/latitude bounds",
    class = "edr_map_crs_error"
  )

  plausible_missing <- sf::st_set_crs(original, NA)
  expect_warning(
    edr_map(plausible_missing, popup = "table"),
    "has no CRS.*treated as WGS 84",
    class = "edr_map_crs_warning"
  )
})

test_that("grid colour transforms retain original values and validate domains", {
  skip_if_not_installed("leaflet")
  skip_if_not_installed("htmlwidgets")

  grid <- expand.grid(x = c(-110, -109), y = c(40, 41))
  grid$value <- c(0, 1, 100, 10000)

  m <- edr_map(
    tibble::as_tibble(grid),
    mode = "grid",
    grid_transform = "sqrt"
  )
  payload <- extract_render_payload(m)
  expect_identical(payload$transform, "sqrt")
  expect_equal(vapply(payload$rows, `[[`, numeric(1), "value"), grid$value)

  grid$value[[1]] <- -1
  expect_error(
    edr_map(tibble::as_tibble(grid), mode = "grid", grid_transform = "sqrt"),
    "non-negative"
  )
  expect_error(
    edr_map(tibble::as_tibble(grid), mode = "grid", grid_transform = "log1p"),
    "greater than -1"
  )
})

test_that("edr_add_stations composes station popups over a coverage map", {
  skip_if_not_installed("leaflet")
  skip_if_not_installed("htmlwidgets")
  skip_if_not_installed("sf")
  skip_if_not_installed("base64enc")

  grid <- expand.grid(
    x = c(-110, -109),
    y = c(36, 37),
    KEEP.OUT.ATTRS = FALSE
  )
  grid$parameter <- "population density"
  grid$unit <- "people/km2"
  grid$value <- seq_len(nrow(grid))

  locs <- geojson_to_sf(read_fixture("locations.geojson"))
  series <- covjson_to_tibble(read_fixture("pointseries.covjson"))
  data_list <- list(
    "08313000" = series,
    "08317400" = series
  )

  base <- edr_map(tibble::as_tibble(grid), mode = "grid")
  m <- edr_add_stations(
    base,
    locs,
    data = data_list,
    popup = "plot+csv",
    group = "USGS gauges"
  )

  expect_s3_class(m, "leaflet")
  expect_equal(extract_render_payload(m)$mode, "grid")
  expect_length(m$jsHooks$render, 1L)
  expect_match(m$jsHooks$render[[1]]$code, "edrRenderPopupCharts")
  expect_match(m$jsHooks$render[[1]]$code, "edr-coverage-pane")
  expect_match(m$jsHooks$render[[1]]$code, "pane: paneName", fixed = TRUE)

  marker_calls <- Filter(
    function(call) identical(call$method, "addCircleMarkers"),
    m$x$calls
  )
  expect_length(marker_calls, 1L)
  expect_identical(marker_calls[[1]]$args[[5]], "USGS gauges")
  expect_identical(marker_calls[[1]]$args[[6]]$className, "edr-station-marker")
  expect_match(extract_popup_html(m), "edr-popup-chart")
  expect_match(extract_popup_html(m), "data:text/csv;base64,")

  expect_null(m$x$fitBounds)
  expect_null(m$x$setView)
})

test_that("edr_add_stations supports multiple groups without duplicate chart hooks", {
  skip_if_not_installed("leaflet")
  skip_if_not_installed("htmlwidgets")
  skip_if_not_installed("sf")

  grid <- expand.grid(x = c(-110, -109), y = c(36, 37))
  grid$value <- seq_len(nrow(grid))
  locs <- geojson_to_sf(read_fixture("locations.geojson"))
  series <- covjson_to_tibble(read_fixture("pointseries.covjson"))

  m <- edr_map(tibble::as_tibble(grid), mode = "grid")
  m <- edr_add_stations(
    m,
    locs[1, , drop = FALSE],
    data = setNames(list(series), locs$id[[1]]),
    popup = "plot",
    group = "USBR stations",
    marker_radius = 8
  )
  m <- edr_add_stations(
    m,
    locs[2, , drop = FALSE],
    data = setNames(list(series), locs$id[[2]]),
    popup = "plot",
    group = "USGS stations",
    fit = TRUE
  )

  marker_calls <- Filter(
    function(call) identical(call$method, "addCircleMarkers"),
    m$x$calls
  )
  groups <- vapply(marker_calls, function(call) call$args[[5]], character(1))
  expect_setequal(groups, c("USBR stations", "USGS stations"))
  expect_length(m$jsHooks$render, 1L)
  station_fit <- extract_render_payload(m)$station_fit
  expect_identical(station_fit$type, "view")
  expect_identical(station_fit$zoom, 9)
  expect_equal(station_fit$lng, as.numeric(sf::st_coordinates(locs[2, ])[1, 1]))
  expect_equal(station_fit$lat, as.numeric(sf::st_coordinates(locs[2, ])[1, 2]))
  expect_null(m$x$fitBounds)
  expect_null(m$x$setView)
})

test_that("edr_add_stations validates additive map arguments", {
  skip_if_not_installed("leaflet")
  skip_if_not_installed("sf")
  locs <- geojson_to_sf(read_fixture("locations.geojson"))
  m <- leaflet::leaflet()

  expect_error(edr_add_stations(list(), locs, popup = "table"),
               "Leaflet htmlwidget")
  expect_error(edr_add_stations(m, locs, popup = "table", group = ""),
               "non-empty character")
  expect_error(edr_add_stations(m, locs, popup = "table", fit = NA),
               "TRUE.*FALSE")
})

test_that("coverage maps apply parameter filters to their payload", {
  skip_if_not_installed("leaflet")
  skip_if_not_installed("htmlwidgets")

  grid <- expand.grid(
    x = c(-110, -109),
    y = c(40, 41),
    parameter = c("temp", "precip"),
    KEEP.OUT.ATTRS = FALSE
  )
  grid$value <- seq_len(nrow(grid))

  m <- edr_map(tibble::as_tibble(grid), parameter = "precip")
  payload <- extract_render_payload(m)

  expect_length(payload$rows, 4L)
  expect_true(all(vapply(
    payload$rows,
    function(row) identical(row$parameter, "precip"),
    logical(1)
  )))
  expect_error(
    edr_map(tibble::as_tibble(grid), parameter = "missing"),
    "No coverage rows match"
  )
})

test_that("map JavaScript treats nullish and blank values as missing", {
  extract_simple_function <- function(js, signature) {
    start <- regexpr(signature, js, fixed = TRUE)[[1]]
    expect_gt(start, 0L)
    remainder <- substring(js, start)
    end <- regexpr("\n  }", remainder, fixed = TRUE)[[1]]
    expect_gt(end, 0L)
    substring(remainder, 1L, end + 3L)
  }

  popup_fn <- extract_simple_function(
    edr4r:::popup_chart_renderer_js(),
    "function edrFiniteNumber(v)"
  )
  coverage_fn <- extract_simple_function(
    edr4r:::coverage_map_js(),
    "function finiteNumber(v)"
  )
  for (fn in list(popup_fn, coverage_fn)) {
    guard <- regexpr("v === null || v === undefined", fn, fixed = TRUE)[[1]]
    blank <- regexpr(
      "typeof v === 'string' && v.trim() === ''",
      fn,
      fixed = TRUE
    )[[1]]
    coercion <- regexpr("var n = Number(v)", fn, fixed = TRUE)[[1]]
    expect_gt(guard, 0L)
    expect_gt(blank, 0L)
    expect_gt(coercion, guard)
    expect_gt(coercion, blank)
  }

  payload <- edr4r:::interactive_chart_payload(tibble::tibble(
    value = c(NA_character_, "  ", "4"),
    datetime = c("2020-01-01", "2020-01-02", "2020-01-03")
  ))
  expect_true(is.na(payload$rows[[1]]$value))
  expect_true(is.na(payload$rows[[2]]$value))
  expect_equal(payload$rows[[3]]$value, 4)
  expect_match(edr4r:::coverage_map_js(), "profileSvg")
})

test_that("edr_map renders profile coverage data with controls but keeps z as profile axis", {
  skip_if_not_installed("leaflet")
  skip_if_not_installed("htmlwidgets")

  profile <- expand.grid(
    x = -110,
    y = 40,
    z = c(0, 10, 20),
    parameter = c("temp", "oxygen"),
    datetime = c("2020-01-01", "2020-01-02"),
    KEEP.OUT.ATTRS = FALSE
  )
  profile$value <- seq_len(nrow(profile))

  m <- edr_map(tibble::as_tibble(profile), mode = "profile")
  expect_s3_class(m, "leaflet")
  payload <- extract_render_payload(m)
  expect_equal(payload$mode, "profile")
  expect_setequal(vapply(payload$controls, `[[`, character(1), "key"),
                  c("parameter", "datetime"))
  expect_false("z" %in% vapply(payload$controls, `[[`, character(1), "key"))
  expect_equal(payload$rows[[1]]$z, "0")
  expect_false(grepl("edr-coverage-profile", m$jsHooks$render[[1]]$code,
                     fixed = TRUE))
})

test_that("edr_save_html writes a non-trivial HTML file", {
  skip_if_not_installed("leaflet")
  skip_if_not_installed("sf")
  skip_if_not_installed("htmlwidgets")
  locs <- geojson_to_sf(read_fixture("locations.geojson"))
  m <- edr_map(locs, popup = "table")
  path <- tempfile(fileext = ".html")
  edr_save_html(m, path)
  expect_true(file.exists(path))
  expect_gt(file.info(path)$size, 10000L)
})
