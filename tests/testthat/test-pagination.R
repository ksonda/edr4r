pagination_response <- function(body, req, status = 200L) {
  mock_json_response(
    body,
    content_type = "application/geo+json",
    status = status,
    url = req$url
  )
}

feature_collection <- function(ids = character(), next_href = NULL) {
  features <- lapply(ids, function(id) {
    list(
      type = "Feature",
      id = id,
      geometry = list(type = "Point", coordinates = list(0, 0)),
      properties = list(name = id)
    )
  })
  links <- if (is.null(next_href)) {
    list()
  } else {
    list(list(rel = "next", href = next_href, type = "application/geo+json"))
  }
  list(type = "FeatureCollection", features = features, links = links)
}

test_that("pagination is opt-in and the default still performs one request", {
  calls <- 0L
  first <- read_fixture("pagination-page-1.geojson")
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    pagination_response(first, req)
  })

  result <- edr_request(
    test_client(),
    "collections/demo/locations",
    query = list(limit = 2),
    format = "geojson"
  )

  expect_equal(calls, 1L)
  expect_s3_class(result, "edr_geojson")
  expect_equal(result$geojson$links[[2]]$rel, "next")
  expect_false("paginate" %in% names(formals(edr_request)))
})

test_that("relative next links are followed opaquely and pages merge in order", {
  first <- read_fixture("pagination-page-1.geojson")
  second <- read_fixture("pagination-page-2.geojson")
  urls <- character()
  httr2::local_mocked_responses(function(req) {
    urls <<- c(urls, req$url)
    body <- if (length(urls) == 1L) first else second
    pagination_response(body, req)
  })

  result <- edr4r:::paginated_feature_collection_request(
    edr_client("https://example.test", max_tries = 1),
    "collections/demo/locations",
    query = list(bbox = "-106,39,-104,41", limit = 2),
    format = "geojson",
    max_pages = 10L,
    max_features = 100L
  )

  expect_equal(length(urls), 2L)
  expect_equal(
    urls[[2]],
    paste0(
      "https://example.test/collections/demo/locations?",
      "cursor=opaque%2Btoken&limit=2&f=json"
    )
  )
  expect_false(grepl("bbox", urls[[2]], fixed = TRUE))
  expect_equal(
    vapply(result$geojson$features, `[[`, character(1), "id"),
    c("station-a", "station-b", "station-c")
  )
  expect_equal(result$geojson$numberReturned, 3L)
  expect_equal(result$geojson$numberMatched, 3L)
  expect_equal(unlist(result$geojson$bbox), c(-106, 39, -104, 41))
  expect_false(any(vapply(
    result$geojson$links,
    function(link) link$rel %in% c("next", "prev", "first", "last"),
    logical(1)
  )))
  expect_equal(
    attr(result, "edr_pagination"),
    list(pages = 2L, features = 3L, complete = TRUE)
  )
})

test_that("absolute next URLs preserve opaque plus and percent encodings", {
  next_url <- paste0(
    "https://example.test/collections/demo/locations?",
    "cursor=A+B&literal=A%2BB&space=A%20B"
  )
  first <- feature_collection("a", next_url)
  second <- feature_collection("b")
  urls <- character()
  httr2::local_mocked_responses(function(req) {
    urls <<- c(urls, req$url)
    pagination_response(if (length(urls) == 1L) first else second, req)
  })

  result <- edr_locations(
    edr_client("https://example.test", max_tries = 1),
    "demo",
    paginate = TRUE,
    max_pages = 2L,
    max_features = 10L
  )

  expect_equal(urls[[2]], next_url)
  expect_equal(attr(result, "edr_pagination")$features, 2L)
})

test_that("relative URL forms resolve without rewriting their raw query", {
  base <- "https://example.test/a/b/locations?old=A+B"
  origin <- "https://example.test:443"

  expect_equal(
    edr4r:::resolve_pagination_url(
      "?cursor=A+B&literal=A%2BB", base, origin, 1L
    ),
    "https://example.test/a/b/locations?cursor=A+B&literal=A%2BB"
  )
  expect_equal(
    edr4r:::resolve_pagination_url(
      "../items?cursor=A+B", base, origin, 1L
    ),
    "https://example.test/a/items?cursor=A+B"
  )
  expect_equal(
    edr4r:::resolve_pagination_url(
      "../a%2Fb+c?cursor=A+B", base, origin, 1L
    ),
    "https://example.test/a/a%2Fb+c?cursor=A+B"
  )
  expect_equal(
    edr4r:::resolve_pagination_url(
      "/root?cursor=A+B", base, origin, 1L
    ),
    "https://example.test/root?cursor=A+B"
  )
  expect_equal(
    edr4r:::resolve_pagination_url(
      "//example.test/root?cursor=A+B", base, origin, 1L
    ),
    "https://example.test/root?cursor=A+B"
  )
})

test_that("public location and item pagination is keyword-only", {
  for (verb in list(edr_locations, edr_items)) {
    formal_names <- names(formals(verb))
    expect_gt(match("paginate", formal_names), match("...", formal_names))
    expect_gt(match("max_pages", formal_names), match("...", formal_names))
    expect_gt(match("max_features", formal_names), match("...", formal_names))
  }
})

test_that("high-level pagination promotes once and retains metadata", {
  skip_if_not_installed("sf")
  first <- read_fixture("pagination-page-1.geojson")
  second <- read_fixture("pagination-page-2.geojson")
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    pagination_response(if (calls == 1L) first else second, req)
  })

  result <- edr_items(
    edr_client("https://example.test", max_tries = 1),
    "demo",
    paginate = TRUE,
    max_pages = 2L,
    max_features = 10L
  )

  expect_s3_class(result, "sf")
  expect_equal(nrow(result), 3L)
  expect_true(all(c("network", "elevation") %in% names(result)))
  expect_equal(
    attr(result, "edr_pagination"),
    list(pages = 2L, features = 3L, complete = TRUE)
  )
})

test_that("page and feature caps fail with typed errors before returning partial data", {
  first <- read_fixture("pagination-page-1.geojson")
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    pagination_response(first, req)
  })

  expect_error(
    edr_locations(
      edr_client("https://example.test", max_tries = 1), "demo",
      paginate = TRUE, max_pages = 1L, max_features = 100L
    ),
    class = "edr_pagination_max_pages"
  )
  expect_equal(calls, 1L)

  calls <- 0L
  expect_error(
    edr_locations(
      edr_client("https://example.test", max_tries = 1), "demo",
      paginate = TRUE, max_pages = 10L, max_features = 1L
    ),
    class = "edr_pagination_max_features"
  )
  expect_equal(calls, 1L)
})

test_that("pagination controls are validated before an HTTP request", {
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    pagination_response(feature_collection(), req)
  })
  client <- edr_client("https://example.test", max_tries = 1)

  for (bad in list(0, -1, 1.5, NA_real_, Inf, .Machine$integer.max + 1)) {
    expect_error(
      edr_locations(client, "demo", max_pages = bad),
      "finite positive integer"
    )
    expect_error(
      edr_items(client, "demo", max_features = bad),
      "finite positive integer"
    )
  }
  expect_error(edr_locations(client, "demo", paginate = NA), "TRUE.*FALSE")
  expect_equal(calls, 0L)
})

test_that("cross-origin, downgrade, credential, and non-HTTP links are rejected", {
  cases <- list(
    list("https://other.test/page", "edr_pagination_origin"),
    list("http://example.test/page", "edr_pagination_origin"),
    list("https://user:secret@example.test/page", "edr_pagination_origin"),
    list("ftp://example.test/page", "edr_pagination_link")
  )

  for (case in cases) {
    calls <- 0L
    first <- feature_collection("a", case[[1]])
    httr2::local_mocked_responses(function(req) {
      calls <<- calls + 1L
      pagination_response(first, req)
    })
    expect_error(
      edr_locations(
        edr_client("https://example.test", max_tries = 1), "demo",
        paginate = TRUE
      ),
      class = case[[2]],
      info = case[[1]]
    )
    expect_equal(calls, 1L, info = case[[1]])
  }
})

test_that("a cross-origin redirect response is not a new trusted pagination origin", {
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    mock_json_response(
      feature_collection(),
      content_type = "application/geo+json",
      url = "https://redirected.test/collections/demo/locations?f=json"
    )
  })

  expect_error(
    edr_locations(
      edr_client(
        "https://example.test", max_tries = 1,
        headers = c(Authorization = "Bearer secret")
      ),
      "demo",
      paginate = TRUE
    ),
    class = "edr_pagination_origin"
  )
  expect_equal(calls, 1L)
})

test_that("self and two-page cycles stop before refetching a visited URL", {
  calls <- 0L
  self <- feature_collection("a", "?f=json")
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    pagination_response(self, req)
  })
  expect_error(
    edr_locations(
      edr_client("https://example.test", max_tries = 1), "demo",
      paginate = TRUE
    ),
    class = "edr_pagination_cycle"
  )
  expect_equal(calls, 1L)

  calls <- 0L
  first_url <- "https://example.test/collections/demo/locations?f=json"
  first <- feature_collection("a", "?cursor=2")
  second <- feature_collection("b", first_url)
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    pagination_response(if (calls == 1L) first else second, req)
  })
  expect_error(
    edr_locations(
      edr_client("https://example.test", max_tries = 1), "demo",
      paginate = TRUE
    ),
    class = "edr_pagination_cycle"
  )
  expect_equal(calls, 2L)
})

test_that("multiple and malformed next links fail explicitly", {
  malformed <- list(
    list(
      type = "FeatureCollection", features = list(),
      links = list(list(rel = "next"), list(rel = "self", href = "/self"))
    ),
    list(
      type = "FeatureCollection", features = list(),
      links = list(
        list(rel = "next", href = "?page=2"),
        list(rel = "NEXT", href = "?page=3")
      )
    ),
    list(
      type = "FeatureCollection", features = list(),
      links = list(rel = "next", href = "?page=2")
    )
  )

  for (body in malformed) {
    httr2::local_mocked_responses(function(req) pagination_response(body, req))
    expect_error(
      edr_locations(
        edr_client("https://example.test", max_tries = 1), "demo",
        paginate = TRUE
      ),
      class = "edr_pagination_link"
    )
  }
})

test_that("feature order and duplicate ids are retained", {
  first <- feature_collection(c("a", "b"), "?page=2")
  second <- feature_collection(c("b", "c"))
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    pagination_response(if (calls == 1L) first else second, req)
  })

  result <- edr4r:::paginated_feature_collection_request(
    edr_client("https://example.test", max_tries = 1),
    "collections/demo/items", list(), "geojson", 2L, 10L
  )
  expect_equal(
    vapply(result$geojson$features, `[[`, character(1), "id"),
    c("a", "b", "b", "c")
  )
})

test_that("all-empty pages merge to a GeoJSON empty array", {
  first <- feature_collection(character(), "?page=2")
  second <- feature_collection()
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    pagination_response(if (calls == 1L) first else second, req)
  })

  result <- edr4r:::paginated_feature_collection_request(
    edr_client("https://example.test", max_tries = 1),
    "collections/demo/locations", list(), "geojson", 2L, 10L
  )
  expect_type(result$geojson$features, "list")
  expect_length(result$geojson$features, 0L)
  expect_equal(result$geojson$numberReturned, 0L)
})

test_that("204 and one-page servers terminate without a speculative request", {
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    mock_empty_response(url = req$url)
  })

  empty <- edr4r:::paginated_feature_collection_request(
    edr_client("https://example.test", max_tries = 1),
    "collections/demo/locations", list(limit = 2), "geojson", 2L, 10L
  )
  expect_equal(calls, 1L)
  expect_length(empty$geojson$features, 0L)
  expect_equal(
    attr(empty, "edr_pagination"),
    list(pages = 1L, features = 0L, complete = TRUE)
  )

  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    pagination_response(feature_collection(c("a", "b", "c")), req)
  })
  one_page <- edr4r:::paginated_feature_collection_request(
    edr_client("https://example.test", max_tries = 1),
    "collections/demo/locations", list(limit = 2), "geojson", 2L, 10L
  )
  expect_equal(calls, 1L)
  expect_equal(
    vapply(one_page$geojson$features, `[[`, character(1), "id"),
    c("a", "b", "c")
  )
})

test_that("a non-FeatureCollection page fails instead of returning partial data", {
  first <- feature_collection("a", "?page=2")
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    body <- if (calls == 1L) first else list(ok = TRUE)
    pagination_response(body, req)
  })

  expect_error(
    edr_items(
      edr_client("https://example.test", max_tries = 1), "demo",
      paginate = TRUE
    ),
    class = "edr_pagination_response"
  )
  expect_equal(calls, 2L)
})
