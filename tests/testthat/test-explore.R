explore_grid_cov <- function() {
  list(
    type = "Coverage",
    parameters = list(
      temp = list(unit = list(symbol = "degC"),
                  observedProperty = list(label = "Temperature"))
    ),
    domain = list(
      domainType = "Grid",
      axes = list(
        x = list(values = list(-110, -109, -108)),
        y = list(values = list(40, 41))
      )
    ),
    ranges = list(
      temp = list(
        type = "NdArray",
        axisNames = list("y", "x"),
        shape = list(2L, 3L),
        values = list(1, 2, 3, 4, 5, 6)
      )
    )
  )
}

explore_profile_cov <- function() {
  list(
    type = "Coverage",
    parameters = list(
      temp = list(unit = list(symbol = "degC"),
                  observedProperty = list(label = "Temperature"))
    ),
    domain = list(
      domainType = "VerticalProfile",
      axes = list(
        x = list(values = list(-110)),
        y = list(values = list(40)),
        z = list(values = list(0, 10, 20))
      )
    ),
    ranges = list(
      temp = list(
        type = "NdArray",
        axisNames = list("z"),
        shape = list(3L),
        values = list(12, 10, 8)
      )
    )
  )
}

test_that("edr_explore fetches per-station data and returns a leaflet map", {
  skip_if_not_installed("leaflet")
  skip_if_not_installed("sf")
  skip_if_not_installed("base64enc")

  gj  <- read_fixture("locations.geojson")
  cov <- read_fixture("pointseries.covjson")
  cols <- read_fixture("collections.json")

  # Auto planning discovers capabilities first, then retrieves locations,
  # then fetches one CovJSON response per location.
  call_n <- 0L
  httr2::local_mocked_responses(function(req) {
    call_n <<- call_n + 1L
    if (call_n == 1L) {
      mock_json_response(cols)
    } else if (call_n == 2L) {
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
  # with both interactive chart payloads and CSV URIs.
  popup_blob <- extract_popup_html(m)
  expect_match(popup_blob, "edr-popup-chart")
  expect_match(popup_blob, "data-edr-chart")
  expect_match(popup_blob, "data:text/csv;base64,")
  expect_match(m$jsHooks$render[[1]]$code, "edrRenderPopupCharts")
})

test_that("edr_explore method = 'cube' uses one bulk call, no per-station N+1", {
  skip_if_not_installed("leaflet")
  skip_if_not_installed("sf")
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
    # Data is fetched first so coverage responses can avoid probing locations.
    # This point-series cube then needs locations for a station map.
    # No per-station N+1 calls expected.
    if (call_n == 1L) {
      mock_json_response(cube)
    } else if (call_n == 2L) {
      mock_json_response(gj, content_type = "application/geo+json")
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
  expect_match(popup_blob, "edr-popup-chart")
  expect_match(popup_blob, "data-edr-chart")
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

test_that("auto planning uses instance query capabilities, not the parent collection", {
  instance <- read_fixture("instance.json")
  urls <- character()
  httr2::local_mocked_responses(function(req) {
    urls <<- c(urls, req$url)
    mock_json_response(instance)
  })
  client <- test_client()

  expect_equal(
    edr4r:::resolve_explore_method(
      client, "model", "auto",
      bbox = c(-10, -10, 10, 10), coords = NULL,
      instance_id = "2024070900"
    ),
    "cube"
  )
  expect_equal(
    edr4r:::resolve_explore_method(
      client, "model", "auto",
      bbox = NULL, coords = c(0, 0),
      instance_id = "2024070900"
    ),
    "position"
  )

  # The second plan reuses the cached instance document; neither plan probes
  # the parent /collections index, which only needs to advertise instances.
  expect_equal(length(urls), 1L)
  expect_match(
    urls[[1]],
    "/collections/model/instances/2024070900",
    fixed = TRUE
  )
  request_path <- sub("^https?://[^/]+", "", urls[[1]])
  request_path <- sub("\\?.*$", "", request_path)
  expect_equal(request_path, "/collections/model/instances/2024070900")
})

test_that("instance auto planning tolerates recoverable unnamed query metadata", {
  instance <- read_fixture("instance.json")
  instance$data_queries <- unname(list(
    list(link = list(variables = list(query_type = "cube")))
  ))
  httr2::local_mocked_responses(function(req) mock_json_response(instance))

  method <- edr4r:::resolve_explore_method(
    test_client(), "model", "auto",
    bbox = c(-10, -10, 10, 10), coords = NULL,
    instance_id = "2024070900"
  )

  expect_equal(method, "cube")
})

test_that("edr_explore auto plans and fetches beneath the selected instance", {
  instance <- read_fixture("instance.json")
  urls <- character()
  httr2::local_mocked_responses(function(req) {
    urls <<- c(urls, req$url)
    if (length(urls) == 1L) {
      mock_json_response(instance)
    } else {
      mock_json_response(explore_grid_cov())
    }
  })

  out <- edr_explore(
    test_client(), "model",
    bbox = c(-110, 40, -108, 41),
    method = "auto", output = "data",
    instance_id = "2024070900"
  )

  expect_s3_class(out, "tbl_df")
  expect_equal(length(urls), 2L)
  paths <- sub("\\?.*$", "", urls)
  expect_match(
    paths[[1]],
    "/collections/model/instances/2024070900",
    fixed = TRUE
  )
  expect_match(
    paths[[2]],
    "/collections/model/instances/2024070900/cube",
    fixed = TRUE
  )
})

test_that("per-location exploration keeps every request in instance scope", {
  skip_if_not_installed("sf")
  locations <- read_fixture("locations.geojson")
  coverage <- read_fixture("pointseries.covjson")
  urls <- character()
  httr2::local_mocked_responses(function(req) {
    urls <<- c(urls, req$url)
    if (length(urls) == 1L) {
      mock_json_response(locations, content_type = "application/geo+json")
    } else {
      mock_json_response(coverage)
    }
  })

  out <- edr_explore(
    test_client(), "model",
    method = "per-location", output = "data", quiet = TRUE,
    instance_id = "run 00"
  )

  expect_type(out, "list")
  expect_equal(length(urls), 3L)
  prefix <- "/collections/model/instances/run%2000/locations"
  expect_true(all(grepl(prefix, urls, fixed = TRUE)))
  expect_equal(
    sum(grepl(paste0(prefix, "/"), urls, fixed = TRUE)),
    2L
  )
})

test_that("edr_explore keeps instance_id keyword-only", {
  formal_names <- names(formals(edr_explore))
  expect_gt(match("instance_id", formal_names), match("...", formal_names))
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

test_that("per-station fetches preserve datetime and omit missing query values", {
  coverage <- read_fixture("pointseries.covjson")
  urls <- character()
  httr2::local_mocked_responses(function(req) {
    urls <<- c(urls, utils::URLdecode(req$url))
    mock_json_response(coverage)
  })

  edr4r:::fetch_per_station(
    test_client(), "demo", "dated",
    datetime = "2020-01-01/2020-01-03",
    parameter_name = NULL,
    quiet = TRUE
  )
  edr4r:::fetch_per_station(
    test_client(), "demo", "undated",
    datetime = NULL,
    parameter_name = NULL,
    quiet = TRUE
  )

  expect_match(
    urls[[1L]],
    "datetime=2020-01-01/2020-01-03",
    fixed = TRUE
  )
  expect_false(grepl("datetime=", urls[[2L]], fixed = TRUE))
  expect_false(grepl("datetime=NA", urls[[2L]], fixed = TRUE))
})

test_that("edr_explore can return a plot for gridded cube data", {
  skip_if_not_installed("ggplot2")
  call_n <- 0L
  httr2::local_mocked_responses(function(req) {
    call_n <<- call_n + 1L
    mock_json_response(explore_grid_cov())
  })

  p <- edr_explore(
    test_client(), "grid-demo",
    bbox = c(-110, 40, -108, 41),
    method = "cube",
    output = "plot"
  )
  expect_s3_class(p, "ggplot")
  expect_true(inherits(p$layers[[1]]$geom, "GeomTile"))
  expect_equal(call_n, 1L)
})

test_that("edr_explore can return a profile plot from position data", {
  skip_if_not_installed("ggplot2")
  httr2::local_mocked_responses(function(req) {
    mock_json_response(explore_profile_cov())
  })

  p <- edr_explore(
    test_client(), "profile-demo",
    coords = c(-110, 40),
    method = "position",
    output = "plot"
  )
  expect_s3_class(p, "ggplot")
  expect_true(inherits(p$layers[[1]]$geom, "GeomPath"))
})

test_that("edr_explore auto falls back to coverage maps when locations are unavailable", {
  skip_if_not_installed("leaflet")
  skip_if_not_installed("htmlwidgets")
  call_n <- 0L
  httr2::local_mocked_responses(function(req) {
    call_n <<- call_n + 1L
    mock_json_response(explore_grid_cov())
  })

  p <- edr_explore(
    test_client(), "grid-demo",
    bbox = c(-110, 40, -108, 41),
    method = "cube",
    output = "auto"
  )
  expect_s3_class(p, "leaflet")
  expect_equal(extract_render_payload(p)$mode, "grid")
  expect_equal(call_n, 1L)
})

test_that("edr_explore output = 'map' can return coverage maps without locations", {
  skip_if_not_installed("leaflet")
  skip_if_not_installed("htmlwidgets")
  call_n <- 0L
  httr2::local_mocked_responses(function(req) {
    call_n <<- call_n + 1L
    mock_json_response(explore_profile_cov())
  })

  m <- edr_explore(
    test_client(), "profile-demo",
    coords = c(-110, 40),
    method = "position",
    output = "map"
  )
  expect_s3_class(m, "leaflet")
  expect_equal(extract_render_payload(m)$mode, "profile")
  expect_equal(call_n, 1L)
})

test_that("edr_explore + edr_save_html round-trip to disk", {
  skip_if_not_installed("leaflet")
  skip_if_not_installed("sf")
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("base64enc")
  skip_if_not_installed("htmlwidgets")

  gj  <- read_fixture("locations.geojson")
  cov <- read_fixture("pointseries.covjson")
  cols <- read_fixture("collections.json")

  call_n <- 0L
  httr2::local_mocked_responses(function(req) {
    call_n <<- call_n + 1L
    if (call_n == 1L) {
      mock_json_response(cols)
    } else if (call_n == 2L) {
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

test_that("output = 'plot' works through the per-location route", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("sf")
  gj <- read_fixture("locations.geojson")
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

  p <- edr_explore(
    test_client(), "demo",
    method = "per-location",
    output = "plot",
    quiet = TRUE
  )
  expect_s3_class(p, "ggplot")
  expect_true(".location_id" %in% names(p$data))
  expect_equal(length(unique(p$data$.location_id)), 2L)
  expect_equal(call_n, 3L)
})

test_that("auto planning stops when capability discovery fails", {
  call_n <- 0L
  httr2::local_mocked_responses(function(req) {
    call_n <<- call_n + 1L
    mock_json_response(list(description = "metadata unavailable"), status = 503L)
  })
  expect_error(
    edr_explore(test_client(), "demo", method = "auto", output = "data"),
    "Automatic fallback was stopped"
  )
  expect_equal(call_n, 1L)
})

test_that("per-location exploration enforces max_requests before data calls", {
  skip_if_not_installed("sf")
  gj <- read_fixture("locations.geojson")
  call_n <- 0L
  httr2::local_mocked_responses(function(req) {
    call_n <<- call_n + 1L
    mock_json_response(gj, content_type = "application/geo+json")
  })
  expect_error(
    edr_explore(
      test_client(), "demo",
      method = "per-location", output = "data",
      max_requests = 1L, quiet = TRUE
    ),
    "exceeding.*max_requests"
  )
  expect_equal(call_n, 1L)
})

test_that("bulk data output skips an unnecessary locations request", {
  call_n <- 0L
  httr2::local_mocked_responses(function(req) {
    call_n <<- call_n + 1L
    mock_json_response(explore_grid_cov())
  })
  out <- edr_explore(
    test_client(), "grid-demo",
    bbox = c(-110, 40, -108, 41),
    method = "cube", output = "data"
  )
  expect_s3_class(out, "tbl_df")
  expect_equal(call_n, 1L)
})

test_that("file is rejected for non-map output before network activity", {
  call_n <- 0L
  httr2::local_mocked_responses(function(req) {
    call_n <<- call_n + 1L
    cli::cli_abort("network should not be called")
  })
  expect_error(
    edr_explore(
      test_client(), "demo", method = "cube",
      bbox = c(0, 0, 1, 1), output = "data", file = tempfile()
    ),
    "only supported.*map"
  )
  expect_equal(call_n, 0L)
})

test_that("max_requests rejects fractional and out-of-range integers", {
  expect_error(edr4r:::check_max_requests(1.5), "positive integer")
  expect_error(edr4r:::check_max_requests(1e20), "positive integer")
  expect_silent(edr4r:::check_max_requests(Inf))
})
