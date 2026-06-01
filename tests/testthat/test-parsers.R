test_that("covjson_to_tibble flattens a PointSeries with nulls", {
  cov <- read_fixture("pointseries.covjson")
  tb <- covjson_to_tibble(cov)

  expect_s3_class(tb, "tbl_df")
  # 2 parameters x 3 timesteps
  expect_equal(nrow(tb), 6)
  expect_setequal(unique(tb$parameter), c("storage", "elevation"))

  storage <- tb[tb$parameter == "storage", ]
  expect_equal(storage$value, c(100.5, NA, 102.7))
  expect_equal(unique(storage$unit), "acre-feet")
  expect_equal(unique(storage$parameter_label), "Reservoir Storage")
  expect_equal(unique(storage$x), -104.8)
  expect_equal(unique(storage$y), 40.42)
  expect_equal(unique(tb$coverage_id), "247")
  expect_s3_class(tb$datetime, "POSIXct")
})

test_that("covjson_to_tibble respects NdArray row-major ordering", {
  cov <- list(
    type = "Coverage",
    parameters = list(temp = list(unit = list(symbol = "degC"),
                                  observedProperty = list(label = "Air Temp"))),
    domain = list(
      domainType = "Grid",
      axes = list(
        x = list(values = list(10, 20, 30)),
        y = list(values = list(1, 2))
      )
    ),
    ranges = list(
      temp = list(type = "NdArray", axisNames = list("y", "x"),
                  shape = list(2L, 3L), values = list(11, 12, 13, 21, 22, 23))
    )
  )
  tb <- covjson_to_tibble(cov)
  expect_equal(nrow(tb), 6)
  v <- function(xx, yy) tb$value[tb$x == xx & tb$y == yy]
  expect_equal(v(10, 1), 11)
  expect_equal(v(30, 1), 13)
  expect_equal(v(10, 2), 21)
  expect_equal(v(30, 2), 23)
})

test_that("covjson_to_tibble accepts an edr_response wrapper", {
  cov <- read_fixture("pointseries.covjson")
  wrapped <- structure(list(covjson = cov),
                       class = c("edr_response", "edr_covjson", "list"))
  tb <- covjson_to_tibble(wrapped)
  expect_equal(nrow(tb), 6)
})

test_that("covjson_to_tibble can keep datetime as character", {
  cov <- read_fixture("pointseries.covjson")
  tb <- covjson_to_tibble(cov, datetime_as_posix = FALSE)
  expect_type(tb$datetime, "character")
})

test_that("geojson_to_sf returns an sf object", {
  skip_if_not_installed("sf")
  gj <- read_fixture("locations.geojson")
  sfobj <- geojson_to_sf(gj)
  expect_s3_class(sfobj, "sf")
  expect_equal(nrow(sfobj), 2)
  expect_true("name" %in% names(sfobj))
  expect_true(all(sf::st_geometry_type(sfobj) == "POINT"))
})

test_that("non-CoverageJSON input errors clearly", {
  expect_error(covjson_to_tibble(list(foo = 1)), "CoverageJSON")
})

test_that("mixed numeric/character parameters in one coverage demote cleanly", {
  cov <- list(
    type = "Coverage",
    parameters = list(
      storage = list(unit = list(symbol = "acre-feet"),
                     observedProperty = list(label = "Reservoir Storage")),
      qa_flag = list(observedProperty = list(label = "QA Flag"))
    ),
    domain = list(
      domainType = "PointSeries",
      axes = list(
        x = list(values = list(-104.8)),
        y = list(values = list(40.42)),
        t = list(values = list("2020-01-01T00:00:00Z", "2020-01-02T00:00:00Z"))
      )
    ),
    ranges = list(
      storage = list(type = "NdArray", axisNames = list("t"),
                     shape = list(2L), values = list(100.5, 102.7)),
      qa_flag = list(type = "NdArray", axisNames = list("t"),
                     shape = list(2L), values = list("ok", "missing"))
    )
  )
  expect_warning(tb <- covjson_to_tibble(cov), "storage")
  expect_type(tb$value, "character")
  expect_equal(tb$value[tb$parameter == "storage"], c("100.5", "102.7"))
  expect_equal(tb$value[tb$parameter == "qa_flag"], c("ok", "missing"))
})

test_that("a numeric coverage bound with a character coverage demotes the numeric one", {
  make_cov <- function(id, vals) {
    list(
      id = id,
      type = "Coverage",
      domain = list(
        domainType = "PointSeries",
        axes = list(
          x = list(values = list(-100)),
          y = list(values = list(40)),
          t = list(values = list("2020-01-01T00:00:00Z"))
        )
      ),
      ranges = list(
        flag = list(type = "NdArray", axisNames = list("t"),
                    shape = list(1L), values = list(vals))
      )
    )
  }
  cc <- list(
    type = "CoverageCollection",
    parameters = list(flag = list(observedProperty = list(label = "Flag"))),
    coverages = list(make_cov("A", 1), make_cov("B", "missing"))
  )
  expect_warning(tb <- covjson_to_tibble(cc), "flag")
  expect_type(tb$value, "character")
  expect_setequal(tb$value, c("1", "missing"))
})

test_that("all-numeric responses emit no warning and keep numeric values", {
  cov <- read_fixture("pointseries.covjson")
  expect_silent(tb <- covjson_to_tibble(cov))
  expect_type(tb$value, "double")
})

test_that("all-character responses do not warn (no demotion happened)", {
  cov <- list(
    type = "Coverage",
    parameters = list(qa = list(observedProperty = list(label = "QA"))),
    domain = list(
      domainType = "PointSeries",
      axes = list(
        x = list(values = list(0)),
        y = list(values = list(0)),
        t = list(values = list("2020-01-01T00:00:00Z"))
      )
    ),
    ranges = list(
      qa = list(type = "NdArray", axisNames = list("t"),
                shape = list(1L), values = list("ok"))
    )
  )
  expect_silent(tb <- covjson_to_tibble(cov))
  expect_type(tb$value, "character")
  expect_equal(tb$value, "ok")
})
