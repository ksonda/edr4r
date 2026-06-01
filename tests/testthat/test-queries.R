test_that("edr_location URL-encodes ids and sends filters", {
  captured <- NULL
  cov <- read_fixture("pointseries.covjson")
  httr2::local_mocked_responses(function(req) {
    captured <<- req
    mock_json_response(cov)
  })

  res <- edr_location(test_client(), "awdb-forecasts-edr",
                      location_id = "1185:CO:SNTL",
                      datetime = "2020-01-01/..",
                      parameter_name = "WTEQ")
  expect_s3_class(res, "edr_covjson")
  # Colons are legal in a path segment, so the normalized URL keeps them
  # literal; the server accepts station triplets in this form.
  expect_match(captured$url, "locations/1185:CO:SNTL")
  expect_match(captured$url, "datetime=2020-01-01")
  expect_match(captured$url, "parameter-name=WTEQ")
})

test_that("edr_location percent-encodes unsafe id characters", {
  captured <- NULL
  cov <- read_fixture("pointseries.covjson")
  httr2::local_mocked_responses(function(req) {
    captured <<- req
    mock_json_response(cov)
  })
  edr_location(test_client(), "demo", location_id = "a b", format = "json")
  expect_match(captured$url, "locations/a%20b")
})

test_that("edr_location resists query / fragment injection in ids", {
  # '?', '#', '&' would otherwise reshape the URL into query/fragment/etc.
  # Pre-encoding forces them inside the location-id segment.
  for (id in c("a?b", "a#b", "a&b")) {
    captured <- NULL
    cov <- read_fixture("pointseries.covjson")
    httr2::local_mocked_responses(function(req) {
      captured <<- req
      mock_json_response(cov)
    })
    edr_location(test_client(), "demo", location_id = id, format = "json")
    enc <- utils::URLencode(id, reserved = TRUE)
    expect_match(captured$url, paste0("locations/", enc), fixed = TRUE,
                 info = paste("id =", id))
    # Belt-and-braces: exactly one '/locations/' segment in the path.
    path <- sub("\\?.*$", "", captured$url)
    expect_equal(length(gregexpr("/locations/", path, fixed = TRUE)[[1]]), 1L,
                 info = paste("id =", id))
  }
})

test_that("edr_location rejects ids containing '/'", {
  expect_error(
    edr_location(test_client(), "demo", location_id = "a/b"),
    "must not contain"
  )
  expect_error(
    edr_item(test_client(), "demo", item_id = "a/b"),
    "must not contain"
  )
})

test_that("edr_cube serializes bbox and validates it", {
  captured <- NULL
  cov <- read_fixture("pointseries.covjson")
  httr2::local_mocked_responses(function(req) {
    captured <<- req
    mock_json_response(cov)
  })

  edr_cube(test_client(), "rise-edr",
           bbox = c(-101.4, 27.2, -92.7, 32.2),
           datetime = "2020-01-01/2020-12-31")
  expect_match(captured$url, "cube")
  expect_match(captured$url, "bbox=-101.4(%2C|,)27.2")

  expect_error(
    edr_cube(test_client(), "rise-edr", bbox = c(1, 2, 3)),
    "length 4 or 6"
  )
})

test_that("edr_area builds a POLYGON coords param", {
  captured <- NULL
  cov <- read_fixture("pointseries.covjson")
  httr2::local_mocked_responses(function(req) {
    captured <<- req
    mock_json_response(cov)
  })

  edr_area(test_client(), "rise-edr",
           coords = matrix(c(-109, 47, -104, 47, -104, 49, -109, 49),
                           ncol = 2, byrow = TRUE))
  expect_match(captured$url, "area")
  expect_match(utils::URLdecode(captured$url), "POLYGON\\(\\(")
})

test_that("edr_locations promotes GeoJSON to sf when sf present", {
  skip_if_not_installed("sf")
  gj <- read_fixture("locations.geojson")
  httr2::local_mocked_responses(function(req) {
    mock_json_response(gj, content_type = "application/geo+json")
  })
  res <- edr_locations(test_client(), "rise-edr")
  expect_s3_class(res, "sf")
  expect_equal(nrow(res), 2)
})

test_that("edr_position builds a POINT coords param", {
  captured <- NULL
  cov <- read_fixture("pointseries.covjson")
  httr2::local_mocked_responses(function(req) {
    captured <<- req
    mock_json_response(cov)
  })
  edr_position(test_client(), "rise-edr", coords = c(-105.5, 40.2))
  expect_match(utils::URLdecode(captured$url), "POINT\\(-105.5 40.2\\)")
})

test_that("edr_radius requires numeric within", {
  expect_error(
    edr_radius(test_client(), "rise-edr", coords = c(0, 0), within = "x"),
    "single numeric"
  )
})
