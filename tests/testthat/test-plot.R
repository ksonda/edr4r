test_that("edr_plot returns a ggplot for a tidy tibble", {
  skip_if_not_installed("ggplot2")
  cov <- read_fixture("pointseries.covjson")
  tb <- covjson_to_tibble(cov)
  p <- edr_plot(tb)
  expect_s3_class(p, "ggplot")
})

test_that("edr_plot accepts an edr_response directly", {
  skip_if_not_installed("ggplot2")
  cov <- read_fixture("pointseries.covjson")
  wrapped <- structure(list(covjson = cov),
                       class = c("edr_response", "edr_covjson", "list"))
  p <- edr_plot(wrapped)
  expect_s3_class(p, "ggplot")
})

test_that("edr_plot subsets via parameter =", {
  skip_if_not_installed("ggplot2")
  cov <- read_fixture("pointseries.covjson")
  tb <- covjson_to_tibble(cov)
  p <- edr_plot(tb, parameter = "discharge")
  expect_s3_class(p, "ggplot")
  # parameter is converted to a factor with "discharge (ft3/s)" label
  expect_equal(as.character(unique(p$data$parameter)), "discharge (ft3/s)")
})

test_that("edr_plot errors when parameter doesn't exist", {
  skip_if_not_installed("ggplot2")
  cov <- read_fixture("pointseries.covjson")
  tb <- covjson_to_tibble(cov)
  expect_error(edr_plot(tb, parameter = "nope"), "No rows match")
})

test_that("edr_plot auto-detects gridded coverages", {
  skip_if_not_installed("ggplot2")
  cov <- list(
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
  tb <- covjson_to_tibble(cov)
  expect_equal(edr4r:::detect_plot_view(tb, "auto"), "grid")
  p <- edr_plot(tb)
  expect_s3_class(p, "ggplot")
  expect_true(inherits(p$layers[[1]]$geom, "GeomTile"))
  grDevices::png(tempfile(fileext = ".png"))
  on.exit(grDevices::dev.off(), add = TRUE)
  expect_silent(print(p))
})

test_that("edr_plot auto-detects vertical profiles", {
  skip_if_not_installed("ggplot2")
  cov <- list(
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
  tb <- covjson_to_tibble(cov)
  expect_equal(edr4r:::detect_plot_view(tb, "auto"), "profile")
  p <- edr_plot(tb)
  expect_s3_class(p, "ggplot")
  expect_true(inherits(p$layers[[1]]$geom, "GeomPath"))
})

test_that("custom axes separate grid panels and time/profile groups", {
  skip_if_not_installed("ggplot2")

  grid <- covjson_to_tibble(read_fixture("custom-axis.covjson"))
  p_grid <- edr_plot(grid)
  expect_setequal(
    unique(as.character(p_grid$data$.edr_panel)),
    c(
      "temperature (Cel) | realisations=control",
      "temperature (Cel) | realisations=perturbed"
    )
  )

  time <- tibble::tibble(
    coverage_id = "station",
    parameter = "flow",
    datetime = rep(
      as.POSIXct(c("2024-01-01", "2024-01-02"), tz = "UTC"),
      2L
    ),
    value = c(1, 2, 10, 20),
    .axis_member = rep(c("control", "perturbed"), each = 2L)
  )
  p_time <- edr_plot(time)
  expect_equal(edr4r:::n_present_unique(p_time$data$.edr_time_group), 2L)

  profile <- tibble::tibble(
    coverage_id = "station",
    parameter = "temperature",
    z = rep(c(0, 10), 2L),
    value = c(20, 19, 21, 20),
    .axis_member = rep(c("control", "perturbed"), each = 2L)
  )
  p_profile <- edr_plot(profile, view = "profile")
  expect_equal(
    edr4r:::n_present_unique(p_profile$data$.edr_profile_group),
    2L
  )
})

test_that("projected CoverageJSON remains valid for ggplot grids", {
  skip_if_not_installed("ggplot2")

  projected <- covjson_to_tibble(read_fixture("projected-grid.covjson"))
  expect_silent(p <- edr_plot(projected))
  expect_s3_class(p, "ggplot")
})
