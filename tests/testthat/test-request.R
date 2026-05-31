test_that("edr_request builds the URL and parses JSON", {
  captured <- NULL
  httr2::local_mocked_responses(function(req) {
    captured <<- req
    mock_json_response(list(ok = TRUE, n = 3L))
  })

  res <- edr_request(test_client(), "collections/rise-edr/locations",
                     query = list(limit = 5), format = "json")
  expect_equal(res$ok, TRUE)
  expect_match(captured$url, "collections/rise-edr/locations")
  expect_match(captured$url, "limit=5")
  expect_match(captured$url, "f=json")
})

test_that("comma .multi joins repeated parameters", {
  captured <- NULL
  httr2::local_mocked_responses(function(req) {
    captured <<- req
    mock_json_response(list(ok = TRUE))
  })

  edr_request(test_client(), "collections/snotel-edr/cube",
              query = list(`parameter-name` = c("TAVG", "WTEQ")))
  # comma-joined, URL-encoded comma is %2C
  expect_match(captured$url, "parameter-name=TAVG(%2C|,)WTEQ")
})

test_that("geojson format wraps response and can promote to sf", {
  gj <- read_fixture("locations.geojson")
  httr2::local_mocked_responses(function(req) {
    mock_json_response(gj, content_type = "application/geo+json")
  })
  res <- edr_request(test_client(), "collections/rise-edr/locations",
                     format = "geojson")
  expect_s3_class(res, "edr_geojson")
  expect_length(res$geojson$features, 2)
})

test_that("covjson format wraps response", {
  cov <- read_fixture("pointseries.covjson")
  httr2::local_mocked_responses(function(req) mock_json_response(cov))
  res <- edr_request(test_client(), "collections/rise-edr/locations/247",
                     format = "covjson")
  expect_s3_class(res, "edr_covjson")
  expect_length(res$covjson$coverages, 1)
})

test_that("CSV responses parse to a tibble", {
  csv <- "parameter,datetime,value,unit\nstorage,2020-01-01,100.5,acre-feet\n"
  httr2::local_mocked_responses(function(req) {
    mock_text_response(csv, content_type = "text/csv")
  })
  res <- edr_request(test_client(), "collections/rise-edr/locations/247",
                     format = "csv")
  expect_s3_class(res, "tbl_df")
  expect_equal(res$value, 100.5)
})

test_that("HTTP errors are surfaced", {
  httr2::local_mocked_responses(function(req) {
    mock_json_response(list(description = "Location not found"), status = 404L)
  })
  expect_error(
    edr_request(test_client(), "collections/rise-edr/locations/999999"),
    class = "httr2_http_404"
  )
})
