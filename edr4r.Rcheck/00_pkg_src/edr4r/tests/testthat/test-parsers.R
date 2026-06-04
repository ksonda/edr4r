test_that("covjson_to_tibble flattens a PointSeries with nulls", {
  cov <- read_fixture("pointseries.covjson")
  tb <- covjson_to_tibble(cov)

  expect_s3_class(tb, "tbl_df")
  # 2 parameters x 3 timesteps
  expect_equal(nrow(tb), 6)
  expect_setequal(unique(tb$parameter), c("discharge", "gage_height"))

  discharge <- tb[tb$parameter == "discharge", ]
  expect_equal(discharge$value, c(100.5, NA, 102.7))
  expect_equal(unique(discharge$unit), "ft3/s")
  expect_equal(unique(discharge$parameter_label), "Discharge")
  expect_equal(unique(discharge$x), -109.83)
  expect_equal(unique(discharge$y), 37.02)
  expect_equal(unique(tb$coverage_id), "08313000")
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

test_that("covjson_to_tibble materializes regular grid axes", {
  cov <- list(
    type = "Coverage",
    parameters = list(ppt = list(unit = list(symbol = "mm/month"),
                                 observedProperty = list(label = "Precip"))),
    domain = list(
      domainType = "Grid",
      axes = list(
        x = list(start = -113, stop = -112, num = 3L),
        y = list(start = 37, stop = 36, num = 2L),
        t = list(values = list("2023-01-01"))
      )
    ),
    ranges = list(
      ppt = list(
        type = "NdArray",
        axisNames = list("t", "y", "x"),
        shape = list(1L, 2L, 3L),
        values = list(11, 12, 13, 21, 22, 23)
      )
    )
  )
  tb <- covjson_to_tibble(cov)
  expect_equal(nrow(tb), 6)
  expect_equal(sort(unique(tb$x)), c(-113, -112.5, -112))
  expect_equal(unique(tb$y), c(37, 36))

  v <- function(xx, yy) tb$value[tb$x == xx & tb$y == yy]
  expect_equal(v(-113, 37), 11)
  expect_equal(v(-112, 37), 13)
  expect_equal(v(-113, 36), 21)
  expect_equal(v(-112, 36), 23)
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

test_that("geojson_props_tibble works without dplyr/sf (no map_dfr regression)", {
  # Regression guard: purrr::map_dfr off-loads its bind to dplyr, which we
  # don't depend on. Make sure vec_rbind handles the feature-properties
  # stack across rows even when feature property keys differ.
  gj <- read_fixture("locations.geojson")
  tb <- edr4r:::geojson_props_tibble(gj)
  expect_s3_class(tb, "tbl_df")
  expect_equal(nrow(tb), 2L)
  expect_true("id" %in% names(tb))
})

test_that("mixed numeric/character parameters in one coverage demote cleanly", {
  cov <- list(
    type = "Coverage",
    parameters = list(
      discharge = list(unit = list(symbol = "ft3/s"),
                       observedProperty = list(label = "Discharge")),
      qa_flag = list(observedProperty = list(label = "QA Flag"))
    ),
    domain = list(
      domainType = "PointSeries",
      axes = list(
        x = list(values = list(-109.83)),
        y = list(values = list(37.02)),
        t = list(values = list("2020-01-01T00:00:00Z", "2020-01-02T00:00:00Z"))
      )
    ),
    ranges = list(
      discharge = list(type = "NdArray", axisNames = list("t"),
                       shape = list(2L), values = list(100.5, 102.7)),
      qa_flag = list(type = "NdArray", axisNames = list("t"),
                     shape = list(2L), values = list("ok", "missing"))
    )
  )
  expect_warning(tb <- covjson_to_tibble(cov), "discharge")
  expect_type(tb$value, "character")
  expect_equal(tb$value[tb$parameter == "discharge"], c("100.5", "102.7"))
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

test_that("mixed numeric and text values in one range preserve text", {
  cov <- list(
    type = "Coverage",
    parameters = list(
      reading = list(observedProperty = list(label = "Reading"))
    ),
    domain = list(
      domainType = "PointSeries",
      axes = list(
        x = list(values = list(0)),
        y = list(values = list(0)),
        t = list(values = list(
          "2020-01-01T00:00:00Z",
          "2020-01-02T00:00:00Z",
          "2020-01-03T00:00:00Z"
        ))
      )
    ),
    ranges = list(
      reading = list(
        type = "NdArray", axisNames = list("t"), shape = list(3L),
        values = list("1.5", "suspect", NA)
      )
    )
  )
  expect_warning(tb <- covjson_to_tibble(cov), "reading")
  expect_type(tb$value, "character")
  expect_equal(tb$value, c("1.5", "suspect", NA_character_))
})

test_that("parse_datetime picks the first format that parses any element", {
  # Single-format axis: full parse.
  iso <- c("2023-01-01T00:00:00Z", "2023-01-02T00:00:00Z")
  p <- edr4r:::parse_datetime(iso)
  expect_s3_class(p, "POSIXct")
  expect_false(any(is.na(p)))

  date_only <- c("2023-01-01", "2023-01-02")
  p2 <- edr4r:::parse_datetime(date_only)
  expect_s3_class(p2, "POSIXct")
  expect_false(any(is.na(p2)))
})

test_that("parse_datetime silently NA-fills when an axis mixes formats", {
  # ASSUMPTION lock-in: the parser picks the first matching format from
  # its list and applies it to the whole vector. Values that don't match
  # that format become NA. If a server ever mixes ISO timestamps with
  # date-only strings on the same axis, the date-only ones drop out.
  mixed <- c("2023-01-01", "2023-01-02T00:00:00Z")
  p <- edr4r:::parse_datetime(mixed)
  expect_s3_class(p, "POSIXct")
  # ISO timestamp format wins (listed first); date-only becomes NA.
  expect_true(is.na(p[[1]]))
  expect_false(is.na(p[[2]]))
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
