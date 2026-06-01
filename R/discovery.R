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

#' Get the queryables (filter properties) for a collection
#'
#' Returns the OGC API queryables document for a collection -- a JSON
#' Schema describing the filter properties the server exposes (this is
#' typically used by OGC API Features for CQL2 / property-based
#' filtering). It is **not** the right place to look up the data
#' parameters / observed properties an EDR collection serves; for that,
#' use [edr_parameters()].
#'
#' @inheritParams edr_collection
#' @return A list with the parsed queryables document.
#' @export
edr_queryables <- function(client, collection_id) {
  collection_id <- check_collection_id(collection_id)
  edr_request(
    client,
    paste0("collections/", collection_id, "/queryables"),
    format = "json"
  )
}

#' List the data parameters a collection serves
#'
#' Pulls the `parameter_names` block out of the collection document
#' (`GET /collections/{id}`) and flattens it into a tidy tibble. These
#' are the observed properties you can pass to `parameter_name =` on the
#' query verbs ([edr_location()], [edr_cube()], etc.).
#'
#' EDR servers vary in how they key the `parameter_names` dictionary
#' (numeric IDs, short codes, etc.). The `id` column in the returned
#' tibble is the value to pass back as `parameter_name`; the `name`
#' column is the human-readable label.
#'
#' @inheritParams edr_collection
#' @return A tibble with one row per parameter. Columns:
#'   `id`, `name`, `description`, `unit_symbol`, `unit_label`,
#'   `observed_property`.
#' @export
edr_parameters <- function(client, collection_id) {
  collection_id <- check_collection_id(collection_id)
  body <- edr_collection(client, collection_id)
  params <- body$parameter_names %||% body$parameters %||% list()
  if (length(params) == 0L) {
    return(empty_parameters_tibble())
  }
  rows <- Map(parameter_row, params, names(params))
  vctrs::vec_rbind(!!!rows)
}

# ---------------------------------------------------------------------
# parameter helpers (check_collection_id / collection_row /
# empty_collections_tibble live below, alongside the collection helpers)

parameter_row <- function(p, key) {
  obs <- p$observedProperty %||% list()
  unit <- p$unit %||% list()
  tibble::tibble(
    id                = p$id %||% key %||% NA_character_,
    name              = p$name %||% localized(obs$label) %||% NA_character_,
    description       = localized(obs$description) %||% localized(p$description) %||% NA_character_,
    unit_symbol       = extract_unit_symbol(unit$symbol),
    unit_label        = localized(unit$label) %||% NA_character_,
    observed_property = obs$id %||% NA_character_
  )
}

# unit$symbol may be a bare string or a {value, type} list.
extract_unit_symbol <- function(s) {
  if (is.null(s)) return(NA_character_)
  if (is.character(s) && length(s) >= 1L) return(s[[1]])
  if (is.list(s)) return(s$value %||% s$symbol %||% s$label %||% NA_character_)
  NA_character_
}

empty_parameters_tibble <- function() {
  tibble::tibble(
    id                = character(),
    name              = character(),
    description       = character(),
    unit_symbol       = character(),
    unit_label        = character(),
    observed_property = character()
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
