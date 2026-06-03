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

test_that("edr_explore method = 'cube' uses one bulk call, no per-station N+1", {
  skip_if_not_installed("leaflet")
  skip_if_not_installed("sf")
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("base64enc")

  gj  <- read_fixture("locations.geojson")
  # Build a synthetic /cube CovJSON whose two coverages live at the same
  # (x, y) as the two fixture features, so spatial matching finds them.
  cube <- list(
    type = "CoverageCollection",
    parameters = list(
      discharge = list(
        unit = list(symbol = "ft3/s"),
        observedProperty = list(label = list(en = "Discharge"))
      )
    ),
    coverages = list(
      list(
        type = "Coverage",
        domain = list(
          domainType = "PointSeries",
          axes = list(
            x = list(values = list(-109.83)),
            y = list(values = list(37.02)),
            t = list(values = list("2020-01-01T00:00:00Z", "2020-01-02T00:00:00Z"))
          )
        ),
        ranges = list(discharge = list(
          type = "NdArray", axisNames = list("t"),
          shape = list(2L), values = list(11, 12)
        ))
      ),
      list(
        type = "Coverage",
        domain = list(
          domainType = "PointSeries",
          axes = list(
            x = list(values = list(-106.86)),
            y = list(values = list(35.55)),
            t = list(values = list("2020-01-01T00:00:00Z", "2020-01-02T00:00:00Z"))
          )
        ),
        ranges = list(discharge = list(
          type = "NdArray", axisNames = list("t"),
          shape = list(2L), values = list(21, 22)
        ))
      )
    )
  )

  call_n <- 0L
  httr2::local_mocked_responses(function(req) {
    call_n <<- call_n + 1L
    # call 1: edr_locations -> FeatureCollection
    # call 2: edr_cube      -> CoverageCollection
    # No per-station N+1 calls expected.
    if (call_n == 1L) {
      mock_json_response(gj, content_type = "application/geo+json")
    } else if (call_n == 2L) {
      mock_json_response(cube)
    } else {
      cli::cli_abort("Unexpected extra HTTP call (#{call_n}); cube path should make exactly 2.")
    }
  })

  m <- edr_explore(test_client(), "demo",
                   bbox           = c(-110, 35, -106, 38),
                   datetime       = "2020-01-01/2020-01-02",
                   parameter_name = "discharge",
                   method         = "cube",
                   quiet          = TRUE)
  expect_s3_class(m, "leaflet")
  expect_equal(call_n, 2L)

  popup_blob <- extract_popup_html(m)
  expect_match(popup_blob, "data:image/svg\\+xml;base64,")
  expect_match(popup_blob, "data:text/csv;base64,")
})

test_that("auto explore method requires matching spatial input", {
  cols <- read_fixture("collections.json")
  httr2::local_mocked_responses(function(req) mock_json_response(cols))

  client <- test_client()
  expect_equal(
    edr4r:::resolve_explore_method(
      client, "daily-values", "auto",
      bbox = NULL,
      coords = matrix(c(0, 0, 1, 0, 1, 1), ncol = 2, byrow = TRUE)
    ),
    "area"
  )
  expect_equal(
    edr4r:::resolve_explore_method(
      client, "daily-values", "auto",
      bbox = c(-110, 35, -106, 38),
      coords = NULL
    ),
    "cube"
  )
  expect_equal(
    edr4r:::resolve_explore_method(
      client, "daily-values", "auto",
      bbox = NULL,
      coords = NULL
    ),
    "per-location"
  )
  expect_equal(
    edr4r:::resolve_explore_method(
      client, "daily-values", "cube",
      bbox = NULL,
      coords = NULL
    ),
    "cube"
  )
})

test_that("per-station fetches warn when stations fail", {
  cov <- read_fixture("pointseries.covjson")
  call_n <- 0L
  httr2::local_mocked_responses(function(req) {
    call_n <<- call_n + 1L
    if (call_n == 1L) {
      mock_json_response(cov)
    } else {
      mock_json_response(list(description = "station failed"), status = 500L)
    }
  })

  expect_warning(
    res <- edr4r:::fetch_per_station(
      test_client(), "demo", c("ok", "bad"),
      datetime = NULL, parameter_name = NULL, quiet = TRUE
    ),
    "Failed to fetch data"
  )
  expect_s3_class(res[[1]], "tbl_df")
  expect_null(res[[2]])
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
