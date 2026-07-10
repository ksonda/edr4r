test_that("edr_location URL-encodes ids and sends filters", {
  captured <- NULL
  cov <- read_fixture("pointseries.covjson")
  httr2::local_mocked_responses(function(req) {
    captured <<- req
    mock_json_response(cov)
  })

  # A colon-separated triplet id (the kind used by some snow / forecast
  # networks) exercises the path-segment encoding path.
  res <- edr_location(test_client(), "station-network",
                      location_id = "1185:CO:SNTL",
                      datetime = "2020-01-01/..",
                      parameter_name = "swe")
  expect_s3_class(res, "edr_covjson")
  expect_match(captured$url, "locations/1185(%3A|:)CO(%3A|:)SNTL")
  expect_match(captured$url, "datetime=2020-01-01")
  expect_match(captured$url, "parameter-name=swe")
})

test_that("edr_location percent-encodes unsafe id characters", {
  captured <- NULL
  cov <- read_fixture("pointseries.covjson")
  httr2::local_mocked_responses(function(req) {
    captured <<- req
    mock_json_response(cov)
  })
  edr_location(test_client(), "demo", location_id = "a b", format = "json")
  expect_match(captured$url, "locations/a%20b")
})

test_that("edr_location resists query / fragment injection in ids", {
  # '?', '#', '&' would otherwise reshape the URL into query/fragment/etc.
  # Pre-encoding forces them inside the location-id segment.
  for (id in c("a?b", "a#b", "a&b")) {
    captured <- NULL
    cov <- read_fixture("pointseries.covjson")
    httr2::local_mocked_responses(function(req) {
      captured <<- req
      mock_json_response(cov)
    })
    edr_location(test_client(), "demo", location_id = id, format = "json")
    enc <- utils::URLencode(id, reserved = TRUE)
    expect_match(captured$url, paste0("locations/", enc), fixed = TRUE,
                 info = paste("id =", id))
    # Belt-and-braces: exactly one '/locations/' segment in the path.
    path <- sub("\\?.*$", "", captured$url)
    expect_equal(length(gregexpr("/locations/", path, fixed = TRUE)[[1]]), 1L,
                 info = paste("id =", id))
  }
})

test_that("edr_location rejects ids containing '/'", {
  expect_error(
    edr_location(test_client(), "demo", location_id = "a/b"),
    "must not contain"
  )
  expect_error(
    edr_item(test_client(), "demo", item_id = "a/b"),
    "must not contain"
  )
})

test_that("edr_cube serializes bbox and validates it", {
  captured <- NULL
  cov <- read_fixture("pointseries.covjson")
  httr2::local_mocked_responses(function(req) {
    captured <<- req
    mock_json_response(cov)
  })

  edr_cube(test_client(), "monitoring-locations",
           bbox = c(-101.4, 27.2, -92.7, 32.2),
           datetime = "2020-01-01/2020-12-31")
  expect_match(captured$url, "cube")
  expect_match(captured$url, "bbox=-101.4(%2C|,)27.2")

  expect_error(
    edr_cube(test_client(), "monitoring-locations", bbox = c(1, 2, 3)),
    "length 4 or 6"
  )
})

test_that("edr_area builds a POLYGON coords param", {
  captured <- NULL
  cov <- read_fixture("pointseries.covjson")
  httr2::local_mocked_responses(function(req) {
    captured <<- req
    mock_json_response(cov)
  })

  edr_area(test_client(), "monitoring-locations",
           coords = matrix(c(-109, 47, -104, 47, -104, 49, -109, 49),
                           ncol = 2, byrow = TRUE))
  expect_match(captured$url, "area")
  expect_match(utils::URLdecode(captured$url), "POLYGON\\(\\(")
})

test_that("edr_locations promotes GeoJSON to sf when sf present", {
  skip_if_not_installed("sf")
  gj <- read_fixture("locations.geojson")
  httr2::local_mocked_responses(function(req) {
    mock_json_response(gj, content_type = "application/geo+json")
  })
  res <- edr_locations(test_client(), "monitoring-locations")
  expect_s3_class(res, "sf")
  expect_equal(nrow(res), 2)
})

test_that("edr_position builds a POINT coords param", {
  captured <- NULL
  cov <- read_fixture("pointseries.covjson")
  httr2::local_mocked_responses(function(req) {
    captured <<- req
    mock_json_response(cov)
  })
  edr_position(test_client(), "monitoring-locations", coords = c(-105.5, 40.2))
  expect_match(utils::URLdecode(captured$url), "POINT\\(-105.5 40.2\\)")
})

test_that("edr_radius requires numeric within", {
  expect_error(
    edr_radius(test_client(), "monitoring-locations", coords = c(0, 0), within = "x"),
    "finite non-negative"
  )
  expect_error(
    edr_radius(test_client(), "monitoring-locations", coords = c(0, 0), within = -1),
    "non-negative"
  )
  expect_error(
    edr_radius(test_client(), "monitoring-locations", coords = c(0, 0), within = Inf),
    "finite"
  )
})

test_that("all bbox-taking verbs share finite ordered validation", {
  expect_error(
    edr_locations(test_client(), "demo", bbox = c(2, 0, 1, 1)),
    "minimum"
  )
  expect_error(
    edr_items(test_client(), "demo", bbox = c(0, 0, NA, 1)),
    "finite"
  )
})

test_that("edr_corridor requires valid width and height", {
  cov <- read_fixture("pointseries.covjson")
  captured <- NULL
  httr2::local_mocked_responses(function(req) {
    captured <<- req
    mock_json_response(cov)
  })

  edr_corridor(
    test_client(), "demo",
    coords = matrix(c(0, 0, 1, 1), ncol = 2, byrow = TRUE),
    corridor_width = 10,
    corridor_height = 100,
    width_units = "km",
    height_units = "m"
  )
  decoded <- utils::URLdecode(captured$url)
  expect_match(decoded, "corridor-width=10", fixed = TRUE)
  expect_match(decoded, "corridor-height=100", fixed = TRUE)
  expect_match(decoded, "height-units=m", fixed = TRUE)

  expect_error(
    edr_corridor(
      test_client(), "demo", coords = "LINESTRING(0 0, 1 1)",
      corridor_width = 0, corridor_height = 10
    ),
    "corridor_width.*positive"
  )
  expect_error(
    edr_corridor(
      test_client(), "demo", coords = "LINESTRING(0 0, 1 1)",
      corridor_width = 10, corridor_height = NA_real_
    ),
    "corridor_height.*positive"
  )
})

test_that("every collection query verb supports instance-scoped paths", {
  urls <- character()
  httr2::local_mocked_responses(function(req) {
    urls <<- c(urls, req$url)
    mock_json_response(list(ok = TRUE))
  })
  client <- test_client()
  instance <- "run 00"

  edr_locations(client, "model", format = "json", instance_id = instance)
  edr_location(
    client, "model", "station-1",
    format = "json", instance_id = instance
  )
  edr_items(client, "model", format = "json", instance_id = instance)
  edr_item(
    client, "model", "feature-1",
    format = "json", instance_id = instance
  )
  edr_position(
    client, "model", c(0, 0),
    format = "json", instance_id = instance
  )
  edr_area(
    client, "model", "POLYGON((0 0, 1 0, 1 1, 0 0))",
    format = "json", instance_id = instance
  )
  edr_cube(
    client, "model", c(0, 0, 1, 1),
    format = "json", instance_id = instance
  )
  edr_radius(
    client, "model", c(0, 0), within = 10,
    format = "json", instance_id = instance
  )
  edr_trajectory(
    client, "model", "LINESTRING(0 0, 1 1)",
    format = "json", instance_id = instance
  )
  edr_corridor(
    client, "model", "LINESTRING(0 0, 1 1)",
    corridor_width = 10, corridor_height = 100,
    format = "json", instance_id = instance
  )

  paths <- sub("^https?://[^/]+", "", urls)
  paths <- sub("\\?.*$", "", paths)
  prefix <- "/collections/model/instances/run%2000/"
  expect_equal(paths, paste0(prefix, c(
    "locations",
    "locations/station-1",
    "items",
    "items/feature-1",
    "position",
    "area",
    "cube",
    "radius",
    "trajectory",
    "corridor"
  )))
})

test_that("instance ids resist path, query, and fragment injection", {
  captured <- NULL
  httr2::local_mocked_responses(function(req) {
    captured <<- req
    mock_json_response(list(ok = TRUE))
  })

  instance <- "run?#&"
  edr_cube(
    test_client(), "model", c(0, 0, 1, 1),
    format = "json", instance_id = instance
  )
  encoded <- utils::URLencode(instance, reserved = TRUE)
  expect_match(
    captured$url,
    paste0("/collections/model/instances/", encoded, "/cube"),
    fixed = TRUE
  )

  expect_error(
    edr_position(
      test_client(), "model", c(0, 0),
      instance_id = "run/00"
    ),
    "instance_id.*must not contain"
  )
})

test_that("instance_id is keyword-only and legacy positional calls are unchanged", {
  verbs <- list(
    edr_locations, edr_location, edr_items, edr_item, edr_position,
    edr_area, edr_cube, edr_radius, edr_trajectory, edr_corridor
  )
  for (verb in verbs) {
    formal_names <- names(formals(verb))
    expect_gt(match("instance_id", formal_names), match("...", formal_names))
  }

  captured <- NULL
  httr2::local_mocked_responses(function(req) {
    captured <<- req
    mock_json_response(list(ok = TRUE))
  })
  # Every pre-existing formal is supplied positionally. The request must use
  # the original collection-level path, not treat any value as instance_id.
  edr_position(
    test_client(), "model", c(0, 0), "2024-01-01", "temp",
    NULL, NULL, "json"
  )
  path <- sub("\\?.*$", "", captured$url)
  expect_match(path, "/collections/model/position", fixed = TRUE)
  expect_false(grepl("/instances/", path, fixed = TRUE))
})
