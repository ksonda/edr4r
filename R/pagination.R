# Bounded pagination for GeoJSON FeatureCollection responses.
#
# OGC API servers advertise an opaque `rel = "next"` link.  The client must
# follow that URL as supplied rather than reconstructing an offset or cursor.

paginated_feature_collection_request <- function(client, path, query, format,
                                                  max_pages, max_features) {
  request <- build_edr_http_request(client, path, query, format)
  response <- perform_edr_request(request, verbose = client$verbose)
  paginate_geojson_response(
    client,
    request = request,
    first_response = response,
    format = format,
    max_pages = max_pages,
    max_features = max_features
  )
}

check_pagination_args <- function(paginate, max_pages, max_features,
                                  call = rlang::caller_env()) {
  if (!is.logical(paginate) || length(paginate) != 1L || is.na(paginate)) {
    cli::cli_abort(
      "{.arg paginate} must be {.code TRUE} or {.code FALSE}.",
      call = call
    )
  }
  check_pagination_limit(max_pages, "max_pages", call = call)
  check_pagination_limit(max_features, "max_features", call = call)
  invisible()
}

check_pagination_limit <- function(x, arg, call = rlang::caller_env()) {
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || !is.finite(x) ||
      x < 1 || x > .Machine$integer.max || x %% 1 != 0) {
    cli::cli_abort(
      "{.arg {arg}} must be a finite positive integer.",
      call = call
    )
  }
  invisible()
}

paginate_geojson_response <- function(client, request, first_response, format,
                                      max_pages, max_features) {
  pages <- list()
  visited <- character()
  page_number <- 1L
  feature_count <- 0L
  response <- first_response
  current_request <- request
  request_url <- request$url
  service_origin <- pagination_origin(
    pagination_url_parts(request_url, page_number = 1L)
  )

  repeat {
    page_url <- pagination_page_url(response, current_request)
    page_parts <- pagination_url_parts(page_url, page_number = page_number)
    page_origin <- pagination_origin(page_parts)

    if (!identical(page_origin, service_origin)) {
      pagination_abort(
        c(
          "Pagination response {page_number} changed origin.",
          "x" = "Expected {.url {service_origin}}, received {.url {page_origin}}."
        ),
        class = "edr_pagination_origin",
        page = page_number,
        url = page_url
      )
    }

    canonical <- canonical_pagination_url(page_url, page_parts)
    if (canonical %in% visited) {
      pagination_abort(
        "Pagination cycle detected at page {page_number}: {.url {page_url}}.",
        class = "edr_pagination_cycle",
        page = page_number,
        url = page_url
      )
    }
    visited <- c(visited, canonical)

    parsed <- parse_response(response, format = format)
    document <- feature_collection_document(
      parsed,
      page_number = page_number,
      page_url = page_url
    )
    page_features <- length(document$features)

    if (feature_count + page_features > max_features) {
      pagination_abort(
        c(
          "Pagination exceeded {.arg max_features} = {max_features} on page {page_number}.",
          "i" = paste0(
            "Fetched {feature_count} feature{?s} before this page; ",
            "the page contains {page_features}."
          )
        ),
        class = c(
          "edr_pagination_max_features",
          "edr_pagination_limit"
        ),
        page = page_number,
        pages_fetched = page_number - 1L,
        features_fetched = feature_count,
        page_features = page_features
      )
    }

    feature_count <- feature_count + page_features
    pages[[page_number]] <- document
    href <- feature_collection_next_href(document, page_number = page_number)

    if (is.null(href)) break

    next_url <- resolve_pagination_url(
      href,
      page_url = page_url,
      service_origin = service_origin,
      page_number = page_number
    )
    next_canonical <- canonical_pagination_url(
      next_url,
      pagination_url_parts(next_url, page_number = page_number)
    )
    if (next_canonical %in% visited) {
      pagination_abort(
        "Pagination cycle detected after page {page_number}: {.url {next_url}}.",
        class = "edr_pagination_cycle",
        page = page_number,
        url = next_url
      )
    }

    if (page_number >= max_pages) {
      pagination_abort(
        c(
          paste0(
            "Pagination reached {.arg max_pages} = {max_pages}, ",
            "but the server advertised another page."
          ),
          "i" = "Increase {.arg max_pages} to continue from {.url {next_url}}."
        ),
        class = c(
          "edr_pagination_max_pages",
          "edr_pagination_limit"
        ),
        page = page_number,
        pages_fetched = page_number,
        features_fetched = feature_count,
        next_url = next_url
      )
    }

    current_request <- httr2::req_url(current_request, next_url)
    response <- perform_edr_request(current_request, verbose = client$verbose)
    page_number <- page_number + 1L
  }

  merge_feature_collection_pages(pages, feature_count = feature_count)
}

pagination_page_url <- function(response, request) {
  url <- tryCatch(
    httr2::resp_url(response),
    error = function(e) NULL
  )
  if (!is.character(url) || length(url) != 1L || is.na(url) || !nzchar(url)) {
    url <- request$url
  }
  url
}

feature_collection_document <- function(x, page_number, page_url) {
  document <- if (inherits(x, "edr_geojson")) x$geojson else NULL
  valid_type <- is.list(document) &&
    is.character(document$type) && length(document$type) == 1L &&
    !is.na(document$type) && identical(document$type, "FeatureCollection")
  valid_features <- valid_type && "features" %in% names(document) &&
    is.list(document$features)

  if (!valid_features) {
    pagination_abort(
      c(
        "Pagination page {page_number} is not a GeoJSON FeatureCollection.",
        "x" = "Response URL: {.url {page_url}}"
      ),
      class = "edr_pagination_response",
      page = page_number,
      url = page_url
    )
  }
  if (length(document$features) > 0L &&
      !all(vapply(document$features, is.list, logical(1)))) {
    pagination_abort(
      "Pagination page {page_number} has a malformed {.field features} array.",
      class = "edr_pagination_response",
      page = page_number,
      url = page_url
    )
  }
  document
}

feature_collection_next_href <- function(document, page_number) {
  links <- document$links
  if (is.null(links)) return(NULL)
  if (!is.list(links) ||
      (!is.null(names(links)) && any(c("rel", "href") %in% names(links)))) {
    pagination_abort(
      "Pagination page {page_number} has a malformed {.field links} array.",
      class = "edr_pagination_link",
      page = page_number
    )
  }

  is_next <- vapply(links, function(link) {
    if (!is.list(link)) return(FALSE)
    rel <- link$rel
    is.character(rel) && length(rel) == 1L && !is.na(rel) &&
      identical(tolower(trimws(rel)), "next")
  }, logical(1))
  next_links <- links[is_next]

  if (length(next_links) == 0L) return(NULL)
  if (length(next_links) > 1L) {
    pagination_abort(
      "Pagination page {page_number} advertises multiple {.code rel = \"next\"} links.",
      class = "edr_pagination_link",
      page = page_number
    )
  }

  href <- next_links[[1L]]$href
  if (!is.character(href) || length(href) != 1L || is.na(href) ||
      !nzchar(trimws(href))) {
    pagination_abort(
      paste0(
        "Pagination page {page_number} has a {.code rel = \"next\"} ",
        "link without one non-empty {.field href}."
      ),
      class = "edr_pagination_link",
      page = page_number
    )
  }
  if (!identical(href, trimws(href))) {
    pagination_abort(
      paste0(
        "Pagination page {page_number} has a next-page {.field href} ",
        "with leading or trailing whitespace."
      ),
      class = "edr_pagination_link",
      page = page_number
    )
  }
  href
}

resolve_pagination_url <- function(href, page_url, service_origin,
                                   page_number = NA_integer_) {
  resolved <- tryCatch(
    resolve_raw_relative_url(page_url, href),
    error = function(e) NULL
  )
  if (!is.character(resolved) || length(resolved) != 1L ||
      is.na(resolved) || !nzchar(resolved)) {
    pagination_abort(
      "Could not resolve the next-page URL advertised on page {page_number}.",
      class = "edr_pagination_link",
      page = page_number,
      href = href
    )
  }

  parts <- pagination_url_parts(resolved, page_number = page_number)
  origin <- pagination_origin(parts)
  if (!identical(origin, service_origin)) {
    pagination_abort(
      c(
        "Refusing to follow a cross-origin pagination link on page {page_number}.",
        "x" = "Expected {.url {service_origin}}, received {.url {origin}}."
      ),
      class = "edr_pagination_origin",
      page = page_number,
      href = href,
      url = resolved
    )
  }
  resolved
}

resolve_raw_relative_url <- function(page_url, href) {
  # Strip the fragment without parsing/rebuilding the query. Opaque cursor
  # values can distinguish `+`, `%20`, and `%2B`, so URL round-tripping is not
  # safe here.
  href_no_fragment <- sub("#.*$", "", href)
  page_no_fragment <- sub("#.*$", "", page_url)

  # Absolute URI, including unsupported schemes which validation rejects.
  if (grepl("^[A-Za-z][A-Za-z0-9+.-]*:", href_no_fragment)) {
    return(href_no_fragment)
  }

  page_parts <- httr2::url_parse(page_no_fragment)
  if (startsWith(href_no_fragment, "//")) {
    return(paste0(page_parts$scheme, ":", href_no_fragment))
  }
  if (startsWith(href_no_fragment, "?")) {
    return(paste0(sub("[?].*$", "", page_no_fragment), href_no_fragment))
  }
  # A fragment-only reference resolves to the current document. The caller's
  # cycle guard will reject it before another request is issued.
  if (!nzchar(href_no_fragment)) return(page_no_fragment)

  question <- regexpr("?", href_no_fragment, fixed = TRUE)[[1L]]
  if (question > 0L) {
    path <- substr(href_no_fragment, 1L, question - 1L)
    raw_query <- substr(href_no_fragment, question, nchar(href_no_fragment))
  } else {
    path <- href_no_fragment
    raw_query <- ""
  }

  authority_match <- regexpr(
    "^[A-Za-z][A-Za-z0-9+.-]*://[^/?#]*",
    page_no_fragment,
    perl = TRUE
  )
  authority <- regmatches(page_no_fragment, authority_match)
  if (!nzchar(authority)) stop("page URL has no authority")
  base_document <- sub("[?].*$", "", page_no_fragment)
  base_path <- substr(
    base_document,
    nchar(authority) + 1L,
    nchar(base_document)
  )

  merged_path <- if (startsWith(path, "/")) {
    path
  } else if (!nzchar(base_path)) {
    paste0("/", path)
  } else {
    paste0(sub("[^/]*$", "", base_path), path)
  }
  paste0(authority, remove_raw_dot_segments(merged_path), raw_query)
}

remove_raw_dot_segments <- function(path) {
  input <- path
  output <- ""
  remove_last_segment <- function(x) sub("/?[^/]*$", "", x)

  while (nzchar(input)) {
    if (startsWith(input, "../")) {
      input <- substr(input, 4L, nchar(input))
    } else if (startsWith(input, "./")) {
      input <- substr(input, 3L, nchar(input))
    } else if (startsWith(input, "/./")) {
      input <- paste0("/", substr(input, 4L, nchar(input)))
    } else if (identical(input, "/.")) {
      input <- "/"
    } else if (startsWith(input, "/../")) {
      input <- paste0("/", substr(input, 5L, nchar(input)))
      output <- remove_last_segment(output)
    } else if (identical(input, "/..")) {
      input <- "/"
      output <- remove_last_segment(output)
    } else if (input %in% c(".", "..")) {
      input <- ""
    } else if (startsWith(input, "/")) {
      next_slash <- regexpr("/", substr(input, 2L, nchar(input)), fixed = TRUE)[[1L]]
      if (next_slash < 0L) {
        output <- paste0(output, input)
        input <- ""
      } else {
        output <- paste0(output, substr(input, 1L, next_slash))
        input <- substr(input, next_slash + 1L, nchar(input))
      }
    } else {
      next_slash <- regexpr("/", input, fixed = TRUE)[[1L]]
      if (next_slash < 0L) {
        output <- paste0(output, input)
        input <- ""
      } else {
        output <- paste0(output, substr(input, 1L, next_slash - 1L))
        input <- substr(input, next_slash, nchar(input))
      }
    }
  }
  output
}

pagination_url_parts <- function(url, page_number = NA_integer_) {
  parts <- tryCatch(httr2::url_parse(url), error = function(e) NULL)
  if (is.null(parts)) {
    pagination_abort(
      "Pagination page {page_number} supplied an invalid URL: {.val {url}}.",
      class = "edr_pagination_link",
      page = page_number,
      url = url
    )
  }
  scheme <- tolower(parts$scheme %||% "")
  if (!scheme %in% c("http", "https") ||
      is.null(parts$hostname) || !nzchar(parts$hostname)) {
    pagination_abort(
      "Pagination only follows absolute HTTP(S) URLs; received {.val {url}}.",
      class = "edr_pagination_link",
      page = page_number,
      url = url
    )
  }
  if (!is.null(parts$username) || !is.null(parts$password)) {
    pagination_abort(
      "Refusing a pagination URL containing embedded credentials.",
      class = "edr_pagination_origin",
      page = page_number,
      url = url
    )
  }
  parts
}

pagination_origin <- function(parts) {
  scheme <- tolower(parts$scheme)
  host <- tolower(parts$hostname)
  port <- parts$port
  if (is.null(port) || !nzchar(port)) {
    port <- if (identical(scheme, "https")) "443" else "80"
  }
  paste0(scheme, "://", host, ":", port)
}

canonical_pagination_url <- function(url, parts = pagination_url_parts(url)) {
  url <- sub("#.*$", "", url)
  authority_match <- regexpr(
    "^[A-Za-z][A-Za-z0-9+.-]*://[^/?#]*",
    url,
    perl = TRUE
  )
  authority <- regmatches(url, authority_match)
  suffix <- substr(url, nchar(authority) + 1L, nchar(url))
  question <- regexpr("?", suffix, fixed = TRUE)[[1L]]
  if (question > 0L) {
    path <- substr(suffix, 1L, question - 1L)
    raw_query <- substr(suffix, question, nchar(suffix))
  } else {
    path <- suffix
    raw_query <- ""
  }
  if (!nzchar(path)) path <- "/"
  paste0(pagination_origin(parts), remove_raw_dot_segments(path), raw_query)
}

merge_feature_collection_pages <- function(pages, feature_count) {
  out <- pages[[1L]]
  features <- unlist(
      lapply(pages, function(page) page$features),
      recursive = FALSE,
      use.names = FALSE
    )
  # `unlist(list(), recursive = FALSE)` is NULL; GeoJSON requires an array.
  out$features <- if (is.null(features)) list() else features
  out$numberReturned <- feature_count

  if (!is.null(out$links)) {
    navigation <- c("next", "prev", "first", "last")
    keep <- vapply(out$links, function(link) {
      if (!is.list(link)) return(TRUE)
      rel <- link$rel
      if (!is.character(rel) || length(rel) != 1L || is.na(rel)) return(TRUE)
      !tolower(trimws(rel)) %in% navigation
    }, logical(1))
    out$links <- out$links[keep]
  }

  wrapped <- wrap_geojson(out)
  attr(wrapped, "edr_pagination") <- list(
    pages = as.integer(length(pages)),
    features = as.integer(feature_count),
    complete = TRUE
  )
  wrapped
}

pagination_abort <- function(message, class, ...) {
  cli::cli_abort(message, class = class, ..., .envir = parent.frame())
}
