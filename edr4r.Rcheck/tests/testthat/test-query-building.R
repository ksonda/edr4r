test_that("common_query renames params and joins vectors", {
  q <- edr4r:::common_query(
    bbox = c(-101.4, 27.2, -92.7, 32.2),
    datetime = c("2020-01-01", "2020-12-31"),
    parameter_name = c("storage", "elevation")
  )
  expect_equal(q$bbox, "-101.4,27.2,-92.7,32.2")
  expect_equal(q$datetime, "2020-01-01/2020-12-31")
  expect_equal(q[["parameter-name"]], c("storage", "elevation"))
  expect_false("parameter_name" %in% names(q))
})

test_that("single-string datetime is passed through", {
  q <- edr4r:::common_query(datetime = "2020-01-01/..")
  expect_equal(q$datetime, "2020-01-01/..")
})

test_that("WKT coercion handles vectors, matrices, and strings", {
  expect_equal(edr4r:::to_wkt_point(c(-105.5, 40.2)), "POINT(-105.5 40.2)")
  expect_equal(edr4r:::to_wkt_point("POINT(1 2)"), "POINT(1 2)")

  poly <- edr4r:::to_wkt_polygon(
    matrix(c(-109, 47, -104, 47, -104, 49, -109, 49), ncol = 2, byrow = TRUE)
  )
  expect_match(poly, "^POLYGON\\(\\(")
  # ring auto-closed
  expect_match(poly, "-109 47\\)\\)$")

  ls <- edr4r:::to_wkt_linestring(matrix(c(0, 0, 1, 1, 2, 0), ncol = 2, byrow = TRUE))
  expect_equal(ls, "LINESTRING(0 0, 1 1, 2 0)")

  expect_error(edr4r:::to_wkt_point("notwkt"), "WKT POINT")
})

test_that("WKT coercion rejects wrong geometry types and bad coordinates", {
  expect_error(edr4r:::to_wkt_point("POLYGON((0 0, 1 0, 1 1, 0 0))"), "WKT POINT")
  expect_error(edr4r:::to_wkt_polygon("LINESTRING(0 0, 1 1)"), "WKT POLYGON")
  expect_error(edr4r:::to_wkt_linestring("POINT(0 0)"), "WKT LINESTRING")

  expect_error(edr4r:::to_wkt_point(c(0, Inf)), "finite")
  expect_error(
    edr4r:::to_wkt_polygon(matrix(c(0, 0, 1, 1), ncol = 2, byrow = TRUE)),
    "at least 3"
  )
  expect_error(
    edr4r:::to_wkt_linestring(matrix(c(0, 0), ncol = 2)),
    "at least 2"
  )
  expect_error(
    edr4r:::to_wkt_polygon(data.frame(x = c("a", "b", "c"), y = c(1, 2, 3))),
    "numeric"
  )
})

test_that("bbox validation rejects bad lengths", {
  expect_error(edr4r:::check_bbox(c(1, 2, 3)), "length 4 or 6")
  expect_silent(edr4r:::check_bbox(c(1, 2, 3, 4)))
})
