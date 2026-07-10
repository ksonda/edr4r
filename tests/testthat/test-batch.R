test_that("edr_location_batch returns ordered, provenance-rich data", {
  coverage <- read_fixture("pointseries.covjson")
  urls <- character()
  httr2::local_mocked_responses(function(req) {
    urls <<- c(urls, req$url)
    mock_json_response(coverage)
  })

  result <- edr_location_batch(
    test_client(), "model family", c("station a", "station:b"),
    datetime = c("2024-01-01", "2024-01-31"),
    parameter_name = "discharge",
    z = "surface",
    crs = "CRS84",
    limit = 20L,
    progress = FALSE,
    instance_id = "run 00"
  )

  expect_s3_class(result, "edr_location_batch")
  expect_s3_class(result, "edr_batch")
  expect_identical(result$collection_id, "model family")
  expect_identical(result$instance_id, "run 00")
  expect_identical(result$format, "covjson")
  expect_equal(
    names(result),
    c("collection_id", "instance_id", "format", "requests", "data", "errors")
  )
  expect_s3_class(result$requests, "tbl_df")
  expect_s3_class(result$data, "tbl_df")
  expect_s3_class(result$errors, "tbl_df")
  expect_equal(
    result$requests,
    tibble::tibble(
      request_id = 1:2,
      location_id = c("station a", "station:b"),
      datetime = rep("2024-01-01/2024-01-31", 2),
      status = rep("success", 2),
      n_rows = rep(6L, 2)
    )
  )
  expect_equal(result$data$.request_id, rep(1:2, each = 6L))
  expect_equal(
    result$data$.location_id,
    rep(c("station a", "station:b"), each = 6L)
  )
  expect_equal(nrow(result$errors), 0L)
  expect_type(result$errors$http_status, "integer")
  expect_type(result$errors$condition, "list")

  expect_equal(length(urls), 2L)
  decoded <- utils::URLdecode(urls)
  expect_true(all(grepl(
    "/collections/model family/instances/run 00/locations/",
    decoded,
    fixed = TRUE
  )))
  expect_match(decoded[[1]], "/station a?", fixed = TRUE)
  expect_match(decoded[[2]], "/station:b?", fixed = TRUE)
  expect_true(all(grepl("datetime=2024-01-01/2024-01-31", decoded, fixed = TRUE)))
  expect_true(all(grepl("parameter-name=discharge", decoded, fixed = TRUE)))
  expect_true(all(grepl("z=surface", decoded, fixed = TRUE)))
  expect_true(all(grepl("crs=CRS84", decoded, fixed = TRUE)))
  expect_true(all(grepl("limit=20", decoded, fixed = TRUE)))

  expect_output(print(result), "requests:.*2.*2 success")
  expect_output(print(result), "instance:.*run 00")
})

test_that("batch validation finishes before network activity", {
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    cli::cli_abort("network should not be called")
  })
  client <- test_client()

  expect_error(edr_location_batch(client, "demo", 1, progress = FALSE), "character vector")
  expect_error(edr_location_batch(client, "demo", character(), progress = FALSE), "character vector")
  expect_error(edr_location_batch(client, "demo", c("ok", NA_character_), progress = FALSE), "missing")
  expect_error(edr_location_batch(client, "demo", c("ok", "  "), progress = FALSE), "blank")
  expect_error(edr_location_batch(client, "demo", c("same", "same"), progress = FALSE), "unique")
  expect_error(edr_location_batch(client, "demo", "a/b", progress = FALSE), "must not contain")
  expect_error(
    edr_location_batch(client, "demo", c("a", "b"), max_requests = 1L, progress = FALSE),
    "exceeding.*max_requests"
  )
  for (cap in list(Inf, 0, -1, 1.5, NA_real_, 1e20)) {
    expect_error(
      edr_location_batch(client, "demo", "a", max_requests = cap, progress = FALSE),
      "finite positive integer"
    )
  }
  expect_error(
    edr_location_batch(client, "demo", "a", progress = NA),
    "progress.*TRUE.*FALSE"
  )
  expect_error(
    edr_location_batch(client, "demo", "a", bad = list(1), progress = FALSE),
    "atomic vectors"
  )
  expect_error(
    edr_location_batch(client, "demo", "a", instance_id = "run/00", progress = FALSE),
    "instance_id.*must not contain"
  )
  expect_error(
    edr_location_batch(client, "bad/collection", "a", progress = FALSE),
    "collection_id.*must not contain"
  )
  expect_error(
    edr_location_batch(client, "demo", "a", format = "geojson", progress = FALSE),
    "should be one of"
  )
  expect_equal(calls, 0L)
})

test_that("on_error stop preserves the first condition and stops the loop", {
  coverage <- read_fixture("pointseries.covjson")
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    if (calls == 1L) {
      mock_json_response(coverage)
    } else if (calls == 2L) {
      mock_json_response(list(description = "missing station"), status = 404L)
    } else {
      mock_json_response(coverage)
    }
  })

  expect_error(
    edr_location_batch(
      test_client(), "demo", c("ok", "missing", "not-run"),
      progress = FALSE
    ),
    "missing station",
    class = "httr2_http_404"
  )
  expect_equal(calls, 2L)
})

test_that("on_error collect records HTTP and parser failures without warning", {
  coverage <- read_fixture("pointseries.covjson")
  malformed <- list(
    type = "Coverage",
    parameters = list(temp = list()),
    ranges = list(
      temp = list(
        type = "NdArray",
        axisNames = list("t"),
        shape = list(1L),
        values = list(1)
      )
    )
  )
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    if (calls == 1L) {
      mock_json_response(coverage)
    } else if (calls == 2L) {
      mock_json_response(list(description = "missing station"), status = 404L)
    } else {
      mock_json_response(malformed)
    }
  })

  expect_no_warning(
    result <- edr_location_batch(
      test_client(), "demo", c("ok", "missing", "malformed"),
      on_error = "collect", progress = FALSE
    )
  )

  expect_equal(calls, 3L)
  expect_equal(result$requests$status, c("success", "error", "error"))
  expect_equal(result$requests$n_rows, c(6L, NA_integer_, NA_integer_))
  expect_equal(unique(result$data$.request_id), 1L)
  expect_equal(unique(result$data$.location_id), "ok")
  expect_equal(result$errors$request_id, 2:3)
  expect_equal(result$errors$location_id, c("missing", "malformed"))
  expect_equal(result$errors$condition_class[[1]], "httr2_http_404")
  expect_equal(result$errors$http_status, c(404L, NA_integer_))
  expect_match(result$errors$message[[1]], "404.*missing station")
  expect_match(result$errors$message[[2]], "no inline CoverageJSON domain")
  expect_s3_class(result$errors$condition[[1]], "httr2_http_404")
  expect_s3_class(result$errors$condition[[2]], "error")
})

test_that("empty responses are successes with explicit empty status", {
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    if (calls == 1L) {
      mock_empty_response()
    } else {
      mock_json_response(list(
        type = "CoverageCollection",
        parameters = list(),
        coverages = list()
      ))
    }
  })

  result <- edr_location_batch(
    test_client(), "demo", c("no-content", "no-coverages"),
    on_error = "collect", progress = FALSE
  )

  expect_equal(result$requests$status, c("empty", "empty"))
  expect_equal(result$requests$n_rows, c(0L, 0L))
  expect_equal(nrow(result$data), 0L)
  expect_equal(
    names(result$data),
    c(
      ".request_id", ".location_id", "coverage_id", "parameter",
      "parameter_label", "unit", "datetime", "x", "y", "z", "value"
    )
  )
  expect_equal(nrow(result$errors), 0L)
})

test_that("all collected failures return typed empty data and errors", {
  httr2::local_mocked_responses(function(req) {
    mock_json_response(list(description = "gone"), status = 404L)
  })

  result <- edr_location_batch(
    test_client(), "demo", c("gone-1", "gone-2"),
    on_error = "collect", progress = FALSE
  )

  expect_equal(result$requests$status, c("error", "error"))
  expect_equal(nrow(result$data), 0L)
  expect_type(result$data$.request_id, "integer")
  expect_type(result$data$.location_id, "character")
  expect_equal(result$errors$request_id, 1:2)
  expect_equal(result$errors$http_status, c(404L, 404L))
})

test_that("CSV batches reconcile differing atomic column types deterministically", {
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    text <- if (calls == 1L) {
      "parameter,value\nflow,1.5\n"
    } else {
      "parameter,value\nflow,flagged\n"
    }
    mock_text_response(text, content_type = "text/csv")
  })

  expect_warning(
    result <- edr_location_batch(
      test_client(), "demo", c("numeric", "text"),
      format = "csv", progress = FALSE
    ),
    "Demoted batch column.*value"
  )

  expect_equal(result$requests$status, c("success", "success"))
  expect_equal(result$data$.request_id, 1:2)
  expect_equal(result$data$.location_id, c("numeric", "text"))
  expect_type(result$data$value, "character")
  expect_equal(result$data$value, c("1.5", "flagged"))
})

test_that("reserved provenance columns become per-request parser failures", {
  httr2::local_mocked_responses(function(req) {
    mock_text_response(".request_id,value\nserver,1\n", content_type = "text/csv")
  })

  result <- edr_location_batch(
    test_client(), "demo", "station",
    format = "csv", on_error = "collect", progress = FALSE
  )

  expect_equal(result$requests$status, "error")
  expect_equal(nrow(result$data), 0L)
  expect_match(result$errors$message, "reserved provenance columns")
})

test_that("batch controls and instance_id are keyword-only", {
  formal_names <- names(formals(edr_location_batch))
  for (argument in c("max_requests", "on_error", "progress", "instance_id")) {
    expect_gt(match(argument, formal_names), match("...", formal_names))
  }
})
