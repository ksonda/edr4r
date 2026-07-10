#!/usr/bin/env Rscript

# Live, bounded interoperability probes for pagination and station batching.
#
# This script is intentionally outside tests/testthat. It is run only by the
# scheduled/manual, non-blocking GitHub Actions workflow and never by CRAN or
# the regular offline test suite.

suppressPackageStartupMessages(library(edr4r))

message("Checking USGS cursor pagination ...")
usgs <- edr_client(
  "https://api.waterdata.usgs.gov/ogcapi/beta",
  timeout = 20,
  max_tries = 2
)

locations <- edr_locations(
  usgs,
  "daily-edr",
  bbox = c(-78.60, 36.04, -78.28, 36.22),
  limit = 2,
  paginate = TRUE,
  max_pages = 25,
  max_features = 50
)
pagination <- attr(locations, "edr_pagination", exact = TRUE)
if (!is.list(pagination) || !isTRUE(pagination$complete) ||
    pagination$pages < 2L || pagination$features < 1L) {
  stop("USGS location pagination did not return a complete bounded result.",
       call. = FALSE)
}

location_ids <- if (is.data.frame(locations) && "id" %in% names(locations)) {
  unique(as.character(locations$id))
} else if (inherits(locations, "edr_geojson")) {
  features <- locations$geojson$features
  unique(vapply(
    features,
    function(feature) {
      id <- feature$id
      if (is.null(id) || length(id) != 1L || is.na(id)) NA_character_
      else as.character(id)
    },
    character(1)
  ))
} else {
  character()
}
location_ids <- utils::head(
  location_ids[!is.na(location_ids) & nzchar(location_ids)],
  2L
)
if (length(location_ids) == 0L) {
  stop("USGS pagination returned no usable location ids.", call. = FALSE)
}

message("Checking a bounded USGS station batch ...")
batch <- edr_location_batch(
  usgs,
  "daily-edr",
  location_id = location_ids,
  parameter_name = "00060",
  limit = 1,
  max_requests = length(location_ids),
  on_error = "collect",
  progress = FALSE
)
if (any(batch$requests$status == "error") || nrow(batch$data) < 1L) {
  details <- paste(batch$errors$message, collapse = "; ")
  stop(
    "USGS station batch did not parse successfully",
    if (nzchar(details)) paste0(": ", details) else ".",
    call. = FALSE
  )
}

message("Checking WWDH offset pagination ...")
wwdh <- edr_client(
  "https://api.wwdh.internetofwater.app",
  timeout = 20,
  max_tries = 2
)
wwdh_probe <- tryCatch(
  edr_items(
    wwdh,
    "rise-edr",
    limit = 2,
    paginate = TRUE,
    max_pages = 2,
    max_features = 10
  ),
  error = identity
)

if (inherits(wwdh_probe, "edr_pagination_max_pages")) {
  wwdh_result <- "followed two offset pages and stopped at the configured cap"
} else if (inherits(wwdh_probe, "error")) {
  stop(wwdh_probe)
} else {
  wwdh_pagination <- attr(wwdh_probe, "edr_pagination", exact = TRUE)
  if (!is.list(wwdh_pagination) || !isTRUE(wwdh_pagination$complete)) {
    stop("WWDH pagination returned neither a complete result nor a typed cap error.",
         call. = FALSE)
  }
  if (wwdh_pagination$pages < 2L || wwdh_pagination$features < 1L) {
    stop("WWDH pagination did not exercise a next-page continuation.",
         call. = FALSE)
  }
  wwdh_result <- paste(
    "completed", wwdh_pagination$pages, "pages and",
    wwdh_pagination$features, "items"
  )
}

message(
  "Pagination/batch smoke check passed: USGS ", pagination$pages,
  " pages / ", pagination$features, " locations; ",
  nrow(batch$data), " batch rows; WWDH ", wwdh_result, "."
)
