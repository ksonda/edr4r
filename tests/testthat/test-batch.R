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
    c(
      "collection_id", "instance_id", "format", "requests", "data", "errors",
      "parameters"
    )
  )
  expect_null(result$parameters)
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

test_that("batch parameter catalogs are explicit, cached, and nonduplicated", {
  coverage <- read_fixture("pointseries.covjson")
  metadata <- read_fixture("instances.json")$instances[[1L]]
  metadata$parameter_names$air_temperature <- list(
    type = "Parameter",
    label = "Air temperature",
    description = "Near-surface air temperature",
    unit = list(
      label = "kelvin",
      symbol = list(value = "K", type = "https://qudt.org/vocab/unit/K"),
      definition = "https://qudt.org/vocab/unit/K-PER-K"
    ),
    observedProperty = list(id = "https://example.test/observed/air-temperature")
  )
  urls <- character()
  httr2::local_mocked_responses(function(req) {
    urls <<- c(urls, req$url)
    path <- sub("[?].*$", "", req$url)
    if (grepl("/collections/demo$", path)) {
      return(mock_json_response(metadata))
    }
    mock_json_response(coverage)
  })
  client <- edr_client("http://test", max_tries = 1, cache_ttl = Inf)

  result <- edr_location_batch(
    client, "demo", c("station-a", "station-b"),
    include_parameters = TRUE,
    progress = FALSE
  )

  expect_s3_class(result$parameters, "tbl_df")
  expect_equal(nrow(result$parameters), 1L)
  expect_equal(result$parameters$id, "air_temperature")
  expect_equal(result$parameters$description, "Near-surface air temperature")
  expect_equal(result$parameters$unit_symbol, "K")
  expect_equal(result$parameters$unit_symbol_type, "https://qudt.org/vocab/unit/K")
  expect_equal(result$parameters$unit_label, "kelvin")
  expect_equal(
    result$parameters$unit_definition,
    "https://qudt.org/vocab/unit/K-PER-K"
  )
  expect_equal(result$parameters$unit_id, "https://qudt.org/vocab/unit/K")
  expect_equal(length(urls), 3L)
  expect_equal(sum(grepl("/collections/demo$", sub("[?].*$", "", urls))), 1L)
  expect_output(print(result), "parameters:.*1 definition")

  # A later explicit metadata request reuses the batch's discovery response.
  expect_equal(edr_parameters(client, "demo"), result$parameters)
  expect_equal(length(urls), 3L)
})

test_that("instance-scoped batch catalogs use instance metadata", {
  coverage <- read_fixture("pointseries.covjson")
  metadata <- list(
    id = "run 00",
    parameter_names = list(
      wind = list(
        label = "Wind speed",
        unit = list(symbol = "m/s")
      )
    )
  )
  urls <- character()
  httr2::local_mocked_responses(function(req) {
    urls <<- c(urls, utils::URLdecode(req$url))
    path <- sub("[?].*$", "", utils::URLdecode(req$url))
    if (endsWith(path, "/instances/run 00")) {
      return(mock_json_response(metadata))
    }
    mock_json_response(coverage)
  })

  result <- edr_location_batch(
    test_client(), "model", "station",
    instance_id = "run 00",
    include_parameters = TRUE,
    progress = FALSE
  )

  expect_equal(result$parameters$id, "wind")
  expect_equal(result$parameters$unit_symbol, "m/s")
  expect_equal(length(urls), 2L)
  expect_true(endsWith(
    sub("[?].*$", "", urls[[1L]]),
    "/collections/model/instances/run 00"
  ))
  expect_true(grepl(
    "/collections/model/instances/run 00/locations/station", urls[[2L]],
    fixed = TRUE
  ))
})

test_that("time chunks expand the bounded plan and remove boundary duplicates", {
  calls <- 0L
  urls <- character()
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    urls <<- c(urls, utils::URLdecode(req$url))
    text <- if (calls %% 2L == 1L) {
      paste0(
        "parameter,datetime,value\n",
        "flow,2024-01-01,1\n",
        "flow,2024-01-02,2\n",
        "temperature,2024-01-02,10\n"
      )
    } else {
      paste0(
        "parameter,datetime,value\n",
        "flow,2024-01-02,2\n",
        "temperature,2024-01-02,10\n",
        "flow,2024-01-03,3\n"
      )
    }
    mock_text_response(text, content_type = "text/csv")
  })

  result <- edr_location_batch(
    test_client(), "demo", c("station-a", "station-b"),
    datetime = "2024-01-01/2024-01-03",
    format = "csv",
    chunk = "1 day",
    max_requests = 4L,
    progress = FALSE
  )

  expect_equal(calls, 4L)
  expect_equal(
    result$requests,
    tibble::tibble(
      request_id = 1:4,
      location_id = rep(c("station-a", "station-b"), each = 2L),
      datetime = rep(c(
        "2024-01-01/2024-01-02",
        "2024-01-02/2024-01-03"
      ), 2L),
      status = rep("success", 4L),
      n_rows = rep(3L, 4L)
    )
  )
  expect_equal(nrow(result$data), 8L)
  expect_equal(
    result$data$.location_id,
    rep(c("station-a", "station-b"), each = 4L)
  )
  expect_equal(
    result$data$datetime,
    rep(c("2024-01-01", "2024-01-02", "2024-01-02", "2024-01-03"), 2L)
  )
  expect_equal(result$data$.request_id, c(1L, 1L, 1L, 2L, 3L, 3L, 3L, 4L))
  expect_true(grepl(
    "datetime=2024-01-01/2024-01-02", urls[[1]], fixed = TRUE
  ))
  expect_true(grepl(
    "datetime=2024-01-02/2024-01-03", urls[[2]], fixed = TRUE
  ))
  expect_match(urls[[3]], "/station-b?", fixed = TRUE)

  raw <- edr_location_batch(
    test_client(), "demo", c("station-a", "station-b"),
    datetime = "2024-01-01/2024-01-03",
    format = "csv",
    chunk = "1 day",
    deduplicate = FALSE,
    max_requests = 4L,
    progress = FALSE
  )
  expect_equal(nrow(raw$data), 12L)
})

test_that("CoverageJSON chunks deduplicate typed boundary observations", {
  make_coverage <- function(times, discharge, gage_height) {
    coverage <- read_fixture("pointseries.covjson")
    item <- coverage$coverages[[1L]]
    item$domain$axes$t$values <- as.list(times)
    item$ranges$discharge$shape <- list(length(times))
    item$ranges$discharge$values <- as.list(discharge)
    item$ranges$gage_height$shape <- list(length(times))
    item$ranges$gage_height$values <- as.list(gage_height)
    coverage$coverages[[1L]] <- item
    coverage
  }

  responses <- list(
    make_coverage(
      c("2020-01-01T00:00:00Z", "2020-01-02T00:00:00Z"),
      c(100, 101), c(5, 6)
    ),
    make_coverage(
      c("2020-01-02T00:00:00Z", "2020-01-03T00:00:00Z"),
      c(101, 102), c(6, 7)
    )
  )
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    mock_json_response(responses[[calls]])
  })

  result <- edr_location_batch(
    test_client(), "demo", "08313000",
    datetime = "2020-01-01/2020-01-03",
    chunk = "1 day",
    max_requests = 2L,
    progress = FALSE
  )

  expect_equal(result$requests$n_rows, c(4L, 4L))
  expect_equal(nrow(result$data), 6L)
  boundary <- as.POSIXct("2020-01-02", tz = "UTC")
  expect_equal(sum(result$data$datetime == boundary), 2L)
  expect_true(all(result$data$.request_id[result$data$datetime == boundary] == 1L))
})

test_that("chunk deduplication preserves distinct custom-axis members", {
  coverage <- read_fixture("custom-axis.covjson")
  coverage$ranges$temperature$values <- as.list(rep(1, 8L))
  httr2::local_mocked_responses(function(req) mock_json_response(coverage))

  result <- edr_location_batch(
    test_client(), "ensemble", "station",
    datetime = "2024-01-01/2024-01-03",
    chunk = "1 day",
    max_requests = 2L,
    progress = FALSE
  )

  expect_equal(result$requests$n_rows, c(8L, 8L))
  expect_equal(nrow(result$data), 8L)
  expect_setequal(
    unique(result$data$.axis_realisations),
    c("control", "perturbed")
  )
  expect_equal(
    as.integer(table(result$data$.axis_realisations)),
    c(4L, 4L)
  )

  metadata <- attr(result$data, "edr_covjson_metadata")$coverages
  expect_equal(nrow(metadata), 1L)
  expect_equal(metadata$.request_id, 1L)
  expect_equal(metadata$.location_id, "station")
})

test_that("calendar chunks clamp end-of-month boundaries to the anchor day", {
  expect_equal(
    edr4r:::batch_datetime_windows(
      c("2024-01-01", "2024-01-03"), "1 day", max_windows = 10L
    ),
    edr4r:::batch_datetime_windows(
      "2024-01-01/2024-01-03", "1 day", max_windows = 10L
    )
  )

  expect_equal(
    edr4r:::batch_datetime_windows(
      "2024-01-31/2024-05-01", "1 month", max_windows = 10L
    ),
    c(
      "2024-01-31/2024-02-29",
      "2024-02-29/2024-03-31",
      "2024-03-31/2024-04-30",
      "2024-04-30/2024-05-01"
    )
  )

  expect_equal(
    edr4r:::batch_datetime_windows(
      "2024-01-01T00:00:00-05:00/2024-01-04T00:00:00-05:00",
      "1 day",
      max_windows = 10L
    ),
    c(
      "2024-01-01T05:00:00Z/2024-01-02T05:00:00Z",
      "2024-01-02T05:00:00Z/2024-01-03T05:00:00Z",
      "2024-01-03T05:00:00Z/2024-01-04T05:00:00Z"
    )
  )

  expect_equal(
    edr4r:::batch_datetime_windows(
      "2024-02-29/2028-03-01", "1 year", max_windows = 10L
    ),
    c(
      "2024-02-29/2025-02-28",
      "2025-02-28/2026-02-28",
      "2026-02-28/2027-02-28",
      "2027-02-28/2028-02-29",
      "2028-02-29/2028-03-01"
    )
  )

  expect_equal(
    edr4r:::batch_datetime_windows(
      "2022-07-12T00:00Z/2022-07-14T00:00Z",
      "  1 DAY  ",
      max_windows = 10L
    ),
    c(
      "2022-07-12T00:00:00Z/2022-07-13T00:00:00Z",
      "2022-07-13T00:00:00Z/2022-07-14T00:00:00Z"
    )
  )

  expect_equal(
    edr4r:::batch_datetime_windows(
      "2024-01-01T00:00:00.1Z/2024-01-02T00:00:00.1Z",
      "1 day",
      max_windows = 2L
    ),
    "2024-01-01T00:00:00.1Z/2024-01-02T00:00:00.1Z"
  )
  expect_equal(
    edr4r:::batch_datetime_windows(
      "2024-01-01T00:00:00.000001Z/2024-01-02T00:00:00.000001Z",
      "1 day",
      max_windows = 2L
    ),
    "2024-01-01T00:00:00.000001Z/2024-01-02T00:00:00.000001Z"
  )
  expect_equal(
    edr4r:::batch_datetime_windows(
      "2024-01-01/2025-01-01",
      "2147483647 years",
      max_windows = 2L
    ),
    "2024-01-01/2025-01-01"
  )
})

test_that("window deduplication is cross-request and station scoped", {
  data <- tibble::tibble(
    .request_id = c(1L, 1L, 1L, 2L, 2L, 3L),
    .location_id = c("a", "a", "a", "a", "a", "b"),
    parameter = "flow",
    datetime = c(
      "2024-01-01", "2024-01-02", "2024-01-02",
      "2024-01-02", "2024-01-02", "2024-01-02"
    ),
    value = c(1, 2, 2, 2, 99, 2)
  )

  result <- edr4r:::deduplicate_batch_window_rows(data)

  # Both identical rows from request 1 remain. Request 2 loses only the
  # exact row seen earlier; its changed value remains. Location b is distinct.
  expect_equal(result$.request_id, c(1L, 1L, 1L, 2L, 3L))
  expect_equal(result$value, c(1, 2, 2, 99, 2))
})

test_that("chunk errors retain request ids that identify their windows", {
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    if (calls == 2L) {
      return(mock_json_response(
        list(description = "window unavailable"), status = 503L
      ))
    }
    mock_text_response(
      paste0("datetime,value\n2024-01-0", calls, ",", calls, "\n"),
      content_type = "text/csv"
    )
  })

  result <- edr_location_batch(
    test_client(), "demo", "station",
    datetime = "2024-01-01/2024-01-04",
    format = "csv",
    chunk = "1 day",
    max_requests = 3L,
    on_error = "collect",
    progress = FALSE
  )

  expect_equal(result$requests$status, c("success", "error", "success"))
  expect_equal(result$errors$request_id, 2L)
  expect_equal(
    result$requests$datetime[result$errors$request_id],
    "2024-01-02/2024-01-03"
  )
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
  expect_error(
    edr_location_batch(
      client, "demo", c("a", "b"),
      datetime = "2024-01-01/2024-01-03",
      chunk = "1 day", max_requests = 3L, progress = FALSE
    ),
    "exceeding.*max_requests"
  )
  expect_error(
    edr_location_batch(client, "demo", "a", chunk = "1 day", progress = FALSE),
    "bounded.*datetime"
  )
  expect_error(
    edr_location_batch(
      client, "demo", "a", datetime = NA_character_, progress = FALSE
    ),
    "datetime.*missing"
  )
  expect_error(
    edr_location_batch(
      client, "demo", "a", datetime = "2024-01-01/..",
      chunk = "1 day", progress = FALSE
    ),
    "bounded.*datetime"
  )
  expect_error(
    edr_location_batch(
      client, "demo", "a", datetime = "2024-01-01",
      chunk = "1 day", progress = FALSE
    ),
    "bounded.*datetime"
  )
  expect_error(
    edr_location_batch(
      client, "demo", "a", datetime = "2024-01-03/2024-01-01",
      chunk = "1 day", progress = FALSE
    ),
    "start.*before.*end"
  )
  for (bad_datetime in c(
    "2024-02-30/2024-03-02",
    "2024-01-01T25:00:00Z/2024-01-02T00:00:00Z",
    "2024-01-01T00:00:60Z/2024-01-02T00:00:00Z",
    "2024-01-01T00:00:00.1234567Z/2024-01-02T00:00:00.1234567Z",
    "2250-01-01T00:00:00.000001Z/2250-01-02T00:00:00.000001Z",
    "2250-01-01T00:00:00.2Z/2250-01-02T00:00:00.000000Z",
    "2024-01-01/2024-01-02/2024-01-03"
  )) {
    expect_error(
      edr_location_batch(
        client, "demo", "a", datetime = bad_datetime,
        chunk = "1 day", progress = FALSE
      ),
      "datetime|parse|bounded"
    )
  }
  for (bad_chunk in list("", "monthly", "0 days", "1.5 days", "1 hour", 1)) {
    expect_error(
      edr_location_batch(
        client, "demo", "a", datetime = "2024-01-01/2024-01-03",
        chunk = bad_chunk, progress = FALSE
      ),
      "chunk"
    )
  }
  expect_error(
    edr_location_batch(
      client, "demo", "a", datetime = "2024-01-01/2024-01-03",
      chunk = "1 day", deduplicate = NA, progress = FALSE
    ),
    "deduplicate.*TRUE.*FALSE"
  )
  expect_error(
    edr_location_batch(
      client, "demo", "a", include_parameters = NA, progress = FALSE
    ),
    "include_parameters.*TRUE.*FALSE"
  )
  expect_error(
    edr_location_batch(client, "demo", "a", f = NA_character_, progress = FALSE),
    "f.*single non-empty string"
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
  for (argument in c(
    "chunk", "deduplicate", "include_parameters", "max_requests",
    "on_error", "progress", "instance_id", "f"
  )) {
    expect_gt(match(argument, formal_names), match("...", formal_names))
  }
})
