checkpoint_test_result_path <- function(checkpoint, request_id) {
  file.path(
    checkpoint,
    "results",
    sprintf("%010d.rds", as.integer(request_id))
  )
}

checkpoint_test_expect_unlocked <- function(checkpoint) {
  expect_false(dir.exists(file.path(checkpoint, ".edr4r-lock")))
}

checkpoint_test_override <- function(args, overrides) {
  for (name in names(overrides)) args[[name]] <- overrides[[name]]
  args
}

checkpoint_test_copy <- function(source) {
  target <- tempfile("edr4r-checkpoint-copy-")
  dir.create(target)

  entries <- list.files(
    source,
    all.files = TRUE,
    no.. = TRUE,
    recursive = TRUE,
    include.dirs = TRUE
  )
  if (length(entries) == 0L) return(target)

  info <- file.info(file.path(source, entries))
  directories <- entries[!is.na(info$isdir) & info$isdir]
  for (directory in directories) {
    dir.create(file.path(target, directory), recursive = TRUE)
  }

  files <- entries[is.na(info$isdir) | !info$isdir]
  if (length(files) > 0L) {
    ok <- file.copy(
      file.path(source, files),
      file.path(target, files),
      overwrite = FALSE,
      copy.mode = TRUE,
      copy.date = TRUE
    )
    if (!all(ok)) stop("Could not copy checkpoint test fixture.", call. = FALSE)
  }
  target
}

checkpoint_test_seed <- function(checkpoint, overrides = list()) {
  args <- list(
    client = test_client(),
    collection_id = "demo",
    location_id = "station",
    datetime = "2024-01-01/2024-01-03",
    format = "csv",
    chunk = "1 day",
    max_requests = 2L,
    on_error = "collect",
    progress = FALSE,
    checkpoint = checkpoint
  )
  args <- checkpoint_test_override(args, overrides)

  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    mock_text_response(
      paste0(
        "datetime,value\n",
        sprintf("2024-01-%02d,%d\n", calls, calls)
      ),
      content_type = "text/csv"
    )
  })

  result <- do.call(edr_location_batch, args)
  list(result = result, calls = calls, args = args)
}

test_that("checkpoint controls are keyword-only and preserve public structure", {
  formal_names <- names(formals(edr_location_batch))
  expect_gt(match("checkpoint", formal_names), match("...", formal_names))
  expect_gt(match("resume", formal_names), match("...", formal_names))

  checkpoint <- tempfile("edr4r-checkpoint-")
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    if (calls == 1L) {
      mock_text_response(
        "datetime,value\n2024-01-01,1\n",
        content_type = "text/csv"
      )
    } else {
      mock_empty_response()
    }
  })

  first <- edr_location_batch(
    test_client(), "demo", "station",
    datetime = "2024-01-01/2024-01-03",
    format = "csv",
    chunk = "1 day",
    max_requests = 2L,
    on_error = "collect",
    progress = FALSE,
    checkpoint = checkpoint
  )

  expect_equal(calls, 2L)
  expect_s3_class(first, "edr_location_batch")
  expect_s3_class(first, "edr_batch")
  expect_identical(
    names(first),
    c("collection_id", "instance_id", "format", "requests", "data", "errors")
  )
  expect_identical(
    names(first$requests),
    c("request_id", "location_id", "datetime", "status", "n_rows")
  )
  expect_identical(
    names(first$errors),
    c(
      "request_id", "location_id", "condition_class", "http_status",
      "message", "condition"
    )
  )
  expect_equal(first$requests$status, c("success", "empty"))
  expect_equal(first$requests$n_rows, c(1L, 0L))
  expect_equal(nrow(first$data), 1L)
  expect_equal(nrow(first$errors), 0L)

  manifest_path <- file.path(checkpoint, "manifest.rds")
  expect_true(file.exists(manifest_path))
  manifest <- readRDS(manifest_path)
  expect_identical(
    names(manifest),
    c(
      "magic", "schema_version", "fingerprint", "created_at",
      "package_version", "endpoint", "collection_id", "instance_id",
      "format", "plan"
    )
  )
  expect_identical(manifest$magic, "edr4r_location_batch_checkpoint")
  expect_identical(manifest$schema_version, 1L)
  expect_type(manifest$fingerprint, "character")
  expect_equal(nchar(manifest$fingerprint), 32L)
  expect_type(manifest$created_at, "character")
  expect_type(manifest$package_version, "character")
  expect_identical(manifest$endpoint, test_client()$base_url)
  expect_identical(manifest$collection_id, "demo")
  expect_null(manifest$instance_id)
  expect_identical(manifest$format, "csv")
  expect_identical(
    names(manifest$plan),
    c("request_id", "location_id", "datetime")
  )
  expect_equal(nrow(manifest$plan), 2L)

  success_record <- readRDS(checkpoint_test_result_path(checkpoint, 1L))
  empty_record <- readRDS(checkpoint_test_result_path(checkpoint, 2L))
  record_names <- c(
    "magic", "schema_version", "fingerprint", "request_id", "status",
    "n_rows", "data"
  )
  expect_identical(names(success_record), record_names)
  expect_identical(names(empty_record), record_names)
  expect_identical(success_record$magic, "edr4r_location_batch_result")
  expect_identical(success_record$schema_version, 1L)
  expect_identical(success_record$fingerprint, manifest$fingerprint)
  expect_identical(success_record$request_id, 1L)
  expect_identical(success_record$status, "success")
  expect_identical(success_record$n_rows, 1L)
  expect_s3_class(success_record$data, "tbl_df")
  expect_false(any(c(".request_id", ".location_id") %in% names(success_record$data)))
  expect_identical(empty_record$request_id, 2L)
  expect_identical(empty_record$status, "empty")
  expect_identical(empty_record$n_rows, 0L)
  expect_s3_class(empty_record$data, "tbl_df")
  expect_equal(nrow(empty_record$data), 0L)
  checkpoint_test_expect_unlocked(checkpoint)

  resumed_calls <- 0L
  httr2::local_mocked_responses(function(req) {
    resumed_calls <<- resumed_calls + 1L
    cli::cli_abort("A complete checkpoint must not issue HTTP requests.")
  })
  resumed <- edr_location_batch(
    edr_client("http://test", max_tries = 3), "demo", "station",
    datetime = "2024-01-01/2024-01-03",
    format = "csv",
    chunk = "1 days",
    deduplicate = FALSE,
    max_requests = 10L,
    on_error = "stop",
    progress = FALSE,
    checkpoint = checkpoint,
    resume = TRUE
  )

  expect_equal(resumed_calls, 0L)
  expect_equal(resumed$requests, first$requests)
  expect_equal(resumed$data, first$data)
  expect_equal(nrow(resumed$errors), 0L)
  checkpoint_test_expect_unlocked(checkpoint)
})

test_that("CoverageJSON terminal data and typed empties round-trip through RDS", {
  checkpoint <- tempfile("edr4r-checkpoint-covjson-")
  coverage <- read_fixture("pointseries.covjson")
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    mock_json_response(coverage)
  })

  first <- edr_location_batch(
    test_client(), "demo", "with-data",
    max_requests = 1L,
    progress = FALSE,
    checkpoint = checkpoint
  )
  expect_equal(calls, 1L)
  expect_equal(first$requests$status, "success")
  expect_s3_class(first$data$datetime, "POSIXct")

  resumed_calls <- 0L
  httr2::local_mocked_responses(function(req) {
    resumed_calls <<- resumed_calls + 1L
    cli::cli_abort("Terminal CoverageJSON results must not be fetched again.")
  })
  resumed <- edr_location_batch(
    test_client(), "demo", "with-data",
    max_requests = 1L,
    progress = FALSE,
    checkpoint = checkpoint,
    resume = TRUE
  )

  expect_equal(resumed_calls, 0L)
  expect_equal(resumed$requests, first$requests)
  expect_equal(resumed$data, first$data)
  expect_equal(resumed$errors, first$errors)
  checkpoint_test_expect_unlocked(checkpoint)

  empty_checkpoint <- tempfile("edr4r-checkpoint-empty-covjson-")
  httr2::local_mocked_responses(function(req) mock_empty_response())
  empty <- edr_location_batch(
    test_client(), "demo", "without-data",
    progress = FALSE,
    checkpoint = empty_checkpoint
  )
  expect_equal(empty$requests$status, "empty")
  expect_equal(empty$requests$n_rows, 0L)

  empty_resume_calls <- 0L
  httr2::local_mocked_responses(function(req) {
    empty_resume_calls <<- empty_resume_calls + 1L
    cli::cli_abort("A typed empty result must be terminal.")
  })
  empty_resumed <- edr_location_batch(
    test_client(), "demo", "without-data",
    progress = FALSE,
    checkpoint = empty_checkpoint,
    resume = TRUE
  )
  expect_equal(empty_resume_calls, 0L)
  expect_equal(empty_resumed$requests, empty$requests)
  expect_equal(empty_resumed$data, empty$data)
  checkpoint_test_expect_unlocked(empty_checkpoint)
})

test_that("stop interruption resumes only unresolved requests", {
  checkpoint <- tempfile("edr4r-checkpoint-stop-")
  initial_calls <- 0L
  httr2::local_mocked_responses(function(req) {
    initial_calls <<- initial_calls + 1L
    if (initial_calls == 1L) {
      mock_text_response(
        "datetime,value\n2024-01-01,1\n",
        content_type = "text/csv"
      )
    } else {
      mock_json_response(
        list(description = "interrupted window"),
        status = 503L
      )
    }
  })

  expect_error(
    edr_location_batch(
      test_client(), "demo", "station",
      datetime = "2024-01-01/2024-01-04",
      format = "csv",
      chunk = "1 day",
      max_requests = 3L,
      progress = FALSE,
      checkpoint = checkpoint
    ),
    "interrupted window",
    class = "httr2_http_503"
  )
  expect_equal(initial_calls, 2L)
  expect_true(file.exists(checkpoint_test_result_path(checkpoint, 1L)))
  expect_false(file.exists(checkpoint_test_result_path(checkpoint, 2L)))
  expect_false(file.exists(checkpoint_test_result_path(checkpoint, 3L)))
  checkpoint_test_expect_unlocked(checkpoint)

  resumed_calls <- 0L
  resumed_urls <- character()
  httr2::local_mocked_responses(function(req) {
    resumed_calls <<- resumed_calls + 1L
    resumed_urls <<- c(resumed_urls, utils::URLdecode(req$url))
    mock_text_response(
      paste0(
        "datetime,value\n",
        sprintf("2024-01-%02d,%d\n", resumed_calls + 1L, resumed_calls + 1L)
      ),
      content_type = "text/csv"
    )
  })

  result <- edr_location_batch(
    test_client(), "demo", "station",
    datetime = "2024-01-01/2024-01-04",
    format = "csv",
    chunk = "1 day",
    max_requests = 3L,
    progress = FALSE,
    checkpoint = checkpoint,
    resume = TRUE
  )

  expect_equal(resumed_calls, 2L)
  expected_windows <- c(
    "datetime=2024-01-02/2024-01-03",
    "datetime=2024-01-03/2024-01-04"
  )
  expect_true(all(vapply(
    seq_along(expected_windows),
    function(i) grepl(expected_windows[[i]], resumed_urls[[i]], fixed = TRUE),
    logical(1)
  )))
  expect_false(any(grepl(
    "datetime=2024-01-01/2024-01-02",
    resumed_urls,
    fixed = TRUE
  )))
  expect_equal(result$requests$request_id, 1:3)
  expect_equal(result$requests$status, rep("success", 3L))
  expect_equal(result$requests$n_rows, rep(1L, 3L))
  expect_equal(result$data$.request_id, 1:3)
  expect_equal(nrow(result$errors), 0L)
  checkpoint_test_expect_unlocked(checkpoint)
})

test_that("collected failures remain unresolved and are retried", {
  checkpoint <- tempfile("edr4r-checkpoint-collect-")
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    if (calls == 1L) {
      mock_json_response(list(description = "temporary"), status = 503L)
    } else {
      mock_text_response(
        "datetime,value\n2024-01-02,2\n",
        content_type = "text/csv"
      )
    }
  })

  first <- edr_location_batch(
    test_client(), "demo", "station",
    datetime = "2024-01-01/2024-01-03",
    format = "csv",
    chunk = "1 day",
    max_requests = 2L,
    on_error = "collect",
    progress = FALSE,
    checkpoint = checkpoint
  )

  expect_equal(calls, 2L)
  expect_equal(first$requests$status, c("error", "success"))
  expect_equal(first$errors$request_id, 1L)
  expect_false(file.exists(checkpoint_test_result_path(checkpoint, 1L)))
  expect_true(file.exists(checkpoint_test_result_path(checkpoint, 2L)))

  retry_calls <- 0L
  httr2::local_mocked_responses(function(req) {
    retry_calls <<- retry_calls + 1L
    mock_text_response(
      "datetime,value\n2024-01-01,1\n",
      content_type = "text/csv"
    )
  })
  recovered <- edr_location_batch(
    test_client(), "demo", "station",
    datetime = "2024-01-01/2024-01-03",
    format = "csv",
    chunk = "1 day",
    max_requests = 2L,
    on_error = "collect",
    progress = FALSE,
    checkpoint = checkpoint,
    resume = TRUE
  )

  expect_equal(retry_calls, 1L)
  expect_equal(recovered$requests$status, c("success", "success"))
  expect_equal(recovered$data$.request_id, 1:2)
  expect_equal(nrow(recovered$errors), 0L)
  checkpoint_test_expect_unlocked(checkpoint)

  persistent <- tempfile("edr4r-checkpoint-persistent-")
  for (iteration in 1:3) {
    invocation_calls <- 0L
    httr2::local_mocked_responses(function(req) {
      invocation_calls <<- invocation_calls + 1L
      mock_json_response(list(description = "still unavailable"), status = 503L)
    })
    failed <- edr_location_batch(
      test_client(), "demo", "station",
      datetime = "2024-01-01/2024-01-02",
      format = "csv",
      chunk = "1 day",
      max_requests = 1L,
      on_error = "collect",
      progress = FALSE,
      checkpoint = persistent,
      resume = iteration > 1L
    )
    expect_equal(invocation_calls, 1L)
    expect_equal(failed$requests$status, "error")
    expect_equal(nrow(failed$errors), 1L)
    expect_false(file.exists(checkpoint_test_result_path(persistent, 1L)))
    checkpoint_test_expect_unlocked(persistent)
  }
})

test_that("deduplication combines restored and live raw pieces deterministically", {
  checkpoint <- tempfile("edr4r-checkpoint-dedup-")
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    if (calls == 1L) {
      mock_text_response(
        paste0(
          "parameter,datetime,value\n",
          "flow,2024-01-01,1\n",
          "flow,2024-01-02,2\n"
        ),
        content_type = "text/csv"
      )
    } else {
      mock_json_response(list(description = "stop after first"), status = 503L)
    }
  })
  expect_error(
    edr_location_batch(
      test_client(), "demo", "station",
      datetime = "2024-01-01/2024-01-03",
      format = "csv",
      chunk = "1 day",
      max_requests = 2L,
      progress = FALSE,
      checkpoint = checkpoint
    ),
    "stop after first"
  )

  resumed_calls <- 0L
  httr2::local_mocked_responses(function(req) {
    resumed_calls <<- resumed_calls + 1L
    mock_text_response(
      paste0(
        "parameter,datetime,value\n",
        "flow,2024-01-02,2\n",
        "flow,2024-01-03,3\n"
      ),
      content_type = "text/csv"
    )
  })
  resumed <- edr_location_batch(
    test_client(), "demo", "station",
    datetime = "2024-01-01/2024-01-03",
    format = "csv",
    chunk = "1 day",
    max_requests = 2L,
    progress = FALSE,
    checkpoint = checkpoint,
    resume = TRUE
  )
  expect_equal(resumed_calls, 1L)

  clean_calls <- 0L
  clean_responses <- c(
    paste0(
      "parameter,datetime,value\n",
      "flow,2024-01-01,1\n",
      "flow,2024-01-02,2\n"
    ),
    paste0(
      "parameter,datetime,value\n",
      "flow,2024-01-02,2\n",
      "flow,2024-01-03,3\n"
    )
  )
  httr2::local_mocked_responses(function(req) {
    clean_calls <<- clean_calls + 1L
    mock_text_response(clean_responses[[clean_calls]], content_type = "text/csv")
  })
  clean <- edr_location_batch(
    test_client(), "demo", "station",
    datetime = "2024-01-01/2024-01-03",
    format = "csv",
    chunk = "1 day",
    max_requests = 2L,
    progress = FALSE
  )

  expect_equal(resumed$requests, clean$requests)
  expect_equal(resumed$data, clean$data)
  expect_equal(resumed$errors, clean$errors)
  expect_equal(nrow(resumed$data), 3L)
  expect_equal(
    resumed$data$.request_id[resumed$data$datetime == "2024-01-02"],
    1L
  )

  raw_calls <- 0L
  httr2::local_mocked_responses(function(req) {
    raw_calls <<- raw_calls + 1L
    cli::cli_abort("Changing deduplicate must not refetch terminal rows.")
  })
  raw <- edr_location_batch(
    test_client(), "demo", "station",
    datetime = "2024-01-01/2024-01-03",
    format = "csv",
    chunk = "1 day",
    deduplicate = FALSE,
    max_requests = 2L,
    progress = FALSE,
    checkpoint = checkpoint,
    resume = TRUE
  )
  expect_equal(raw_calls, 0L)
  expect_equal(nrow(raw$data), 4L)
  expect_equal(
    raw$data$.request_id[raw$data$datetime == "2024-01-02"],
    c(1L, 2L)
  )
  checkpoint_test_expect_unlocked(checkpoint)
})

test_that("fingerprints reject request identity changes before network", {
  checkpoint <- tempfile("edr4r-checkpoint-fingerprint-")
  seed_args <- list(
    client = test_client(),
    collection_id = "demo",
    location_id = c("a", "b"),
    datetime = "2024-01-01/2024-01-03",
    parameter_name = "flow",
    z = "surface",
    crs = "CRS84",
    format = "csv",
    limit = 10L,
    chunk = "1 day",
    max_requests = 4L,
    on_error = "collect",
    progress = FALSE,
    instance_id = "run-a",
    checkpoint = checkpoint
  )
  seed_calls <- 0L
  httr2::local_mocked_responses(function(req) {
    seed_calls <<- seed_calls + 1L
    mock_text_response(
      paste0("datetime,value\n2024-01-01,", seed_calls, "\n"),
      content_type = "text/csv"
    )
  })
  do.call(edr_location_batch, seed_args)
  expect_equal(seed_calls, 4L)

  allowed_args <- checkpoint_test_override(seed_args, list(
    client = edr_client(
      "http://test",
      max_tries = 3,
      headers = c(Authorization = "Bearer rotated-token")
    ),
    chunk = " 1 DAYS ",
    deduplicate = FALSE,
    max_requests = 10L,
    on_error = "stop",
    progress = FALSE,
    resume = TRUE
  ))
  allowed_calls <- 0L
  httr2::local_mocked_responses(function(req) {
    allowed_calls <<- allowed_calls + 1L
    cli::cli_abort("Output and transport options must not invalidate a checkpoint.")
  })
  allowed <- do.call(edr_location_batch, allowed_args)
  expect_equal(allowed_calls, 0L)
  expect_equal(allowed$requests$status, rep("success", 4L))
  checkpoint_test_expect_unlocked(checkpoint)

  mismatch_cases <- list(
    endpoint = list(client = edr_client("http://other", max_tries = 1)),
    collection = list(collection_id = "other"),
    instance = list(instance_id = "run-b"),
    location_order = list(location_id = c("b", "a")),
    windows = list(
      datetime = "2024-01-01/2024-01-04",
      max_requests = 6L
    ),
    parameter = list(parameter_name = "temperature"),
    z = list(z = "10"),
    crs = list(crs = "EPSG:4326"),
    format = list(format = "covjson"),
    dots = list(limit = 11L)
  )

  mismatch_calls <- 0L
  httr2::local_mocked_responses(function(req) {
    mismatch_calls <<- mismatch_calls + 1L
    cli::cli_abort("Fingerprint mismatches must be detected before HTTP.")
  })
  for (case in mismatch_cases) {
    case_checkpoint <- checkpoint_test_copy(checkpoint)
    args <- checkpoint_test_override(seed_args, case)
    args$checkpoint <- case_checkpoint
    args$resume <- TRUE
    expect_error(
      do.call(edr_location_batch, args),
      "checkpoint|fingerprint|match|different"
    )
    checkpoint_test_expect_unlocked(case_checkpoint)
  }
  expect_equal(mismatch_calls, 0L)
})

test_that("expanded caps are enforced before checkpoint access", {
  missing <- tempfile("edr4r-checkpoint-cap-")
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    cli::cli_abort("Request cap validation must happen before HTTP.")
  })

  expect_error(
    edr_location_batch(
      test_client(), "demo", c("a", "b"),
      datetime = "2024-01-01/2024-01-03",
      format = "csv",
      chunk = "1 day",
      max_requests = 3L,
      progress = FALSE,
      checkpoint = missing,
      resume = TRUE
    ),
    "exceeding.*max_requests"
  )
  expect_equal(calls, 0L)
  expect_false(dir.exists(missing))

  existing <- tempfile("edr4r-checkpoint-cap-existing-")
  checkpoint_test_seed(existing, list(
    location_id = c("a", "b"),
    max_requests = 4L
  ))
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    cli::cli_abort("Restored rows do not reduce the logical request cap.")
  })
  expect_error(
    edr_location_batch(
      test_client(), "demo", c("a", "b"),
      datetime = "2024-01-01/2024-01-03",
      format = "csv",
      chunk = "1 day",
      max_requests = 3L,
      progress = FALSE,
      checkpoint = existing,
      resume = TRUE
    ),
    "exceeding.*max_requests"
  )
  expect_equal(calls, 0L)
  checkpoint_test_expect_unlocked(existing)
})

test_that("checkpoint path and resume validation precede network activity", {
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    cli::cli_abort("Invalid checkpoint state must not issue HTTP.")
  })

  expect_error(
    edr_location_batch(
      test_client(), "demo", "station",
      format = "csv", progress = FALSE,
      resume = TRUE
    ),
    "checkpoint|resume"
  )
  expect_error(
    edr_location_batch(
      test_client(), "demo", "station",
      format = "csv", progress = FALSE,
      checkpoint = NA_character_
    ),
    "checkpoint.*directory path"
  )
  expect_error(
    edr_location_batch(
      test_client(), "demo", "station",
      format = "csv", progress = FALSE,
      checkpoint = tempfile("edr4r-checkpoint-invalid-resume-"),
      resume = NA
    ),
    "resume.*TRUE.*FALSE"
  )

  embedded <- tempfile("edr4r-checkpoint-embedded-credentials-")
  expect_error(
    edr_location_batch(
      edr_client("http://user:password@test", max_tries = 1),
      "demo", "station",
      format = "csv", progress = FALSE,
      checkpoint = embedded,
      resume = TRUE
    ),
    "embedded credentials"
  )
  expect_false(dir.exists(embedded))

  queried <- tempfile("edr4r-checkpoint-base-query-")
  expect_error(
    edr_location_batch(
      edr_client("http://test?token=secret", max_tries = 1),
      "demo", "station",
      format = "csv", progress = FALSE,
      checkpoint = queried,
      resume = TRUE
    ),
    "query string or fragment"
  )
  expect_false(dir.exists(queried))

  ordinary_file <- tempfile("edr4r-checkpoint-file-")
  writeLines("not a directory", ordinary_file)
  expect_error(
    edr_location_batch(
      test_client(), "demo", "station",
      format = "csv", progress = FALSE,
      checkpoint = ordinary_file,
      resume = TRUE
    ),
    "checkpoint|directory|file"
  )

  nonempty <- tempfile("edr4r-checkpoint-nonempty-")
  dir.create(nonempty)
  writeLines("keep", file.path(nonempty, "unrelated.txt"))
  expect_error(
    edr_location_batch(
      test_client(), "demo", "station",
      format = "csv", progress = FALSE,
      checkpoint = nonempty,
      resume = TRUE
    ),
    "checkpoint|manifest|non-empty|nonempty"
  )

  existing <- tempfile("edr4r-checkpoint-existing-")
  checkpoint_test_seed(existing, list(
    datetime = "2024-01-01/2024-01-02",
    max_requests = 1L
  ))
  expect_error(
    edr_location_batch(
      test_client(), "demo", "station",
      datetime = "2024-01-01/2024-01-02",
      format = "csv",
      chunk = "1 day",
      max_requests = 1L,
      progress = FALSE,
      checkpoint = existing,
      resume = FALSE
    ),
    "resume|already|existing|checkpoint"
  )
  expect_equal(calls, 0L)
  checkpoint_test_expect_unlocked(existing)

  missing <- tempfile("edr4r-checkpoint-missing-")
  init_calls <- 0L
  httr2::local_mocked_responses(function(req) {
    init_calls <<- init_calls + 1L
    mock_text_response("value\n1\n", content_type = "text/csv")
  })
  initialized <- edr_location_batch(
    test_client(), "demo", "station",
    format = "csv",
    progress = FALSE,
    checkpoint = missing,
    resume = TRUE
  )
  expect_equal(init_calls, 1L)
  expect_equal(initialized$requests$status, "success")
  expect_true(file.exists(file.path(missing, "manifest.rds")))
  checkpoint_test_expect_unlocked(missing)
})

test_that("checkpoint files omit request URLs, headers, and conditions", {
  checkpoint <- tempfile("edr4r-checkpoint-secrets-")
  client <- edr_client(
    "http://test",
    max_tries = 1,
    headers = c(Authorization = "Bearer header-secret")
  )
  httr2::local_mocked_responses(function(req) {
    mock_text_response("value\n1\n", content_type = "text/csv")
  })

  edr_location_batch(
    client, "demo", "station",
    format = "csv",
    api_key = "query-secret",
    progress = FALSE,
    checkpoint = checkpoint
  )

  stored <- list(
    manifest = readRDS(file.path(checkpoint, "manifest.rds")),
    result = readRDS(checkpoint_test_result_path(checkpoint, 1L))
  )
  rendered <- paste(capture.output(str(stored)), collapse = "\n")
  expect_false(grepl("header-secret", rendered, fixed = TRUE))
  expect_false(grepl("query-secret", rendered, fixed = TRUE))
  expect_false(grepl("Authorization", rendered, fixed = TRUE))
  expect_false(grepl("api_key", rendered, fixed = TRUE))
  expect_false(any(vapply(stored, inherits, logical(1), what = "condition")))
  checkpoint_test_expect_unlocked(checkpoint)
})

test_that("lock collisions abort and owned locks are always released", {
  locked <- tempfile("edr4r-checkpoint-locked-")
  dir.create(locked)
  dir.create(file.path(locked, ".edr4r-lock"))
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    cli::cli_abort("A lock collision must abort before HTTP.")
  })
  expect_error(
    edr_location_batch(
      test_client(), "demo", "station",
      format = "csv",
      progress = FALSE,
      checkpoint = locked,
      resume = TRUE
    ),
    "lock|stale|active"
  )
  expect_equal(calls, 0L)
  expect_true(dir.exists(file.path(locked, ".edr4r-lock")))

  parser_failure <- tempfile("edr4r-checkpoint-parser-")
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
  httr2::local_mocked_responses(function(req) mock_json_response(malformed))
  expect_error(
    edr_location_batch(
      test_client(), "demo", "station",
      progress = FALSE,
      checkpoint = parser_failure
    ),
    "CoverageJSON|domain|inline"
  )
  expect_true(file.exists(file.path(parser_failure, "manifest.rds")))
  expect_false(file.exists(checkpoint_test_result_path(parser_failure, 1L)))
  checkpoint_test_expect_unlocked(parser_failure)
})

test_that("terminal write failures release the lock and leave work retryable", {
  checkpoint <- tempfile("edr4r-checkpoint-write-failure-")
  save_calls <- 0L
  request_calls <- 0L
  original_atomic_save <- edr4r:::batch_checkpoint_atomic_save

  local({
    testthat::local_mocked_bindings(
      batch_checkpoint_atomic_save = function(...) {
        save_calls <<- save_calls + 1L
        if (save_calls == 1L) return(original_atomic_save(...))
        cli::cli_abort("simulated terminal checkpoint write failure")
      },
      .package = "edr4r"
    )
    httr2::local_mocked_responses(function(req) {
      request_calls <<- request_calls + 1L
      mock_text_response("value\n1\n", content_type = "text/csv")
    })

    expect_error(
      edr_location_batch(
        test_client(), "demo", "station",
        format = "csv",
        progress = FALSE,
        checkpoint = checkpoint
      ),
      "simulated terminal checkpoint write failure"
    )
  })

  expect_equal(save_calls, 2L)
  expect_equal(request_calls, 1L)
  expect_true(file.exists(file.path(checkpoint, "manifest.rds")))
  expect_false(file.exists(checkpoint_test_result_path(checkpoint, 1L)))
  checkpoint_test_expect_unlocked(checkpoint)

  retry_calls <- 0L
  httr2::local_mocked_responses(function(req) {
    retry_calls <<- retry_calls + 1L
    mock_text_response("value\n1\n", content_type = "text/csv")
  })
  result <- edr_location_batch(
    test_client(), "demo", "station",
    format = "csv",
    progress = FALSE,
    checkpoint = checkpoint,
    resume = TRUE
  )
  expect_equal(retry_calls, 1L)
  expect_equal(result$requests$status, "success")
  expect_true(file.exists(checkpoint_test_result_path(checkpoint, 1L)))
  checkpoint_test_expect_unlocked(checkpoint)
})

test_that("corrupt and malformed manifests abort before network", {
  seed <- tempfile("edr4r-checkpoint-manifest-seed-")
  checkpoint_test_seed(seed, list(
    datetime = "2024-01-01/2024-01-02",
    max_requests = 1L
  ))

  corrupt <- checkpoint_test_copy(seed)
  writeBin(charToRaw("not an rds file"), file.path(corrupt, "manifest.rds"))

  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    cli::cli_abort("Corrupt manifests must abort before HTTP.")
  })
  condition <- expect_error(
    edr_location_batch(
      test_client(), "demo", "station",
      datetime = "2024-01-01/2024-01-02",
      format = "csv",
      chunk = "1 day",
      max_requests = 1L,
      progress = FALSE,
      checkpoint = corrupt,
      resume = TRUE
    ),
    "manifest|checkpoint|corrupt|read"
  )
  expect_match(conditionMessage(condition), "manifest.rds|manifest")
  checkpoint_test_expect_unlocked(corrupt)

  malformed_cases <- list(
    missing_magic = function(x) { x$magic <- NULL; x },
    wrong_magic = function(x) { x$magic <- "other"; x },
    wrong_schema = function(x) { x$schema_version <- 2L; x },
    bad_fingerprint = function(x) { x$fingerprint <- "short"; x },
    missing_endpoint = function(x) { x$endpoint <- NULL; x },
    malformed_plan = function(x) { x$plan$datetime <- NULL; x },
    extra_field = function(x) { x$extra <- TRUE; x }
  )

  for (mutate_manifest in malformed_cases) {
    checkpoint <- checkpoint_test_copy(seed)
    path <- file.path(checkpoint, "manifest.rds")
    saveRDS(mutate_manifest(readRDS(path)), path)
    expect_error(
      edr_location_batch(
        test_client(), "demo", "station",
        datetime = "2024-01-01/2024-01-02",
        format = "csv",
        chunk = "1 day",
        max_requests = 1L,
        progress = FALSE,
        checkpoint = checkpoint,
        resume = TRUE
      ),
      "manifest|checkpoint|schema|fingerprint|plan"
    )
    checkpoint_test_expect_unlocked(checkpoint)
  }
  expect_equal(calls, 0L)
})

test_that("corrupt and inconsistent terminal records abort before network", {
  seed <- tempfile("edr4r-checkpoint-result-seed-")
  checkpoint_test_seed(seed, list(
    datetime = "2024-01-01/2024-01-02",
    max_requests = 1L
  ))

  corrupt <- checkpoint_test_copy(seed)
  corrupt_path <- checkpoint_test_result_path(corrupt, 1L)
  writeBin(charToRaw("not an rds file"), corrupt_path)

  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    cli::cli_abort("Corrupt terminal records must abort before HTTP.")
  })
  condition <- expect_error(
    edr_location_batch(
      test_client(), "demo", "station",
      datetime = "2024-01-01/2024-01-02",
      format = "csv",
      chunk = "1 day",
      max_requests = 1L,
      progress = FALSE,
      checkpoint = corrupt,
      resume = TRUE
    ),
    "result|checkpoint|corrupt|read"
  )
  expect_match(conditionMessage(condition), "0000000001.rds|result")
  checkpoint_test_expect_unlocked(corrupt)

  malformed_cases <- list(
    missing_magic = function(x) { x$magic <- NULL; x },
    wrong_magic = function(x) { x$magic <- "other"; x },
    wrong_schema = function(x) { x$schema_version <- 2L; x },
    wrong_fingerprint = function(x) {
      x$fingerprint <- paste(rep("0", 32L), collapse = "")
      x
    },
    wrong_request = function(x) { x$request_id <- 2L; x },
    invalid_status = function(x) { x$status <- "error"; x },
    wrong_n_rows = function(x) { x$n_rows <- x$n_rows + 1L; x },
    non_data_frame = function(x) { x$data <- list(value = 1); x },
    reserved_column = function(x) {
      x$data$.request_id <- rep(1L, nrow(x$data))
      x
    },
    empty_with_rows = function(x) { x$status <- "empty"; x },
    success_without_rows = function(x) {
      x$data <- x$data[0, , drop = FALSE]
      x$n_rows <- 0L
      x
    },
    extra_field = function(x) { x$extra <- TRUE; x }
  )

  for (mutate_record in malformed_cases) {
    checkpoint <- checkpoint_test_copy(seed)
    path <- checkpoint_test_result_path(checkpoint, 1L)
    saveRDS(mutate_record(readRDS(path)), path)
    expect_error(
      edr_location_batch(
        test_client(), "demo", "station",
        datetime = "2024-01-01/2024-01-02",
        format = "csv",
        chunk = "1 day",
        max_requests = 1L,
        progress = FALSE,
        checkpoint = checkpoint,
        resume = TRUE
      ),
      "result|checkpoint|schema|fingerprint|request|status|rows|data|reserved"
    )
    checkpoint_test_expect_unlocked(checkpoint)
  }
  expect_equal(calls, 0L)
})
