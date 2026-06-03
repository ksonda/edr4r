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
