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
})
