test_that("edr_explore fetches per-station data and returns a leaflet map", {
  skip_if_not_installed("leaflet")
  skip_if_not_installed("sf")
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("base64enc")

  gj  <- read_fixture("locations.geojson")
  cov <- read_fixture("pointseries.covjson")

  # The mock returns the locations FeatureCollection on the first call
  # (the /locations request) and the same CovJSON for each /locations/{id}
  # request after that.
  call_n <- 0L
  httr2::local_mocked_responses(function(req) {
    call_n <<- call_n + 1L
    if (call_n == 1L) {
      mock_json_response(gj, content_type = "application/geo+json")
    } else {
      mock_json_response(cov)
    }
  })

  m <- edr_explore(test_client(), "demo",
                   datetime = "2020-01-01/2020-01-03",
                   parameter_name = "discharge",
                   quiet = TRUE)
  expect_s3_class(m, "leaflet")

  # The two CovJSON calls (one per station) should have produced popups
  # with both plot and CSV URIs.
  popup_blob <- extract_popup_html(m)
  expect_match(popup_blob, "data:image/svg\\+xml;base64,")
  expect_match(popup_blob, "data:text/csv;base64,")
})

test_that("edr_explore + edr_save_html round-trip to disk", {
  skip_if_not_installed("leaflet")
  skip_if_not_installed("sf")
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("base64enc")
  skip_if_not_installed("htmlwidgets")

  gj  <- read_fixture("locations.geojson")
  cov <- read_fixture("pointseries.covjson")

  call_n <- 0L
  httr2::local_mocked_responses(function(req) {
    call_n <<- call_n + 1L
    if (call_n == 1L) {
      mock_json_response(gj, content_type = "application/geo+json")
    } else {
      mock_json_response(cov)
    }
  })

  path <- tempfile(fileext = ".html")
  result <- edr_explore(test_client(), "demo",
                        datetime = "2020-01-01/2020-01-03",
                        parameter_name = "discharge",
                        file = path, quiet = TRUE)
  expect_equal(result, path)
  expect_true(file.exists(path))
  expect_gt(file.info(path)$size, 10000L)
})
