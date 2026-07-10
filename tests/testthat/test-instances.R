test_that("edr_instances returns rich tidy instance metadata", {
  fixture <- read_fixture("instances.json")
  httr2::local_mocked_responses(function(req) mock_json_response(fixture))

  tb <- edr_instances(test_client(), "model")

  expect_s3_class(tb, "tbl_df")
  expect_equal(nrow(tb), 2L)
  expect_named(
    tb,
    c("collection_id", names(edr4r:::empty_collections_tibble()))
  )
  expect_equal(tb$collection_id, rep("model", 2L))
  expect_equal(tb$id, c("2024070900", "analysis 00"))
  expect_equal(tb$extent_bbox[[1]], c(-180, -90, 180, 90))
  expect_equal(tb$output_crs[[1]], c("CRS84", "EPSG:4326"))
  expect_equal(tb$output_formats[[1]], c("CoverageJSON", "NetCDF"))
  expect_equal(tb$parameters[[1]], "air_temperature")
  expect_setequal(
    tb$data_queries[[1]],
    c("position", "cube", "locations")
  )
  cube <- tb$query_details[[1]]
  cube <- cube[cube$query == "cube", ]
  expect_equal(cube$default_output_format, "CoverageJSON")
  expect_equal(cube$output_formats[[1]], c("CoverageJSON", "NetCDF"))
  expect_equal(tb$keywords[[1]], c("forecast", "model run"))
  expect_equal(tb$raw[[2]]$id, "analysis 00")
})

test_that("edr_instances parses the frozen Met Office Labs response", {
  fixture <- read_fixture("metoffice-instances.json")
  captured <- NULL
  httr2::local_mocked_responses(function(req) {
    captured <<- req
    mock_json_response(fixture)
  })

  tb <- edr_instances(test_client(), "moglobal-station-level")

  expect_equal(nrow(tb), 1L)
  expect_equal(tb$collection_id, "moglobal-station-level")
  expect_equal(tb$id, "2022070900")
  expect_equal(tb$extent_bbox[[1]], c(-180, 90, 180, -90))
  expect_equal(tb$output_crs[[1]], "MO_Global")
  expect_equal(tb$output_formats[[1]], "NetCDF")
  expect_setequal(tb$data_queries[[1]], c("position", "locations"))
  expect_setequal(
    tb$query_details[[1]]$query,
    c("position", "locations")
  )
  expect_match(
    captured$url,
    "/collections/moglobal-station-level/instances",
    fixed = TRUE
  )
})

test_that("edr_instances returns a typed empty tibble", {
  httr2::local_mocked_responses(function(req) {
    mock_json_response(list(instances = list(), links = list()))
  })

  tb <- edr_instances(test_client(), "empty-model")
  expect_s3_class(tb, "tbl_df")
  expect_equal(nrow(tb), 0L)
  expect_type(tb$collection_id, "character")
  expect_type(tb$id, "character")
  expect_type(tb$extent_bbox, "list")
  expect_type(tb$query_details, "list")
})

test_that("malformed instance indexes fail with a metadata error", {
  responses <- list(
    list(ok = TRUE),
    list(instances = "not-an-array"),
    list(instances = list(run = list(id = "run")))
  )
  call_n <- 0L
  httr2::local_mocked_responses(function(req) {
    call_n <<- call_n + 1L
    mock_json_response(responses[[call_n]])
  })

  expect_error(
    edr_instances(test_client(), "missing"),
    "must contain an.*instances.*array"
  )
  expect_error(
    edr_instances(test_client(), "malformed"),
    "must contain an.*instances.*array"
  )
  expect_error(
    edr_instances(test_client(), "object-shaped"),
    "must contain an.*instances.*array"
  )
})

test_that("instance discovery is cached and refresh replaces the cache", {
  fixture <- read_fixture("instances.json")
  call_n <- 0L
  httr2::local_mocked_responses(function(req) {
    call_n <<- call_n + 1L
    mock_json_response(fixture)
  })
  client <- edr_client("http://test", max_tries = 1, cache_ttl = Inf)

  first <- edr_instances(client, "model")
  second <- edr_instances(client, "model")
  refreshed <- edr_instances(client, "model", refresh = TRUE)

  expect_equal(first, second)
  expect_equal(second, refreshed)
  expect_equal(call_n, 2L)
})

test_that("edr_instance returns raw metadata and has an independent cache", {
  fixture <- read_fixture("instance.json")
  urls <- character()
  httr2::local_mocked_responses(function(req) {
    urls <<- c(urls, req$url)
    mock_json_response(fixture)
  })
  client <- edr_client("http://test", max_tries = 1, cache_ttl = Inf)

  first <- edr_instance(client, "model", "2024070900")
  second <- edr_instance(client, "model", "2024070900")
  refreshed <- edr_instance(
    client, "model", "2024070900",
    refresh = TRUE
  )

  expect_type(first, "list")
  expect_equal(first$id, "2024070900")
  expect_setequal(names(first$data_queries), c("position", "cube", "locations"))
  expect_equal(first, second)
  expect_equal(second, refreshed)
  expect_equal(length(urls), 2L)
  expect_true(all(grepl(
    "/collections/model/instances/2024070900",
    urls,
    fixed = TRUE
  )))
})

test_that("collection and instance ids are safe path segments", {
  fixture <- read_fixture("instance.json")
  captured <- NULL
  httr2::local_mocked_responses(function(req) {
    captured <<- req
    mock_json_response(fixture)
  })

  edr_instance(
    test_client(),
    collection_id = "model family?",
    instance_id = "run 00?#&"
  )
  expected <- paste0(
    "collections/",
    utils::URLencode("model family?", reserved = TRUE),
    "/instances/",
    utils::URLencode("run 00?#&", reserved = TRUE)
  )
  expect_match(captured$url, expected, fixed = TRUE)

  expect_error(
    edr_instance(test_client(), "model", "run/00"),
    "instance_id.*must not contain"
  )
  expect_error(
    edr_instances(test_client(), "model/family"),
    "collection_id.*must not contain"
  )
})

test_that("refresh must be a scalar logical for instance discovery", {
  expect_error(
    edr_instances(test_client(), "model", refresh = NA),
    "refresh.*TRUE.*FALSE"
  )
  expect_error(
    edr_instance(test_client(), "model", "run", refresh = "yes"),
    "refresh.*TRUE.*FALSE"
  )
})
