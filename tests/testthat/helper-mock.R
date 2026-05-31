# Shared helpers for mocking httr2 responses without network access.

fixture_path <- function(name) {
  testthat::test_path("fixtures", name)
}

read_fixture <- function(name) {
  jsonlite::fromJSON(fixture_path(name), simplifyVector = FALSE)
}

# Build a mock httr2 response from an R list serialized to JSON.
mock_json_response <- function(body_list,
                               content_type = "application/json",
                               status = 200L,
                               url = "http://test/local") {
  httr2::response(
    status_code = status,
    url         = url,
    method      = "GET",
    headers     = list(`Content-Type` = content_type),
    body        = charToRaw(jsonlite::toJSON(body_list, auto_unbox = TRUE, null = "null", digits = NA))
  )
}

# Build a mock response from a raw string body (e.g. CSV).
mock_text_response <- function(text,
                               content_type = "text/csv",
                               status = 200L,
                               url = "http://test/local") {
  httr2::response(
    status_code = status,
    url         = url,
    method      = "GET",
    headers     = list(`Content-Type` = content_type),
    body        = charToRaw(text)
  )
}

test_client <- function() {
  edr_client("http://test", max_tries = 1)
}
