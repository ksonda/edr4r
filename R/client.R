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
                       headers = NULL,
                       verbose = FALSE) {
  if (!is.character(base_url) || length(base_url) != 1L || is.na(base_url)) {
    cli::cli_abort("{.arg base_url} must be a single non-NA string.")
  }
  base_url <- sub("/+$", "", base_url)

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
      headers    = headers,
      verbose    = isTRUE(verbose)
    ),
    class = "edr_client"
  )
}

#' @export
format.edr_client <- function(x, ...) {
  c(
    cli::format_inline("<edr_client>"),
    cli::format_inline("  base_url:   {.url {x$base_url}}"),
    cli::format_inline("  user_agent: {x$user_agent}"),
    cli::format_inline("  timeout:    {x$timeout}s"),
    cli::format_inline("  max_tries:  {x$max_tries}"),
    cli::format_inline("  retry transport failures: {x$retry_on_failure}")
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
