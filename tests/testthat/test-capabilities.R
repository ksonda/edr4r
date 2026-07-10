capability_route <- function(req,
                             landing = read_fixture("metoffice-landing.json"),
                             conformance = read_fixture("metoffice-conformance.json"),
                             collection = read_fixture("metoffice-terrain-collection.json"),
                             collections = NULL) {
  url <- sub("\\?.*$", "", req$url)
  if (grepl("/conformance$", url)) return(mock_json_response(conformance))
  if (grepl("/collections/[^/]+/instances/[^/]+$", url)) {
    return(mock_json_response(read_fixture("instance.json")))
  }
  if (grepl("/collections/[^/]+/instances$", url)) {
    return(mock_json_response(read_fixture("instances.json")))
  }
  if (grepl("/collections/[^/]+$", url)) return(mock_json_response(collection))
  if (grepl("/collections$", url)) {
    if (is.null(collections)) collections <- list(collection)
    return(mock_json_response(list(collections = collections)))
  }
  mock_json_response(landing)
}

test_that("service capabilities are scoped, cached snapshots", {
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    capability_route(req)
  })
  client <- edr_client("http://test", max_tries = 1, cache_ttl = Inf)

  first <- edr_capabilities(client)
  second <- edr_capabilities(client)
  refreshed <- edr_capabilities(client, refresh = TRUE)

  expect_s3_class(first, "edr_service_capabilities")
  expect_s3_class(first, "edr_capabilities")
  expect_equal(first$scope, "service")
  expect_equal(nrow(first$collections), 1L)
  expect_length(first$conformance, 8L)
  expect_equal(first, second)
  expect_equal(second, refreshed)
  expect_equal(calls, 6L)
  expect_match(paste(format(first), collapse = "\n"), "collections: 1")
  expect_output(print(first), "edr_capabilities/service")
})

test_that("collection capabilities preserve normalized and raw metadata", {
  collection <- read_fixture("metoffice-terrain-collection.json")
  urls <- character()
  httr2::local_mocked_responses(function(req) {
    urls <<- c(urls, req$url)
    mock_json_response(collection)
  })

  caps <- edr_capabilities(test_client(), "terrain_tiles")

  expect_s3_class(caps, "edr_collection_capabilities")
  expect_equal(caps$scope, "collection")
  expect_equal(caps$collection_id, "terrain_tiles")
  expect_identical(caps$collection, collection)
  expect_equal(caps$summary$id, "terrain_tiles")
  expect_setequal(caps$queries$query, c("position", "radius", "area", "trajectory"))
  expect_equal(caps$output_formats, "CoverageJSON")
  expect_equal(caps$output_crs, "EPSG:4326")
  expect_equal(caps$parameters$id, "Height")
  expect_equal(caps$parameters$unit_id, "https://qudt.org/vocab/unit/M")
  expect_true(is.na(caps$query_error))
  expect_length(urls, 1L)
  expect_match(urls, "/collections/terrain_tiles", fixed = TRUE)
  expect_output(print(caps), "edr_capabilities/collection")
})

test_that("instance capabilities retain parent and instance identity", {
  instance <- read_fixture("instance.json")
  captured <- NULL
  httr2::local_mocked_responses(function(req) {
    captured <<- req$url
    mock_json_response(instance)
  })

  caps <- edr_capabilities(test_client(), "model", "2024070900")

  expect_s3_class(caps, "edr_instance_capabilities")
  expect_equal(caps$scope, "instance")
  expect_equal(caps$collection_id, "model")
  expect_equal(caps$instance_id, "2024070900")
  expect_identical(caps$instance, instance)
  expect_setequal(caps$queries$query, c("position", "cube", "locations"))
  expect_true(edr_supports(caps, query = "locations", format = "GeoJSON"))
  expect_match(captured, "/collections/model/instances/2024070900", fixed = TRUE)
  printed <- paste(format(caps), collapse = "\n")
  expect_match(printed, "model/2024070900", fixed = TRUE)
  expect_match(printed, "CoverageJSON")
  expect_match(printed, "NetCDF")
  expect_match(printed, "GeoJSON")
})

test_that("query-specific formats take precedence and format-only uses a union", {
  collection <- read_fixture("instances.json")$instances[[1L]]
  httr2::local_mocked_responses(function(req) mock_json_response(collection))
  caps <- edr_capabilities(test_client(), "model")

  expect_true(edr_supports(caps, query = "POSITION"))
  expect_true(edr_supports(caps, query = "position", format = "csv"))
  expect_false(edr_supports(caps, query = "position", format = "netcdf"))
  expect_true(edr_supports(caps, format = "NetCDF"))
  expect_true(edr_supports(caps, format = "CSV"))
  expect_true(edr_supports(caps, format = "GeoJSON"))
  expect_false(edr_supports(caps, query = "corridor"))
  expect_false(edr_supports(caps, format = "GRIB2"))
  expect_false(edr_supports(caps, query = "missing", format = "NetCDF"))
  expect_true(edr_supports(caps, query = "cube", format = "netcdf"))
})

test_that("format aliases and MIME parameters normalize consistently", {
  metadata <- read_fixture("metoffice-terrain-collection.json")
  metadata$output_formats <- list(
    "CoverageJSON", "application/geo+json", "application/json", "text/csv",
    "application/x-netcdf", "image/tiff; application=geotiff",
    "application/x-grib2", "text/html"
  )
  httr2::local_mocked_responses(function(req) mock_json_response(metadata))
  caps <- edr_capabilities(test_client(), "formats")
  requested <- c(
    "covjson", "application/prs.coverage+json; charset=UTF-8",
    "GeoJSON", "json", "CSV", "nc", "NetCDF", "GeoTIFF", "tif",
    "GRIB2", "grib", "HTML"
  )
  expect_true(all(vapply(
    requested,
    function(value) edr_supports(caps, format = value),
    logical(1)
  )))
  expect_false(edr_supports(caps, format = "application/x-unknown"))
})

test_that("conformance checks support URIs, aliases, and namespaces", {
  httr2::local_mocked_responses(function(req) capability_route(req))
  caps <- edr_capabilities(test_client())
  full <- "http://www.opengis.net/spec/ogcapi-edr-1/1.0/conf/core"

  expect_true(edr_supports(caps, conformance = full))
  expect_true(edr_supports(caps, conformance = "edr/core"))
  expect_true(edr_supports(caps, conformance = "common/core"))
  expect_true(edr_supports(caps, conformance = "coveragejson"))
  expect_true(edr_supports(caps, conformance = "covjson"))
  expect_true(edr_supports(caps, conformance = "edr/covjson"))
  expect_false(edr_supports(caps, conformance = "common/unknown"))
  expect_error(edr_supports(caps, conformance = "core"), "ambiguous")
})

test_that("supports validates scope, ids, criteria, and malformed snapshots", {
  httr2::local_mocked_responses(function(req) capability_route(req))
  service <- edr_capabilities(test_client())
  collection <- edr_capabilities(test_client(), "terrain_tiles")

  expect_error(edr_supports(list(), query = "position"), "edr_client")
  expect_error(edr_supports(collection), "at least one")
  expect_error(edr_supports(service, query = "position"), "service-level")
  expect_error(edr_supports(collection, conformance = "edr/core"), "service-level")
  expect_error(
    edr_supports(collection, collection_id = "other", query = "position"),
    "does not match"
  )
  expect_error(
    edr_supports(collection, instance_id = "run", query = "position"),
    "collection-level"
  )
  expect_error(edr_capabilities(test_client(), instance_id = "run"), "collection_id")
  expect_error(edr_capabilities(test_client(), "model", "run/1"), "must not contain")
  expect_error(edr_supports(collection, query = "  "), "non-empty")

  malformed <- structure(
    list(scope = "collection"),
    class = c("edr_collection_capabilities", "edr_capabilities", "list")
  )
  expect_error(format(malformed), "Malformed")
  expect_error(edr_supports(malformed, query = "position"), "Malformed")
})

test_that("diagnose returns stable successful service and collection checks", {
  httr2::local_mocked_responses(function(req) capability_route(req))
  result <- edr_diagnose(test_client(), "terrain_tiles")

  expect_s3_class(result, "tbl_df")
  expect_identical(
    result$check,
    c(
      "landing", "discovery links", "conformance", "EDR core conformance",
      "collections", "collection ids", "collection advertised", "collection",
      "query metadata", "query links", "parameter metadata", "format metadata"
    )
  )
  expect_true(all(result$status == "pass"))
  expect_setequal(unique(result$status), "pass")
})

test_that("diagnose continues through independent partial failures", {
  landing_failed <- FALSE
  httr2::local_mocked_responses(function(req) {
    url <- sub("\\?.*$", "", req$url)
    if (identical(url, "http://test") && !landing_failed) {
      landing_failed <<- TRUE
      return(mock_json_response(list(detail = "landing down"), status = 503L))
    }
    if (grepl("/conformance$", url)) {
      return(mock_json_response(list(conformsTo = list(
        "http://www.opengis.net/spec/ogcapi-common-1/1.0/conf/core"
      ))))
    }
    if (grepl("/collections$", url)) {
      return(mock_json_response(list(collections = list(named = list(id = "broken")))))
    }
    mock_json_response(list(
      id = "broken",
      data_queries = list(position = "not-an-object"),
      parameter_names = "not-an-object"
    ))
  })

  result <- edr_diagnose(test_client(), "broken")
  status <- stats::setNames(result$status, result$check)
  expect_equal(status[["landing"]], "fail")
  expect_equal(status[["discovery links"]], "skip")
  expect_equal(status[["conformance"]], "pass")
  expect_equal(status[["EDR core conformance"]], "warn")
  expect_equal(status[["collections"]], "fail")
  expect_equal(status[["collection ids"]], "skip")
  expect_equal(status[["collection advertised"]], "skip")
  expect_equal(status[["collection"]], "pass")
  expect_equal(status[["query metadata"]], "fail")
  expect_equal(status[["query links"]], "skip")
  expect_equal(status[["parameter metadata"]], "fail")
  expect_equal(status[["format metadata"]], "warn")
})

test_that("diagnose skips dependent metadata checks when detail is unavailable", {
  httr2::local_mocked_responses(function(req) {
    url <- sub("\\?.*$", "", req$url)
    if (grepl("/collections/missing$", url)) {
      return(mock_json_response(list(detail = "not found"), status = 404L))
    }
    capability_route(req)
  })

  result <- edr_diagnose(test_client(), "missing")
  dependent <- result[result$check %in% c(
    "query metadata", "query links", "parameter metadata", "format metadata"
  ), ]
  expect_true(all(dependent$status == "skip"))
  expect_equal(result$status[result$check == "collection"], "fail")
})

test_that("diagnose reports duplicate collection ids", {
  duplicate <- read_fixture("metoffice-terrain-collection.json")
  httr2::local_mocked_responses(function(req) {
    capability_route(req, collections = list(duplicate, duplicate))
  })
  result <- edr_diagnose(test_client())
  expect_equal(result$status[result$check == "collection ids"], "fail")
  expect_match(result$detail[result$check == "collection ids"], "not unique")
})

test_that("instance diagnostics remain metadata-only and instance-scoped", {
  urls <- character()
  httr2::local_mocked_responses(function(req) {
    urls <<- c(urls, req$url)
    capability_route(
      req,
      collection = read_fixture("instance.json"),
      collections = list(list(id = "model"))
    )
  })
  result <- edr_diagnose(test_client(), "model", "2024070900")

  expect_true(all(c(
    "instances", "instance ids", "instance advertised", "instance"
  ) %in% result$check))
  expect_equal(result$status[result$check == "instance"], "pass")
  expect_false(any(grepl("/(position|cube|locations)(?:[?]|$)", urls)))
})
