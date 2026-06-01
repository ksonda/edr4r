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
