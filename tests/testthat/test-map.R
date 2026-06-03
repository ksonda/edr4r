test_that("edr_map returns a leaflet htmlwidget", {
  skip_if_not_installed("leaflet")
  skip_if_not_installed("sf")
  gj <- read_fixture("locations.geojson")
  locs <- geojson_to_sf(gj)
  m <- edr_map(locs, popup = "table")
  expect_s3_class(m, "leaflet")
  expect_s3_class(m, "htmlwidget")
})

test_that("popup HTML embeds plot SVG and CSV URIs", {
  skip_if_not_installed("leaflet")
  skip_if_not_installed("sf")
  skip_if_not_installed("ggplot2")
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
  expect_match(popup_blob, "data:image/svg\\+xml;base64,")
  expect_match(popup_blob, "data:text/csv;base64,")
})

test_that("popup = 'table' works without data", {
  skip_if_not_installed("leaflet")
  skip_if_not_installed("sf")
  locs <- geojson_to_sf(read_fixture("locations.geojson"))
  m <- edr_map(locs, popup = "table")
  expect_s3_class(m, "leaflet")
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
