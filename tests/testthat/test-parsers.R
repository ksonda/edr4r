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

test_that("covjson_to_tibble expands composite trajectory coordinates", {
  cov <- read_fixture("trajectory.covjson")
  tb <- covjson_to_tibble(cov)

  expect_equal(nrow(tb), 3L)
  expect_equal(unique(tb$coverage_id), "survey-track-7")
  expect_equal(tb$x, c(-71.100, -71.095, -71.090))
  expect_equal(tb$y, c(42.350, 42.352, 42.355))
  expect_equal(tb$z, c(1.5, 2.0, 2.5))
  expect_equal(tb$value, c(18.2, 18.4, 18.5))
  expect_s3_class(tb$datetime, "POSIXct")
  expect_equal(
    as.numeric(tb$datetime),
    as.numeric(as.POSIXct(c(
      "2024-06-01 10:00:00",
      "2024-06-01 14:05:00",
      "2024-06-01 14:10:00"
    ), tz = "UTC"))
  )
})

test_that("composite and primitive axes align in row-major order", {
  cov <- list(
    type = "Coverage",
    domain = list(
      type = "Domain",
      domainType = "MultiPointSeries",
      axes = list(
        t = list(values = list(
          "2024-01-01T00:00:00Z",
          "2024-01-01T01:00:00Z"
        )),
        composite = list(
          dataType = "tuple",
          coordinates = list("x", "y"),
          values = list(list(-105, 40), list(-104, 41))
        )
      )
    ),
    ranges = list(
      reading = list(
        type = "NdArray", dataType = "float",
        axisNames = list("t", "composite"), shape = list(2L, 2L),
        values = list(11, 12, 21, 22)
      )
    )
  )

  tb <- covjson_to_tibble(cov)
  expect_equal(tb$x, c(-105, -104, -105, -104))
  expect_equal(tb$y, c(40, 41, 40, 41))
  expect_equal(tb$value, c(11, 12, 21, 22))
  expect_equal(
    format(tb$datetime, "%H:%M", tz = "UTC"),
    c("00:00", "00:00", "01:00", "01:00")
  )
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

test_that("Met Office single-point CoverageJSON preserves advertised metadata", {
  cov <- read_fixture("metoffice-terrain.covjson")
  tb <- covjson_to_tibble(cov)

  expect_equal(nrow(tb), 1L)
  expect_equal(tb$coverage_id, "1")
  expect_equal(tb$parameter, "Height")
  expect_equal(tb$parameter_label, "Height")
  expect_equal(tb$unit, "m")
  expect_equal(tb$x, -0.1276)
  expect_equal(tb$y, 51.5072)
  expect_equal(tb$value, 18.9776)
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

test_that("declared string ranges preserve numeric-looking identifiers", {
  cov <- list(
    type = "Coverage",
    domain = list(
      domainType = "PointSeries",
      axes = list(
        x = list(values = list(0)),
        y = list(values = list(0)),
        t = list(values = list(
          "2024-01-01T00:00:00Z",
          "2024-01-02T00:00:00Z",
          "2024-01-03T00:00:00Z"
        ))
      )
    ),
    ranges = list(
      station_code = list(
        type = "NdArray", dataType = "string",
        axisNames = list("t"), shape = list(3L),
        values = list("00123", "1e3", NULL)
      )
    )
  )

  expect_silent(tb <- covjson_to_tibble(cov))
  expect_type(tb$value, "character")
  expect_equal(tb$value, c("00123", "1e3", NA_character_))
})

test_that("declared numeric ranges accept safely representable numeric strings", {
  make_coverage <- function(data_type, values) {
    list(
      type = "Coverage",
      domain = list(
        domainType = "PointSeries",
        axes = list(
          x = list(values = list(0)),
          y = list(values = list(0)),
          t = list(values = as.list(sprintf(
            "2024-01-%02dT00:00:00Z", seq_along(values)
          )))
        )
      ),
      ranges = list(
        reading = list(
          type = "NdArray",
          dataType = data_type,
          axisNames = list("t"),
          shape = list(length(values)),
          values = values
        )
      )
    )
  }

  expect_silent(
    numeric <- covjson_to_tibble(
      make_coverage("float", list("1.5", "2e1", NULL))
    )
  )
  expect_type(numeric$value, "double")
  expect_equal(numeric$value, c(1.5, 20, NA_real_))

  expect_silent(
    integer <- covjson_to_tibble(
      make_coverage("integer", list("1", "2.0"))
    )
  )
  expect_equal(integer$value, c(1, 2))
  expect_error(
    covjson_to_tibble(make_coverage("float", list("1.5", "flagged"))),
    "declares.*float.*strings.*not valid numbers"
  )
  expect_error(
    covjson_to_tibble(make_coverage("float", list("1e999"))),
    "declares.*float.*strings.*not valid numbers"
  )
  expect_error(
    covjson_to_tibble(make_coverage("float", list("1e-400"))),
    "cannot be represented safely"
  )
  expect_error(
    covjson_to_tibble(
      make_coverage("integer", list("9007199254740993"))
    ),
    "cannot be represented safely"
  )
})

test_that("coverage-level parameter metadata augments and overrides collection metadata", {
  scalar_range <- function(value) {
    list(type = "NdArray", dataType = "float", values = list(value))
  }
  cov <- list(
    type = "CoverageCollection",
    parameters = list(
      inherited = list(
        observedProperty = list(label = list(en = "Inherited label")),
        unit = list(symbol = "m")
      ),
      overridden = list(
        observedProperty = list(label = list(en = "Parent label")),
        unit = list(symbol = "parent-unit")
      )
    ),
    coverages = list(list(
      type = "Coverage",
      id = "child-metadata",
      parameters = list(
        overridden = list(
          observedProperty = list(label = list(en = "Child label"))
        ),
        child_only = list(
          observedProperty = list(label = list(en = "Child only")),
          unit = list(symbol = "s")
        )
      ),
      domain = list(
        type = "Domain",
        domainType = "Point",
        axes = list(
          x = list(values = list(-71)),
          y = list(values = list(42))
        )
      ),
      ranges = list(
        inherited = scalar_range(1),
        overridden = scalar_range(2),
        child_only = scalar_range(3)
      )
    ))
  )

  tb <- covjson_to_tibble(cov)
  expect_equal(
    tb$parameter_label,
    c("Inherited label", "Child label", "Child only")
  )
  expect_equal(tb$unit, c("m", "parent-unit", "s"))
})

test_that("parse_datetime handles each ISO-8601 representation element-wise", {
  iso <- c("2023-01-01T00:00:00Z", "2023-01-02T00:00:00Z")
  p <- edr4r:::parse_datetime(iso)
  expect_s3_class(p, "POSIXct")
  expect_false(any(is.na(p)))

  date_only <- c("2023-01-01", "2023-01-02")
  p2 <- edr4r:::parse_datetime(date_only)
  expect_s3_class(p2, "POSIXct")
  expect_false(any(is.na(p2)))

  mixed <- c(
    "2023-01-01",
    "2023-01-02T00:00:00Z",
    "2023-01-02T01:30:00+01:30",
    "2023-01-01T19:00:00-05:00"
  )
  p3 <- edr4r:::parse_datetime(mixed)
  expect_s3_class(p3, "POSIXct")
  expect_false(any(is.na(p3)))
  expect_equal(
    as.numeric(p3),
    as.numeric(as.POSIXct(c(
      "2023-01-01 00:00:00",
      "2023-01-02 00:00:00",
      "2023-01-02 00:00:00",
      "2023-01-02 00:00:00"
    ), tz = "UTC"))
  )
})

test_that("parse_datetime keeps all original values if any value is invalid", {
  mixed <- c("2023-01-01T00:00:00Z", "not-a-date", NA_character_)
  expect_warning(p <- edr4r:::parse_datetime(mixed), "keeping.*character")
  expect_type(p, "character")
  expect_identical(p, mixed)
})

test_that("datetime parsing never drops a valid offset timestamp", {
  cov <- read_fixture("trajectory.covjson")
  cov$domain$axes$composite$values[[2]][[1]] <- "not-a-date"
  expect_warning(tb <- covjson_to_tibble(cov), "keeping.*character")
  expect_type(tb$datetime, "character")
  expect_equal(tb$datetime[[1]], "2024-06-01T10:00:00Z")
  expect_equal(tb$datetime[[2]], "not-a-date")
})

test_that("NdArray invariants are validated before flattening", {
  make_coverage <- function(range, domain = NULL) {
    if (is.null(domain)) {
      domain <- list(
        type = "Domain",
        domainType = "PointSeries",
        axes = list(
          x = list(values = list(0)),
          y = list(values = list(0)),
          t = list(values = list("2024-01-01", "2024-01-02"))
        )
      )
    }
    list(type = "Coverage", domain = domain, ranges = list(p = range))
  }

  expect_error(
    covjson_to_tibble(make_coverage(list(
      type = "NdArray", dataType = "float",
      axisNames = list("t"), shape = list(3L), values = list(1, 2)
    ))),
    "shape requires 3 values, not 2"
  )
  expect_error(
    covjson_to_tibble(make_coverage(list(
      type = "NdArray", dataType = "float",
      axisNames = list("t"), shape = list(1L), values = list(1)
    ))),
    "domain axis has 2 values"
  )
  expect_error(
    covjson_to_tibble(make_coverage(list(
      type = "NdArray", dataType = "float", values = list(1)
    ))),
    "omits non-scalar domain axes"
  )
  expect_error(
    covjson_to_tibble(make_coverage(list(
      type = "NdArray", dataType = "integer",
      axisNames = list("t"), shape = list(2L), values = list(1, 2.5)
    ))),
    "non-integer values"
  )
  expect_error(
    covjson_to_tibble(make_coverage(list(
      type = "NdArray", dataType = "float",
      axisNames = list("t"), shape = list(2L), values = list(1, "bad")
    ))),
    "declares.*float.*strings"
  )

  scalar <- make_coverage(
    list(
      type = "NdArray", dataType = "float",
      shape = list(), axisNames = list(), values = list(7)
    ),
    domain = list(
      type = "Domain", domainType = "Point",
      axes = list(x = list(values = list(0)), y = list(values = list(0)))
    )
  )
  expect_equal(covjson_to_tibble(scalar)$value, 7)
})

test_that("unsupported or external CoverageJSON components fail clearly", {
  point_domain <- list(
    type = "Domain", domainType = "Point",
    axes = list(x = list(values = list(0)), y = list(values = list(0)))
  )

  expect_error(
    covjson_to_tibble(list(
      type = "Coverage",
      domain = "https://example.test/domain/1",
      ranges = list(p = list(type = "NdArray", values = list(1)))
    )),
    "external domain"
  )
  expect_error(
    covjson_to_tibble(list(
      type = "Coverage", domain = point_domain,
      ranges = list(p = "https://example.test/ranges/p")
    )),
    "external.*ranges"
  )
  expect_error(
    covjson_to_tibble(list(
      type = "Coverage", domain = point_domain,
      ranges = list(p = list(type = "TiledNdArray", tileSets = list()))
    )),
    "TiledNdArray.*not yet supported"
  )
  expect_error(
    covjson_to_tibble(list(
      type = "Coverage", domain = point_domain,
      ranges = list(p = list(type = "SomethingElse", values = list(1)))
    )),
    "expected.*NdArray"
  )
})

test_that("malformed tuple axes fail before coordinates are fabricated", {
  cov <- list(
    type = "Coverage",
    domain = list(
      type = "Domain", domainType = "Trajectory",
      axes = list(composite = list(
        dataType = "tuple",
        coordinates = list("t", "x", "y"),
        values = list(list("2024-01-01T00:00:00Z", -71))
      ))
    ),
    ranges = list(p = list(
      type = "NdArray", dataType = "float",
      axisNames = list("composite"), shape = list(1L), values = list(1)
    ))
  )

  expect_error(covjson_to_tibble(cov), "does not match its 3 coordinates")
})

test_that("mixed datetime formats no longer create silent missing values", {
  mixed <- c("2023-01-01", "2023-01-02T00:00:00Z")
  p <- edr4r:::parse_datetime(mixed)
  expect_s3_class(p, "POSIXct")
  expect_false(is.na(p[[1]]))
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
