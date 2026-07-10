#' Perform a low-level EDR request
#'
#' Generally you should not need to call this directly: the high-level
#' verbs ([edr_locations()], [edr_area()], etc.) build the path and
#' query string for you. Use [edr_request()] when you need to hit a
#' bespoke path or a non-standard parameter.
#'
#' @param client An `edr_client` from [edr_client()].
#' @param path Path under the base URL (with or without leading slash),
#'   e.g. `"collections/monitoring-locations/locations"`.
#' @param query Named list of query parameters. Values may be scalars
#'   or vectors; vectors are joined with `","`. `NULL` entries are
#'   dropped.
#' @param format Response format: one of `"json"` (default), `"geojson"`,
#'   `"covjson"`, `"csv"`, `"html"`, or `"raw"`. Passed as `?f=` (except
#'   `"covjson"`, which is sent as `?f=json` with a CoverageJSON
#'   `Accept` hint, since EDR servers return CovJSON via JSON).
#' @param parse If `TRUE` (default), parses JSON / GeoJSON / CovJSON
#'   bodies into R structures. If `FALSE`, returns the raw `httr2`
#'   response.
#' @return A parsed list, tibble, or `edr_response` wrapper; an
#'   `httr2_response` when `parse = FALSE`; or a typed empty result for HTTP
#'   204 responses.
#' @export
edr_request <- function(client,
                        path,
                        query = list(),
                        format = c("json", "geojson", "covjson", "csv", "html", "raw"),
                        parse = TRUE) {
  check_client(client)
  format <- match.arg(format)
  req <- build_edr_http_request(client, path, query, format)
  resp <- perform_edr_request(req, verbose = client$verbose)

  if (!parse || format == "raw") {
    return(resp)
  }
  parse_response(resp, format = format)
}

build_edr_http_request <- function(client, path, query, format) {
  if (!is.character(path) || length(path) != 1L) {
    cli::cli_abort("{.arg path} must be a single string.")
  }
  path <- sub("^/+", "", path)

  query <- prepare_query(query, format = format)
  # Build the URL string ourselves so already-encoded path ids stay
  # encoded when query parameters are added. Some curl/httr2 builds
  # normalise %26 in a path back to '&' during URL reassembly.
  url <- build_request_url(client$base_url, path, query)

  req <- httr2::request(url) |>
    httr2::req_user_agent(client$user_agent) |>
    httr2::req_timeout(client$timeout) |>
    httr2::req_retry(
      max_tries = client$max_tries,
      retry_on_failure = isTRUE(client$retry_on_failure),
      is_transient = is_transient_edr
    ) |>
    httr2::req_error(body = edr_error_body)

  if (length(client$headers) > 0) {
    req <- httr2::req_headers(req, !!!as.list(client$headers))
  }

  req <- httr2::req_headers(req, Accept = accept_header(format))
  req
}

perform_edr_request <- function(req, verbose = FALSE) {
  if (isTRUE(verbose)) {
    cli::cli_inform("GET {req$url}")
  }
  httr2::req_perform(req)
}

build_request_url <- function(base_url, path, query) {
  base_url <- sub("/+$", "", base_url)
  if (nzchar(path)) {
    url <- paste0(base_url, "/", path)
  } else {
    url <- base_url
  }

  query_string <- build_query_string(query)
  if (nzchar(query_string)) {
    paste0(url, "?", query_string)
  } else {
    url
  }
}

build_query_string <- function(query, call = rlang::caller_env()) {
  if (length(query) == 0L) return("")

  nms <- names(query)
  if (is.null(nms) || any(!nzchar(nms))) {
    cli::cli_abort(
      "All components of {.arg query} must be named.",
      call = call
    )
  }

  parts <- Map(build_query_pair, nms, query)
  paste(unlist(parts, use.names = FALSE), collapse = "&")
}

build_query_pair <- function(name, value, call = rlang::caller_env()) {
  if (!is.atomic(value) && !inherits(value, "AsIs")) {
    cli::cli_abort(
      "All elements of {.arg query} must be atomic vectors or {.code NULL}.",
      call = call
    )
  }

  name <- utils::URLencode(name, reserved = TRUE, repeated = TRUE)
  values <- encode_query_value(value, name, call = call)
  paste0(name, "=", values)
}

encode_query_value <- function(value, name, call = rlang::caller_env()) {
  if (inherits(value, "AsIs")) {
    value <- unclass(value)
    if (!is.character(value)) {
      cli::cli_abort(
        "Escaped query value {.val {name}} must be a character vector.",
        call = call
      )
    }
    return(paste(value, collapse = ","))
  }

  value <- format(value, scientific = FALSE, trim = TRUE, justify = "none")
  value <- utils::URLencode(value, reserved = TRUE, repeated = TRUE)
  paste(value, collapse = ",")
}

prepare_query <- function(query, format) {
  if (is.null(query)) query <- list()
  if (!is.list(query)) {
    cli::cli_abort("{.arg query} must be a named list.")
  }
  # Drop NULLs / empty.
  query <- query[!vapply(query, function(v) is.null(v) || length(v) == 0L, logical(1))]

  # Honour explicit user-supplied f.
  if (!"f" %in% names(query)) {
    # pygeoapi (and most OGC API servers) serve *both* GeoJSON and
    # CoverageJSON under `f=json`, distinguishing them by the body's
    # `type` field. `f=geojson` / `f=covjson` are not registered formats
    # and return HTTP 400, so map both to `f=json` and sniff the body.
    f_value <- switch(format,
      json    = "json",
      geojson = "json",
      covjson = "json",
      csv     = "csv",
      html    = "html",
      raw     = NULL
    )
    if (!is.null(f_value)) query$f <- f_value
  }
  query
}

accept_header <- function(format) {
  switch(format,
    json    = "application/json",
    geojson = "application/geo+json, application/json;q=0.9",
    covjson = "application/prs.coverage+json, application/json;q=0.9",
    csv     = "text/csv",
    html    = "text/html",
    raw     = "*/*"
  )
}

is_transient_edr <- function(resp) {
  status <- httr2::resp_status(resp)
  status == 408 || status == 429 || (status >= 500 && status < 600)
}

edr_error_body <- function(resp) {
  # Try to extract a useful message from JSON or text bodies.
  ct <- tryCatch(httr2::resp_content_type(resp), error = function(e) "")
  body <- tryCatch(
    if (grepl("json", ct, fixed = TRUE)) {
      j <- httr2::resp_body_json(resp, check_type = FALSE)
      j$description %||% j$detail %||% j$message %||%
        j$title %||% jsonlite::toJSON(j, auto_unbox = TRUE)
    } else {
      httr2::resp_body_string(resp)
    },
    error = function(e) ""
  )
  body <- as.character(body)
  if (nzchar(body)) substr(body, 1, 500) else NULL
}

parse_response <- function(resp, format) {
  status <- httr2::resp_status(resp)
  if (status == 204L) {
    return(empty_parsed_response(format))
  }

  ct <- tryCatch(httr2::resp_content_type(resp), error = function(e) "")
  if (length(ct) == 0L || is.na(ct)) ct <- ""

  if (format == "csv" || grepl("csv", ct, fixed = TRUE)) {
    if (format == "csv" && nzchar(ct) && grepl("json", ct, fixed = TRUE)) {
      cli::cli_abort(
        c("Expected a CSV response, but the server returned {.val {ct}}.",
          i = "Inspect the response with {.code parse = FALSE} or request a supported server format.")
      )
    }
    txt <- httr2::resp_body_string(resp)
    return(read_csv_text(txt))
  }

  if (format == "html" || grepl("html", ct, fixed = TRUE)) {
    return(httr2::resp_body_string(resp))
  }

  # Default: JSON-ish.
  body <- tryCatch(
    httr2::resp_body_json(resp,
      check_type    = FALSE,
      simplifyVector = FALSE
    ),
    error = function(e) {
      cli::cli_abort(
        "Failed to parse response as JSON ({ct}): {conditionMessage(e)}"
      )
    }
  )

  # Sniff the body so we wrap correctly even when the server returns
  # GeoJSON/CoverageJSON under a generic `application/json` content-type
  # (as pygeoapi does), regardless of the requested `format`.
  switch(detect_json_kind(body, format),
    geojson = wrap_geojson(body),
    covjson = wrap_covjson(body),
    body
  )
}

empty_parsed_response <- function(format) {
  mark_empty <- function(x) {
    class(x) <- unique(c("edr_empty_response", class(x)))
    x
  }

  switch(format,
    geojson = mark_empty(wrap_geojson(list(
      type = "FeatureCollection",
      features = list()
    ))),
    covjson = mark_empty(wrap_covjson(list(
      type = "CoverageCollection",
      parameters = list(),
      coverages = list()
    ))),
    csv = tibble::tibble(),
    html = "",
    json = structure(
      list(status = 204L, format = "json"),
      class = c("edr_empty_response", "edr_response", "list")
    ),
    raw = NULL
  )
}

detect_json_kind <- function(body, format) {
  type <- if (is.list(body)) body$type %||% "" else ""
  if (type %in% c("FeatureCollection", "Feature")) return("geojson")
  if (type %in% c("Coverage", "CoverageCollection")) return("covjson")
  # No decisive marker in the body: fall back to what the caller asked
  # for, but never force a wrapper onto a plain document (collections,
  # conformance, queryables, landing page, ...).
  switch(format,
    geojson = "geojson",
    covjson = "covjson",
    "json"
  )
}

read_csv_text <- function(txt) {
  # Minimal CSV reader using base R to avoid a hard dep on readr.
  con <- textConnection(txt)
  on.exit(close(con))
  tibble::as_tibble(utils::read.csv(con, stringsAsFactors = FALSE, check.names = FALSE))
}

wrap_geojson <- function(body) {
  # Stash the raw GeoJSON for callers; geojson_to_sf() can promote it.
  structure(
    list(geojson = body),
    class = c("edr_response", "edr_geojson", "list")
  )
}

wrap_covjson <- function(body) {
  structure(
    list(covjson = body),
    class = c("edr_response", "edr_covjson", "list")
  )
}

#' @export
format.edr_response <- function(x, ...) {
  if (inherits(x, "edr_empty_response")) {
    return(c(
      cli::format_inline("<edr_response: empty>"),
      cli::format_inline("  status: 204")
    ))
  }
  kind <- if (inherits(x, "edr_geojson")) "GeoJSON" else "CoverageJSON"
  n <- if (kind == "GeoJSON") {
    if (identical(x$geojson$type, "Feature")) 1L
    else length(x$geojson$features %||% list())
  } else {
    if (identical(x$covjson$type, "Coverage")) 1L
    else length(x$covjson$coverages %||% list())
  }
  c(
    cli::format_inline("<edr_response: {kind}>"),
    cli::format_inline("  {if (kind == 'GeoJSON') 'features' else 'coverages'}: {n}")
  )
}

#' @export
print.edr_response <- function(x, ...) {
  cat(format(x, ...), sep = "\n")
  invisible(x)
}
