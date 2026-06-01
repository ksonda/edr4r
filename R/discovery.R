#' EDR service landing page
#'
#' Retrieves the service root document, which advertises links to the
#' collections, conformance, and openapi endpoints.
#'
#' @param client An `edr_client`.
#' @return A list with the parsed landing document.
#' @export
edr_landing <- function(client) {
  edr_request(client, "/", format = "json")
}

#' Declared OGC API conformance classes
#'
#' @inheritParams edr_landing
#' @return A character vector of conformance class URIs.
#' @export
edr_conformance <- function(client) {
  body <- edr_request(client, "conformance", format = "json")
  unlist(body$conformsTo %||% list(), use.names = FALSE)
}

#' List collections offered by the service
#'
#' @inheritParams edr_landing
#' @return A tibble with one row per collection. Always includes `id`,
#'   `title`, `description`, `extent_bbox`, `crs`, `data_queries`, and
#'   `links` columns.
#' @export
edr_collections <- function(client) {
  body <- edr_request(client, "collections", format = "json")
  collections <- body$collections %||% list()
  if (length(collections) == 0L) {
    return(empty_collections_tibble())
  }
  # vec_rbind, not map_dfr: purrr deprecated map_dfr and now off-loads
  # the bind to dplyr, which we don't depend on.
  vctrs::vec_rbind(!!!lapply(collections, collection_row))
}

#' Get a single collection's metadata
#'
#' @inheritParams edr_landing
#' @param collection_id Collection identifier as advertised by the
#'   server -- e.g. `"monitoring-locations"` or `"daily-values"`.
#' @return A list with the raw collection document.
#' @export
edr_collection <- function(client, collection_id) {
  collection_id <- check_collection_id(collection_id)
  edr_request(client, paste0("collections/", collection_id), format = "json")
}

#' List queryable parameters for a collection
#'
#' Returns the JSON Schema describing parameters the collection accepts.
#' Useful for discovering valid `parameter_name` values.
#'
#' @inheritParams edr_collection
#' @return A list with the queryables document.
#' @export
edr_queryables <- function(client, collection_id) {
  collection_id <- check_collection_id(collection_id)
  edr_request(
    client,
    paste0("collections/", collection_id, "/queryables"),
    format = "json"
  )
}

# ---------------------------------------------------------------------
# helpers

check_collection_id <- function(collection_id, call = rlang::caller_env()) {
  if (!is.character(collection_id) || length(collection_id) != 1L ||
      is.na(collection_id) || !nzchar(collection_id)) {
    cli::cli_abort(
      "{.arg collection_id} must be a single non-empty string.",
      call = call
    )
  }
  collection_id
}

collection_row <- function(c) {
  bbox <- tryCatch(c$extent$spatial$bbox[[1]], error = function(e) NULL)
  crs  <- tryCatch(c$extent$spatial$crs, error = function(e) NA_character_)
  dq   <- names(c$data_queries %||% list())
  tibble::tibble(
    id          = c$id %||% NA_character_,
    title       = c$title %||% NA_character_,
    description = c$description %||% NA_character_,
    extent_bbox = list(unlist(bbox %||% NA_real_)),
    crs         = crs %||% NA_character_,
    data_queries = list(dq),
    links       = list(c$links %||% list())
  )
}

empty_collections_tibble <- function() {
  tibble::tibble(
    id          = character(),
    title       = character(),
    description = character(),
    extent_bbox = list(),
    crs         = character(),
    data_queries = list(),
    links       = list()
  )
}
