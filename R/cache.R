#' Clear cached EDR discovery metadata
#'
#' Removes landing-page, conformance, collection, instance, and queryables
#' responses cached by a client. Data-query responses are never cached.
#' The cache is process-local and stored on the client. Copies of the same
#' client share that cache because they share its backing environment.
#'
#' @param client An [edr_client()].
#'
#' @return `client`, invisibly. The client's cache is mutated in place.
#' @export
edr_cache_clear <- function(client) {
  check_client(client)
  cache <- client$cache
  if (is.environment(cache)) {
    rm(list = ls(envir = cache, all.names = TRUE), envir = cache)
  }
  invisible(client)
}

cached_discovery <- function(client, key, refresh, fetch,
                             call = rlang::caller_env()) {
  check_refresh(refresh, call = call)

  if (!is.character(key) || length(key) != 1L || is.na(key) || !nzchar(key)) {
    cli::cli_abort("Internal cache keys must be single non-empty strings.", call = call)
  }
  if (!is.function(fetch)) {
    cli::cli_abort("Internal cache fetchers must be functions.", call = call)
  }

  cache <- client$cache
  ttl <- client$cache_ttl %||% 0
  can_cache <- is.environment(cache) && is.numeric(ttl) &&
    length(ttl) == 1L && !is.na(ttl) && ttl > 0

  if (can_cache && !refresh && exists(key, envir = cache, inherits = FALSE)) {
    entry <- get(key, envir = cache, inherits = FALSE)
    if (valid_cache_entry(entry)) {
      age <- as.numeric(Sys.time()) - entry$stored_at
      if (is.infinite(ttl) || age < ttl) {
        return(entry$value)
      }
    }
    rm(list = key, envir = cache, inherits = FALSE)
  }

  value <- fetch()
  if (can_cache) {
    assign(
      key,
      list(value = value, stored_at = as.numeric(Sys.time())),
      envir = cache
    )
  }
  value
}

valid_cache_entry <- function(entry) {
  is.list(entry) &&
    all(c("value", "stored_at") %in% names(entry)) &&
    is.numeric(entry$stored_at) &&
    length(entry$stored_at) == 1L &&
    !is.na(entry$stored_at) &&
    is.finite(entry$stored_at)
}

check_refresh <- function(refresh, call = rlang::caller_env()) {
  if (!is.logical(refresh) || length(refresh) != 1L || is.na(refresh)) {
    cli::cli_abort(
      "{.arg refresh} must be {.code TRUE} or {.code FALSE}.",
      call = call
    )
  }
  invisible(refresh)
}
