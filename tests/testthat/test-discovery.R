test_that("edr_collections returns a tidy tibble", {
  cols <- read_fixture("collections.json")
  httr2::local_mocked_responses(function(req) mock_json_response(cols))

  tb <- edr_collections(test_client())
  expect_s3_class(tb, "tbl_df")
  expect_equal(nrow(tb), 2)
  expect_setequal(tb$id, c("monitoring-locations", "daily-values"))

  ml <- tb[tb$id == "monitoring-locations", ]
  expect_equal(ml$extent_bbox[[1]], c(-123.60518, 28.4667, -95.875, 48.8283))
  expect_setequal(ml$data_queries[[1]], c("locations", "cube", "area"))
})

test_that("empty collection list yields an empty tibble", {
  httr2::local_mocked_responses(function(req) {
    mock_json_response(list(collections = list()))
  })
  tb <- edr_collections(test_client())
  expect_s3_class(tb, "tbl_df")
  expect_equal(nrow(tb), 0)
})

test_that("edr_conformance flattens the URI list", {
  httr2::local_mocked_responses(function(req) {
    mock_json_response(list(conformsTo = list("http://a", "http://b")))
  })
  cc <- edr_conformance(test_client())
  expect_equal(cc, c("http://a", "http://b"))
})

test_that("collection id is validated", {
  expect_error(edr_collection(test_client(), ""), "non-empty")
  expect_error(edr_collection(test_client(), c("a", "b")), "single non-empty")
  expect_error(edr_collection(test_client(), "a/b"), "must not contain")
})

test_that("collection ids are encoded as path segments", {
  captured <- NULL
  httr2::local_mocked_responses(function(req) {
    captured <<- req
    mock_json_response(list(ok = TRUE))
  })

  edr_collection(test_client(), "daily values?")
  expect_match(captured$url, "collections/daily%20values%3F", fixed = TRUE)
})

test_that("rich collection and parameter metadata is retained", {
  rich <- read_fixture("instances.json")$instances[[1L]]
  # Exercise multiple spatial boxes and parameter-level metadata that are not
  # present in the compact instances fixture.
  rich$extent$spatial$bbox <- list(
    c(-180, -90, 0, 90),
    c(0, -90, 180, 90)
  )
  rich$extent$custom <- list(list(
    id = "realisations",
    interval = list(c(1, 50)),
    values = list("R50/1/1"),
    reference = "Ensemble members"
  ))
  rich$parameter_names$air_temperature <- list(
    type = "Parameter",
    label = list(en = "Air temperature parameter"),
    description = "Near-surface temperature",
    unit = list(
      label = "kelvin",
      symbol = list(value = "K", type = "https://qudt.org/vocab/unit/K"),
      definition = "https://qudt.org/vocab/unit/K-PER-K"
    ),
    observedProperty = list(
      id = "http://codes.wmo.int/temperature",
      label = "Observed air temperature",
      categories = list()
    ),
    measurementType = list(method = "instantaneous"),
    extent = list(interval = list(c(180, 330)))
  )
  rich$parameter_names$air_temperature[["data-type"]] <- "float"
  httr2::local_mocked_responses(function(req) {
    mock_json_response(list(collections = list(rich)))
  })

  tb <- edr_collections(test_client())
  legacy_collection_columns <- c(
    "id", "title", "description", "extent_bbox", "extent_bboxes",
    "extent_crs", "crs", "extent_spatial", "extent_temporal",
    "extent_vertical", "output_crs", "output_formats", "parameters",
    "data_queries", "query_details", "query_error", "has_instances",
    "keywords", "links", "raw"
  )
  expect_identical(
    names(tb)[seq_along(legacy_collection_columns)],
    legacy_collection_columns
  )
  expect_identical(tail(names(tb), 1L), "extent_custom")
  expect_equal(tb$extent_bbox[[1]], c(-180, -90, 0, 90))
  expect_equal(length(tb$extent_bboxes[[1]]), 2L)
  expect_equal(tb$extent_crs, "CRS84")
  expect_equal(tb$crs, tb$extent_crs)
  expect_equal(unlist(tb$extent_temporal[[1]]$interval[[1]]), c(
    "2024-07-09T00:00:00Z", "2024-07-14T00:00:00Z"
  ))
  expect_equal(tb$extent_vertical[[1]]$vrs, "EPSG:5703")
  custom <- tb$extent_custom[[1]][[1L]]
  expect_equal(custom$id, "realisations")
  expect_equal(unlist(custom$interval, use.names = FALSE), c(1, 50))
  expect_equal(unlist(custom$values, use.names = FALSE), "R50/1/1")
  expect_equal(custom$reference, "Ensemble members")
  expect_equal(tb$output_crs[[1]], c("CRS84", "EPSG:4326"))
  expect_equal(tb$output_formats[[1]], c("CoverageJSON", "NetCDF"))

  cube <- tb$query_details[[1]]
  cube <- cube[cube$query == "cube", ]
  expect_equal(cube$query_type, "cube")
  expect_equal(cube$output_formats[[1]], c("CoverageJSON", "NetCDF"))
  expect_equal(cube$default_output_format, "CoverageJSON")
  expect_true(is.na(tb$query_error))

  params <- parameters_tibble(rich)
  legacy_parameter_columns <- c(
    "id", "name", "description", "parameter_type", "unit_symbol",
    "unit_label", "unit_id", "unit_type", "observed_property",
    "observed_property_label", "observed_property_description", "data_type",
    "measurement_type", "extent", "categories", "category_encoding", "raw"
  )
  expect_identical(
    names(params)[seq_along(legacy_parameter_columns)],
    legacy_parameter_columns
  )
  expect_identical(
    tail(names(params), 2L),
    c("unit_symbol_type", "unit_definition")
  )
  expect_equal(params$name, "Air temperature parameter")
  expect_equal(params$parameter_type, "Parameter")
  expect_equal(params$unit_symbol, "K")
  expect_equal(params$unit_symbol_type, "https://qudt.org/vocab/unit/K")
  expect_equal(params$unit_definition, "https://qudt.org/vocab/unit/K-PER-K")
  expect_equal(params$unit_id, "https://qudt.org/vocab/unit/K")
  expect_equal(params$observed_property, "http://codes.wmo.int/temperature")
  expect_equal(params$data_type, "float")
  expect_equal(params$measurement_type[[1]]$method, "instantaneous")
})

test_that("edr_parameters can use instance-scoped metadata", {
  metadata <- list(
    id = "run 00",
    parameter_names = list(
      wind = list(
        label = "Wind speed",
        description = "Instantaneous wind speed",
        unit = list(label = "metres per second", symbol = "m/s")
      )
    )
  )
  captured <- NULL
  httr2::local_mocked_responses(function(req) {
    captured <<- req$url
    mock_json_response(metadata)
  })

  params <- edr_parameters(
    test_client(), "model family",
    instance_id = "run 00"
  )

  expect_equal(params$id, "wind")
  expect_equal(params$name, "Wind speed")
  expect_equal(params$description, "Instantaneous wind speed")
  expect_equal(params$unit_symbol, "m/s")
  expect_equal(params$unit_label, "metres per second")
  expect_match(
    captured,
    "collections/model%20family/instances/run%200",
    fixed = TRUE
  )
})

test_that("legacy camelCase parameter dataType remains supported", {
  metadata <- list(parameter_names = list(
    legacy = list(label = "Legacy value", dataType = "integer")
  ))

  params <- parameters_tibble(metadata)

  expect_equal(params$id, "legacy")
  expect_equal(params$data_type, "integer")
})

test_that("one malformed query does not discard a collection or valid queries", {
  collection <- list(
    id = "partly-conformant",
    data_queries = list(
      position = list(link = list(
        href = "https://example.test/position",
        variables = list(
          query_type = "position",
          output_formats = list("CoverageJSON")
        )
      )),
      cube = "not-an-object"
    )
  )
  httr2::local_mocked_responses(function(req) {
    mock_json_response(list(collections = list(collection)))
  })

  tb <- edr_collections(test_client())
  expect_equal(nrow(tb), 1L)
  expect_equal(tb$data_queries[[1]], "position")
  expect_equal(tb$query_details[[1]]$query, "position")
  expect_match(tb$query_error, "cube:.*JSON object")
  expect_equal(tb$raw[[1]]$data_queries$cube, "not-an-object")
})

test_that("metadata documents and collection arrays are shape checked", {
  responses <- list(
    list(list(title = "array, not object")),
    list(collections = list(named = list(id = "x"))),
    list(collections = "not-an-array"),
    list(list(id = "array-collection"))
  )
  call_n <- 0L
  httr2::local_mocked_responses(function(req) {
    call_n <<- call_n + 1L
    mock_json_response(responses[[call_n]])
  })

  expect_error(edr_landing(test_client()), "must be a JSON object")
  expect_error(edr_collections(test_client()), "collections.*array")
  expect_error(edr_collections(test_client()), "collections.*array")
  expect_error(edr_collection(test_client(), "x"), "must be a JSON object")
})

test_that("discovery helpers use cache keys and refresh replaces values", {
  calls <- character()
  httr2::local_mocked_responses(function(req) {
    path <- sub("^http://test/?", "", sub("\\?.*$", "", req$url))
    calls <<- c(calls, path)
    if (identical(path, "conformance")) {
      return(mock_json_response(list(conformsTo = list(paste0("urn:call:", length(calls))))))
    }
    mock_json_response(list(
      id = "cached",
      parameter_names = list(value = list(label = "Value"))
    ))
  })
  client <- edr_client("http://test", max_tries = 1, cache_ttl = Inf)

  first <- edr_conformance(client)
  second <- edr_conformance(client)
  refreshed <- edr_conformance(client, refresh = TRUE)
  expect_equal(first, second)
  expect_false(identical(second, refreshed))

  first_params <- edr_parameters(client, "cached")
  second_params <- edr_parameters(client, "cached")
  expect_equal(first_params, second_params)
  expect_equal(sum(calls == "conformance"), 2L)
  expect_equal(sum(calls == "collections/cached"), 1L)
})
