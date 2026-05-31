test_that("edr_client constructs and validates", {
  cl <- edr_client("http://localhost:5005/")
  expect_s3_class(cl, "edr_client")
  expect_equal(cl$base_url, "http://localhost:5005") # trailing slash trimmed
  expect_match(cl$user_agent, "^edr4r/")
  expect_equal(cl$max_tries, 3)

  expect_error(edr_client(123), "single non-NA string")
  expect_error(edr_client(c("a", "b")), "single non-NA string")
})

test_that("print method is stable", {
  cl <- edr_client("http://localhost:5005")
  expect_output(print(cl), "edr_client")
  expect_output(print(cl), "localhost:5005")
})

test_that("check_client rejects non-clients", {
  expect_error(edr_request(list(), "x"), "edr_client")
})
