test_that("edr_client constructs and validates", {
  cl <- edr_client("http://localhost:5005/")
  expect_s3_class(cl, "edr_client")
  expect_equal(cl$base_url, "http://localhost:5005") # trailing slash trimmed
  expect_match(cl$user_agent, "^edr4r/")
  expect_equal(cl$max_tries, 3)
  expect_true(cl$retry_on_failure)
  expect_equal(cl$cache_ttl, 300)
  expect_true(is.environment(cl$cache))

  expect_error(edr_client(123), "single non-NA string")
  expect_error(edr_client(c("a", "b")), "single non-NA string")
  expect_error(edr_client(""), "must not be empty")
  expect_error(edr_client("/"), "must not be empty")
  expect_error(edr_client("   "), "must not be empty")
  expect_error(edr_client("http://test", timeout = 0), "positive number")
  expect_error(edr_client("http://test", max_tries = 1.5), "positive integer")
  expect_error(edr_client("http://test", max_tries = 1e20), "positive integer")
  expect_error(edr_client("http://test", retry_on_failure = NA), "TRUE.*FALSE")
})

test_that("cache_ttl is validated and printed clearly", {
  expect_error(edr_client("http://test", cache_ttl = -1), "non-negative")
  expect_error(edr_client("http://test", cache_ttl = -Inf), "non-negative")
  expect_error(edr_client("http://test", cache_ttl = NA_real_), "non-negative")
  expect_error(edr_client("http://test", cache_ttl = NaN), "non-negative")
  expect_error(edr_client("http://test", cache_ttl = c(1, 2)), "non-negative")
  expect_error(edr_client("http://test", cache_ttl = "300"), "non-negative")

  expect_match(
    paste(format(edr_client("http://test", cache_ttl = 15)), collapse = "\n"),
    "15s"
  )
  expect_match(
    paste(format(edr_client("http://test", cache_ttl = 0)), collapse = "\n"),
    "disabled"
  )
  expect_match(
    paste(format(edr_client("http://test", cache_ttl = Inf)), collapse = "\n"),
    "until cleared"
  )
})

test_that("user agent, headers, and verbose options are validated", {
  cl <- edr_client(
    "http://test",
    user_agent = "my-client/1.0",
    headers = c(Authorization = "Bearer token", `X-Test` = "yes"),
    verbose = TRUE
  )
  expect_equal(cl$user_agent, "my-client/1.0")
  expect_equal(
    cl$headers,
    c(Authorization = "Bearer token", `X-Test` = "yes")
  )
  expect_true(cl$verbose)

  expect_error(edr_client("http://test", user_agent = ""), "user_agent.*non-empty")
  expect_error(edr_client("http://test", user_agent = NA_character_), "user_agent.*non-empty")
  expect_error(edr_client("http://test", user_agent = c("a", "b")), "user_agent.*non-empty")
  expect_error(edr_client("http://test", user_agent = 1), "user_agent.*non-empty")
  expect_error(edr_client("http://test", headers = "value"), "headers.*named character")
  expect_error(
    edr_client("http://test", headers = stats::setNames("value", "")),
    "headers.*non-empty names"
  )
  expect_error(edr_client("http://test", headers = c(A = NA_character_)), "headers.*non-NA values")
  expect_error(edr_client("http://test", headers = list(A = "value")), "headers.*named character")
  expect_error(edr_client("http://test", verbose = NA), "verbose.*TRUE.*FALSE")
  expect_error(edr_client("http://test", verbose = 1), "verbose.*TRUE.*FALSE")
  expect_error(edr_client("http://test", verbose = c(TRUE, FALSE)), "verbose.*TRUE.*FALSE")
})

test_that("print method is stable", {
  cl <- edr_client("http://localhost:5005")
  expect_output(print(cl), "edr_client")
  expect_output(print(cl), "localhost:5005")
  expect_output(print(cl), "discovery cache: 300s")
})

test_that("check_client rejects non-clients", {
  expect_error(edr_request(list(), "x"), "edr_client")
  expect_error(edr_cache_clear(list()), "edr_client")
})

test_that("cached discovery returns a fresh cache hit", {
  cl <- edr_client("http://test", cache_ttl = 300)
  calls <- 0L
  fetch <- function() {
    calls <<- calls + 1L
    list(version = calls)
  }

  first <- cached_discovery(cl, "landing", refresh = FALSE, fetch = fetch)
  second <- cached_discovery(cl, "landing", refresh = FALSE, fetch = fetch)

  expect_equal(first, list(version = 1L))
  expect_equal(second, first)
  expect_equal(calls, 1L)
})

test_that("refresh replaces a cached value", {
  cl <- edr_client("http://test", cache_ttl = 300)
  calls <- 0L
  fetch <- function() {
    calls <<- calls + 1L
    paste0("value-", calls)
  }

  expect_equal(
    cached_discovery(cl, "collection:x", refresh = FALSE, fetch = fetch),
    "value-1"
  )
  expect_equal(
    cached_discovery(cl, "collection:x", refresh = TRUE, fetch = fetch),
    "value-2"
  )
  expect_equal(
    cached_discovery(cl, "collection:x", refresh = FALSE, fetch = fetch),
    "value-2"
  )
  expect_equal(calls, 2L)
})

test_that("zero TTL disables cache reads and writes", {
  cl <- edr_client("http://test", cache_ttl = 0)
  calls <- 0L
  fetch <- function() {
    calls <<- calls + 1L
    calls
  }

  expect_equal(cached_discovery(cl, "landing", FALSE, fetch), 1L)
  expect_equal(cached_discovery(cl, "landing", FALSE, fetch), 2L)
  expect_equal(calls, 2L)
  expect_length(ls(cl$cache, all.names = TRUE), 0L)
})

test_that("infinite TTL retains arbitrarily old finite entries", {
  cl <- edr_client("http://test", cache_ttl = Inf)
  calls <- 0L
  fetch <- function() {
    calls <<- calls + 1L
    paste0("value-", calls)
  }

  expect_equal(cached_discovery(cl, "landing", FALSE, fetch), "value-1")
  entry <- get("landing", envir = cl$cache, inherits = FALSE)
  entry$stored_at <- as.numeric(Sys.time()) - 1e9
  assign("landing", entry, envir = cl$cache)

  expect_equal(cached_discovery(cl, "landing", FALSE, fetch), "value-1")
  expect_equal(calls, 1L)
})

test_that("expired entries are fetched again without sleeping", {
  cl <- edr_client("http://test", cache_ttl = 1)
  calls <- 0L
  fetch <- function() {
    calls <<- calls + 1L
    paste0("value-", calls)
  }

  expect_equal(cached_discovery(cl, "landing", FALSE, fetch), "value-1")
  entry <- get("landing", envir = cl$cache, inherits = FALSE)
  entry$stored_at <- as.numeric(Sys.time()) - 2
  assign("landing", entry, envir = cl$cache)

  expect_equal(cached_discovery(cl, "landing", FALSE, fetch), "value-2")
  expect_equal(calls, 2L)
})

test_that("empty discovery values are cached", {
  cl <- edr_client("http://test")
  list_calls <- 0L
  vector_calls <- 0L

  empty_list <- function() {
    list_calls <<- list_calls + 1L
    list()
  }
  empty_vector <- function() {
    vector_calls <<- vector_calls + 1L
    character()
  }

  expect_length(cached_discovery(cl, "empty-list", FALSE, empty_list), 0L)
  expect_length(cached_discovery(cl, "empty-list", FALSE, empty_list), 0L)
  expect_length(cached_discovery(cl, "empty-vector", FALSE, empty_vector), 0L)
  expect_length(cached_discovery(cl, "empty-vector", FALSE, empty_vector), 0L)
  expect_equal(list_calls, 1L)
  expect_equal(vector_calls, 1L)
})

test_that("fetch errors are not cached", {
  cl <- edr_client("http://test")
  calls <- 0L
  fetch <- function() {
    calls <<- calls + 1L
    if (calls == 1L) stop("temporary failure")
    "recovered"
  }

  expect_error(cached_discovery(cl, "landing", FALSE, fetch), "temporary failure")
  expect_false(exists("landing", envir = cl$cache, inherits = FALSE))
  expect_equal(cached_discovery(cl, "landing", FALSE, fetch), "recovered")
  expect_equal(calls, 2L)
})

test_that("failed forced refresh retains the last good value", {
  cl <- edr_client("http://test")
  calls <- 0L
  fetch <- function() {
    calls <<- calls + 1L
    if (calls == 2L) stop("refresh failed")
    paste0("value-", calls)
  }

  expect_equal(cached_discovery(cl, "landing", FALSE, fetch), "value-1")
  expect_error(cached_discovery(cl, "landing", TRUE, fetch), "refresh failed")
  expect_equal(cached_discovery(cl, "landing", FALSE, fetch), "value-1")
  expect_equal(calls, 2L)
})

test_that("clearing one client cache leaves another isolated", {
  first <- edr_client("http://first.test")
  second <- edr_client("http://second.test")
  cached_discovery(first, "landing", FALSE, function() "first")
  cached_discovery(second, "landing", FALSE, function() "second")

  returned <- edr_cache_clear(first)

  expect_identical(returned, first)
  expect_false(exists("landing", envir = first$cache, inherits = FALSE))
  expect_true(exists("landing", envir = second$cache, inherits = FALSE))
})

test_that("malformed cache entries are ignored and replaced", {
  cl <- edr_client("http://test")
  assign("landing", list(value = "stale"), envir = cl$cache)
  calls <- 0L
  fetch <- function() {
    calls <<- calls + 1L
    "fresh"
  }

  expect_equal(cached_discovery(cl, "landing", FALSE, fetch), "fresh")
  expect_equal(calls, 1L)
  expect_true(valid_cache_entry(get("landing", envir = cl$cache)))
})

test_that("shallow client copies share their backing cache", {
  first <- edr_client("http://test")
  second <- first
  calls <- 0L
  fetch <- function() {
    calls <<- calls + 1L
    "shared"
  }

  expect_equal(cached_discovery(first, "landing", FALSE, fetch), "shared")
  expect_equal(cached_discovery(second, "landing", FALSE, fetch), "shared")
  expect_equal(calls, 1L)

  edr_cache_clear(second)
  expect_false(exists("landing", envir = first$cache, inherits = FALSE))
})

test_that("refresh must be a single non-missing logical", {
  cl <- edr_client("http://test")
  fetch <- function() "unused"

  expect_error(cached_discovery(cl, "x", NA, fetch), "refresh.*TRUE.*FALSE")
  expect_error(cached_discovery(cl, "x", 1, fetch), "refresh.*TRUE.*FALSE")
  expect_error(cached_discovery(cl, "x", NULL, fetch), "refresh.*TRUE.*FALSE")
  expect_error(
    cached_discovery(cl, "x", c(TRUE, FALSE), fetch),
    "refresh.*TRUE.*FALSE"
  )
})
