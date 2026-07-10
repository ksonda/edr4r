test_that("edr_request builds the URL and parses JSON", {
  captured <- NULL
  httr2::local_mocked_responses(function(req) {
    captured <<- req
    mock_json_response(list(ok = TRUE, n = 3L))
  })

  res <- edr_request(test_client(), "collections/monitoring-locations/locations",
                     query = list(limit = 5), format = "json")
  expect_equal(res$ok, TRUE)
  expect_match(captured$url, "collections/monitoring-locations/locations")
  expect_match(captured$url, "limit=5")
  expect_match(captured$url, "f=json")
})

test_that("comma .multi joins repeated parameters", {
  captured <- NULL
  httr2::local_mocked_responses(function(req) {
    captured <<- req
    mock_json_response(list(ok = TRUE))
  })

  edr_request(test_client(), "collections/daily-values/cube",
              query = list(`parameter-name` = c("TAVG", "WTEQ")))
  # comma-joined, URL-encoded comma is %2C
  expect_match(captured$url, "parameter-name=TAVG(%2C|,)WTEQ")
})

test_that("geojson format wraps response and can promote to sf", {
  gj <- read_fixture("locations.geojson")
  httr2::local_mocked_responses(function(req) {
    mock_json_response(gj, content_type = "application/geo+json")
  })
  res <- edr_request(test_client(), "collections/monitoring-locations/locations",
                     format = "geojson")
  expect_s3_class(res, "edr_geojson")
  expect_length(res$geojson$features, 2)
})

test_that("covjson format wraps response", {
  cov <- read_fixture("pointseries.covjson")
  httr2::local_mocked_responses(function(req) mock_json_response(cov))
  res <- edr_request(test_client(), "collections/daily-values/locations/08313000",
                     format = "covjson")
  expect_s3_class(res, "edr_covjson")
  expect_length(res$covjson$coverages, 1)
})

test_that("CSV responses parse to a tibble", {
  csv <- "parameter,datetime,value,unit\nstorage,2020-01-01,100.5,acre-feet\n"
  httr2::local_mocked_responses(function(req) {
    mock_text_response(csv, content_type = "text/csv")
  })
  res <- edr_request(test_client(), "collections/daily-values/locations/08313000",
                     format = "csv")
  expect_s3_class(res, "tbl_df")
  expect_equal(res$value, 100.5)
})

test_that("HTTP 204 returns typed empty results", {
  httr2::local_mocked_responses(function(req) mock_empty_response())
  cov <- edr_request(test_client(), "collections/demo/position", format = "covjson")
  expect_s3_class(cov, "edr_empty_response")
  expect_s3_class(cov, "edr_covjson")
  expect_equal(nrow(covjson_to_tibble(cov)), 0L)
  expect_output(print(cov), "status: 204")

  httr2::local_mocked_responses(function(req) mock_empty_response())
  geo <- edr_request(test_client(), "collections/demo/locations", format = "geojson")
  expect_s3_class(geo, "edr_empty_response")
  expect_s3_class(geo, "edr_geojson")

  httr2::local_mocked_responses(function(req) mock_empty_response())
  csv <- edr_request(test_client(), "collections/demo/items", format = "csv")
  expect_s3_class(csv, "tbl_df")
  expect_equal(nrow(csv), 0L)
})

test_that("CSV requests reject JSON success bodies", {
  httr2::local_mocked_responses(function(req) {
    mock_json_response(list(type = "Coverage", domain = list(), ranges = list()))
  })
  expect_error(
    edr_request(test_client(), "collections/demo/position", format = "csv"),
    "Expected a CSV response"
  )
})

test_that("CSV parser handles quoted fields, embedded commas, and newlines", {
  # Regression guard for anyone tempted to swap the parser for something
  # naive (split-on-comma). Base R's read.csv already handles all three.
  csv <- paste0(
    'parameter,datetime,value,unit\n',
    '"flow,daily","2020-01-01",1.5,cfs\n',
    '"qa_flag","2020-01-02","ok, but flagged",NA\n',
    '"longtext","2020-01-03","line1\nline2",NA\n'
  )
  httr2::local_mocked_responses(function(req) {
    mock_text_response(csv, content_type = "text/csv")
  })
  res <- edr_request(test_client(), "x", format = "csv")
  expect_s3_class(res, "tbl_df")
  expect_equal(nrow(res), 3L)
  expect_equal(res$parameter, c("flow,daily", "qa_flag", "longtext"))
  expect_equal(res$value, c("1.5", "ok, but flagged", "line1\nline2"))
})

test_that("HTTP errors are surfaced", {
  httr2::local_mocked_responses(function(req) {
    mock_json_response(list(description = "Location not found"), status = 404L)
  })
  expect_error(
    edr_request(test_client(), "collections/monitoring-locations/locations/999999"),
    class = "httr2_http_404"
  )
})

test_that("is_transient_edr classifies status codes correctly", {
  status <- function(s) structure(list(status_code = s), class = "httr2_response")

  for (s in c(408L, 429L, 500L, 502L, 503L, 504L, 599L)) {
    expect_true(edr4r:::is_transient_edr(status(s)),
                info = paste("status =", s))
  }
  for (s in c(200L, 201L, 301L, 400L, 401L, 403L, 404L, 410L, 422L)) {
    expect_false(edr4r:::is_transient_edr(status(s)),
                 info = paste("status =", s))
  }
})

test_that("edr_request retries transient responses against a real server", {
  skip_if_not_installed("webfakes")

  app <- webfakes::new_app()
  app$locals$attempts <- 0L
  app$get("/collections", function(req, res) {
    res$app$locals$attempts <- res$app$locals$attempts + 1L

    if (res$app$locals$attempts == 1L) {
      res$set_header("Retry-After", "0")
      res$set_status(503L)
      return(res$send_json(list(description = "try again")))
    }

    res$send_json(
      list(ok = TRUE, attempts = res$app$locals$attempts),
      auto_unbox = TRUE
    )
  })

  process <- webfakes::new_app_process(app)
  on.exit(process$stop(), add = TRUE)

  result <- edr_request(
    edr_client(process$url(), max_tries = 3L),
    "collections"
  )

  expect_true(result$ok)
  expect_equal(result$attempts, 2L)
})

test_that("edr_error_body surfaces JSON 'description' in the error message", {
  httr2::local_mocked_responses(function(req) {
    mock_json_response(
      list(description = "Collection 'nope' not found"),
      status = 404L
    )
  })
  expect_error(
    edr_request(test_client(), "collections/nope"),
    "Collection 'nope' not found"
  )
})

test_that("edr_error_body also recognises 'detail', 'message', 'title'", {
  for (key in c("detail", "message", "title")) {
    body <- setNames(list("custom-msg"), key)
    httr2::local_mocked_responses(function(req) {
      mock_json_response(body, status = 400L)
    })
    expect_error(
      edr_request(test_client(), "x"),
      "custom-msg",
      info = paste("error key =", key)
    )
  }
})

test_that("plain-text error bodies are truncated to 500 chars", {
  big <- paste(rep("A", 1500), collapse = "")
  httr2::local_mocked_responses(function(req) {
    mock_text_response(big, content_type = "text/plain", status = 500L)
  })
  err <- tryCatch(
    edr_request(test_client(), "x"),
    error = function(e) e
  )
  # The truncated body lives in the error's body field (returned by
  # edr_error_body). It should be exactly 500 chars, not 1500.
  expect_true(nchar(err$body) <= 500L)
  expect_match(err$body, "^A+$")
})

test_that("verbose = TRUE logs the request URL", {
  httr2::local_mocked_responses(function(req) {
    mock_json_response(list(ok = TRUE))
  })
  cl <- edr_client("http://test", verbose = TRUE)
  expect_message(
    edr_request(cl, "collections"),
    "GET .*collections"
  )
})

test_that("single Coverage and Feature responses print the correct count", {
  cov <- structure(
    list(covjson = list(type = "Coverage", domain = list(), ranges = list())),
    class = c("edr_response", "edr_covjson", "list")
  )
  feature <- structure(
    list(geojson = list(type = "Feature", properties = list(), geometry = NULL)),
    class = c("edr_response", "edr_geojson", "list")
  )
  expect_output(print(cov), "coverages: 1")
  expect_output(print(feature), "features: 1")
})
