#' Create an EDR client
#'
#' Builds a reusable client object that captures the base URL of an OGC
#' API - EDR service, a default user-agent, and HTTP options that are
#' applied to every request.
#'
#' @param base_url Base URL of an
#'   [OGC API - EDR](https://ogcapi.ogc.org/edr/) service. Examples:
#'   the [USGS waterdata OGC API](https://api.waterdata.usgs.gov/ogcapi/beta/)
#'   at `"https://api.waterdata.usgs.gov/ogcapi/beta"`, the
#'   [Western Water Datahub](https://api.wwdh.internetofwater.app) at
#'   `"https://api.wwdh.internetofwater.app"`, or
#'   `"http://localhost:5005"` for a local [pygeoapi](https://pygeoapi.io)
#'   dev server. A trailing slash is optional.
#' @param user_agent String sent in the `User-Agent` header. Defaults to
#'   `"edr4r/<version> (+https://github.com/ksonda/edr4r)"`.
#' @param timeout Request timeout in seconds. Defaults to 60.
#' @param max_tries Maximum number of attempts per request. The client
#'   retries on 408, 429, and 5xx responses with exponential backoff.
#'   Defaults to 3.
#' @param retry_on_failure If `TRUE` (default), retry low-level transport
#'   failures such as connection resets and transient DNS / TLS errors. EDR
#'   requests made by this package are read-only GET requests, so retrying
#'   them is safe.
#' @param cache_ttl Number of seconds to retain discovery responses in this
#'   client's in-memory cache. Defaults to 300 (five minutes). Use `0` to
#'   disable caching or `Inf` to retain metadata until [edr_cache_clear()] is
#'   called. Data-query responses are never cached.
#' @param headers Named character vector of extra headers attached to
#'   every request (e.g. `c(Authorization = "Bearer ...")`).
#' @param verbose If `TRUE`, prints request URLs to the console as they
#'   are made. Useful for debugging.
#'
#' @return An object of class `edr_client`.
#' @export
#'
#' @examples
#' usgs <- edr_client("https://api.waterdata.usgs.gov/ogcapi/beta")
#' usgs
edr_client <- function(base_url,
                       user_agent = NULL,
                       timeout = 60,
                       max_tries = 3,
                       retry_on_failure = TRUE,
                       cache_ttl = 300,
                       headers = NULL,
                       verbose = FALSE) {
  if (!is.character(base_url) || length(base_url) != 1L || is.na(base_url) ||
      !nzchar(base_url)) {
    cli::cli_abort(
      "{.arg base_url} must be a single non-NA string and must not be empty."
    )
  }
  base_url <- trimws(base_url)
  base_url <- sub("/+$", "", base_url)
  if (!nzchar(base_url)) {
    cli::cli_abort(
      "{.arg base_url} must be a single non-NA string and must not be empty."
    )
  }

  if (!is.numeric(timeout) || length(timeout) != 1L ||
      is.na(timeout) || !is.finite(timeout) || timeout <= 0) {
    cli::cli_abort("{.arg timeout} must be a single positive number.")
  }
  if (!is.numeric(max_tries) || length(max_tries) != 1L ||
      is.na(max_tries) || !is.finite(max_tries) || max_tries < 1 ||
      max_tries > .Machine$integer.max || max_tries %% 1 != 0) {
    cli::cli_abort("{.arg max_tries} must be a single positive integer.")
  }
  if (!is.logical(retry_on_failure) || length(retry_on_failure) != 1L ||
      is.na(retry_on_failure)) {
    cli::cli_abort("{.arg retry_on_failure} must be {.code TRUE} or {.code FALSE}.")
  }
  if (!is.numeric(cache_ttl) || length(cache_ttl) != 1L ||
      is.na(cache_ttl) || cache_ttl < 0) {
    cli::cli_abort(
      "{.arg cache_ttl} must be a single non-negative number or {.code Inf}."
    )
  }
  if (!is.logical(verbose) || length(verbose) != 1L || is.na(verbose)) {
    cli::cli_abort("{.arg verbose} must be {.code TRUE} or {.code FALSE}.")
  }

  if (!is.null(user_agent) &&
      (!is.character(user_agent) || length(user_agent) != 1L ||
       is.na(user_agent) || !nzchar(user_agent))) {
    cli::cli_abort("{.arg user_agent} must be a single non-empty string or {.code NULL}.")
  }
  if (!is.null(headers)) {
    header_names <- names(headers)
    if (!is.character(headers) || is.null(header_names) ||
        anyNA(headers) || anyNA(header_names) ||
        any(!nzchar(header_names))) {
      cli::cli_abort(
        "{.arg headers} must be a named character vector with non-empty names and non-NA values."
      )
    }
  }

  if (is.null(user_agent)) {
    ver <- tryCatch(
      as.character(utils::packageVersion("edr4r")),
      error = function(e) "0.0.0"
    )
    user_agent <- sprintf(
      "edr4r/%s (+https://github.com/ksonda/edr4r)",
      ver
    )
  }

  structure(
    list(
      base_url   = base_url,
      user_agent = user_agent,
      timeout    = timeout,
      max_tries  = as.integer(max_tries),
      retry_on_failure = retry_on_failure,
      cache_ttl  = cache_ttl,
      cache       = new.env(parent = emptyenv()),
      headers    = headers,
      verbose    = verbose
    ),
    class = "edr_client"
  )
}

#' @export
format.edr_client <- function(x, ...) {
  cache_label <- if (is.infinite(x$cache_ttl)) {
    "until cleared"
  } else if (identical(x$cache_ttl, 0) || identical(x$cache_ttl, 0L)) {
    "disabled"
  } else {
    paste0(format(x$cache_ttl, scientific = FALSE, trim = TRUE), "s")
  }
  c(
    cli::format_inline("<edr_client>"),
    cli::format_inline("  base_url:   {.url {x$base_url}}"),
    cli::format_inline("  user_agent: {x$user_agent}"),
    cli::format_inline("  timeout:    {x$timeout}s"),
    cli::format_inline("  max_tries:  {x$max_tries}"),
    cli::format_inline("  retry transport failures: {x$retry_on_failure}"),
    cli::format_inline("  discovery cache: {cache_label}")
  )
}

#' @export
print.edr_client <- function(x, ...) {
  cat(format(x, ...), sep = "\n")
  invisible(x)
}

is_edr_client <- function(x) inherits(x, "edr_client")

check_client <- function(client, call = rlang::caller_env()) {
  if (!is_edr_client(client)) {
    cli::cli_abort(
      "{.arg client} must be an {.cls edr_client} built with {.fn edr_client}.",
      call = call
    )
  }
  invisible(client)
}
