#' EDR service landing page
#'
#' Retrieves the service root document, which advertises links to the
#' collections, conformance, and openapi endpoints.
#'
#' @param client An `edr_client`.
#' @param refresh If `TRUE`, bypass and replace any cached response. Discovery
#'   responses otherwise use the client's `cache_ttl`; see [edr_client()].
#' @return A list with the parsed landing document.
#' @export
edr_landing <- function(client, refresh = FALSE) {
  check_client(client)
  cached_discovery(client, "landing", refresh, function() {
    edr_request(client, "/", format = "json")
  })
}

#' Declared OGC API conformance classes
#'
#' @inheritParams edr_landing
#' @return A character vector of conformance class URIs.
#' @export
edr_conformance <- function(client, refresh = FALSE) {
  check_client(client)
  cached_discovery(client, "conformance", refresh, function() {
    body <- edr_request(client, "conformance", format = "json")
    unlist(body$conformsTo %||% list(), use.names = FALSE)
  })
}

#' List collections offered by the service
#'
#' @inheritParams edr_landing
#' @return A tibble with one row per collection. Always includes `id`,
#'   `title`, `description`, spatial/temporal/vertical extent columns, `crs`,
#'   `output_crs`, `output_formats`, `parameters`, `data_queries`,
#'   `query_details`, `has_instances`, and `links` columns. Rich nested
#'   metadata is retained in list columns rather than discarded.
#' @export
edr_collections <- function(client, refresh = FALSE) {
  check_client(client)
  cached_discovery(client, "collections", refresh, function() {
    body <- edr_request(client, "collections", format = "json")
    collections <- body$collections %||% list()
    if (length(collections) == 0L) {
      return(empty_collections_tibble())
    }
    # vec_rbind, not map_dfr: purrr deprecated map_dfr and now off-loads
    # the bind to dplyr, which we don't depend on.
    vctrs::vec_rbind(!!!lapply(collections, collection_row))
  })
}

#' Get a single collection's metadata
#'
#' @inheritParams edr_landing
#' @param collection_id Collection identifier as advertised by the
#'   server -- e.g. `"monitoring-locations"` or `"daily-values"`.
#' @return A list with the raw collection document.
#' @export
edr_collection <- function(client, collection_id, refresh = FALSE) {
  check_client(client)
  collection_id <- collection_path_id(collection_id)
  cached_discovery(
    client,
    paste0("collection:", collection_id),
    refresh,
    function() {
      edr_request(client, paste0("collections/", collection_id), format = "json")
    }
  )
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
edr_queryables <- function(client, collection_id, refresh = FALSE) {
  check_client(client)
  collection_id <- collection_path_id(collection_id)
  cached_discovery(
    client,
    paste0("queryables:", collection_id),
    refresh,
    function() {
      edr_request(
        client,
        paste0("collections/", collection_id, "/queryables"),
        format = "json"
      )
    }
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
#'   `observed_property`, `data_type`, `measurement_type`, `extent`,
#'   `categories`, and `raw`.
#' @export
edr_parameters <- function(client, collection_id, refresh = FALSE) {
  collection_id <- check_collection_id(collection_id)
  body <- edr_collection(client, collection_id, refresh = refresh)
  parameters_tibble(body)
}

parameters_tibble <- function(body) {
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
  if (!is.list(p)) p <- list(description = as.character(p))
  obs <- p$observedProperty %||% list()
  unit <- p$unit %||% list()
  tibble::tibble(
    id                = p$id %||% key %||% NA_character_,
    name              = p$name %||% localized(obs$label) %||% NA_character_,
    description       = localized(obs$description) %||% localized(p$description) %||% NA_character_,
    unit_symbol       = extract_unit_symbol(unit$symbol),
    unit_label        = localized(unit$label) %||% NA_character_,
    observed_property = obs$id %||% NA_character_,
    data_type          = first_character(p$dataType),
    measurement_type   = list(p$measurementType %||% list()),
    extent             = list(p$extent %||% list()),
    categories         = list(
      obs$categories %||% p$categoryEncoding %||% list()
    ),
    raw                = list(p)
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
    observed_property = character(),
    data_type          = character(),
    measurement_type   = list(),
    extent             = list(),
    categories         = list(),
    raw                = list()
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
  if (grepl("/", collection_id, fixed = TRUE)) {
    cli::cli_abort(
      c("{.arg collection_id} must not contain {.val /}.",
        i = "Collection ids are used as HTTP path segments."),
      call = call
    )
  }
  collection_id
}

collection_path_id <- function(collection_id, call = rlang::caller_env()) {
  collection_id <- check_collection_id(collection_id, call = call)
  utils::URLencode(collection_id, reserved = TRUE, repeated = TRUE)
}

collection_row <- function(c) {
  if (!is.list(c)) {
    cli::cli_abort("Collection metadata must be a JSON object.")
  }
  bbox <- tryCatch(c$extent$spatial$bbox[[1]], error = function(e) NULL)
  crs  <- tryCatch(c$extent$spatial$crs, error = function(e) NA_character_)
  dq <- names(c$data_queries %||% list()) %||% character()
  links <- c$links %||% list()
  parameters <- names(c$parameter_names %||% c$parameters %||% list()) %||%
    character()
  query_details <- query_capability_rows(c$data_queries %||% list())
  link_hrefs <- vapply(links, function(link) {
    if (is.list(link)) first_character(link$href) else NA_character_
  }, character(1))
  has_instances <- "instances" %in% dq ||
    any(grepl("/instances/?(?:[?#].*)?$", link_hrefs, perl = TRUE), na.rm = TRUE)

  tibble::tibble(
    id          = c$id %||% NA_character_,
    title       = c$title %||% NA_character_,
    description = c$description %||% NA_character_,
    extent_bbox = list(unlist(bbox %||% NA_real_)),
    crs         = crs %||% NA_character_,
    extent_temporal = list(c$extent$temporal %||% list()),
    extent_vertical = list(c$extent$vertical %||% list()),
    output_crs = list(character_values(c$crs)),
    output_formats = list(character_values(c$output_formats)),
    parameters = list(parameters),
    data_queries = list(dq),
    query_details = list(query_details),
    has_instances = has_instances,
    keywords = list(character_values(c$keywords)),
    links = list(links),
    raw = list(c)
  )
}

empty_collections_tibble <- function() {
  tibble::tibble(
    id          = character(),
    title       = character(),
    description = character(),
    extent_bbox = list(),
    crs         = character(),
    extent_temporal = list(),
    extent_vertical = list(),
    output_crs = list(),
    output_formats = list(),
    parameters = list(),
    data_queries = list(),
    query_details = list(),
    has_instances = logical(),
    keywords = list(),
    links = list(),
    raw = list()
  )
}

query_capability_rows <- function(data_queries) {
  if (is.null(data_queries) || length(data_queries) == 0L) {
    return(empty_query_capabilities_tibble())
  }
  if (!is.list(data_queries) || is.null(names(data_queries)) ||
      any(!nzchar(names(data_queries)))) {
    cli::cli_abort("Collection {.field data_queries} must be a named object.")
  }
  rows <- Map(query_capability_row, data_queries, names(data_queries))
  vctrs::vec_rbind(!!!rows)
}

query_capability_row <- function(query, query_name) {
  if (!is.list(query)) query <- list()
  link <- query$link %||% query
  if (!is.list(link)) link <- list()
  variables <- link$variables %||% query$variables %||% list()
  if (!is.list(variables)) variables <- list()
  crs_details <- variables$crs_details %||% list()
  crs <- vapply(crs_details, function(detail) {
    if (is.list(detail)) first_character(detail$crs) else NA_character_
  }, character(1))
  crs <- crs[!is.na(crs) & nzchar(crs)]

  tibble::tibble(
    query = query_name,
    title = first_character(variables$title),
    description = first_character(variables$description),
    href = first_character(link$href),
    output_formats = list(character_values(variables$output_formats)),
    default_output_format = first_character(variables$default_output_format),
    crs = list(crs),
    within_units = list(character_values(variables$within_units)),
    width_units = list(character_values(variables$width_units)),
    height_units = list(character_values(variables$height_units)),
    raw = list(query)
  )
}

empty_query_capabilities_tibble <- function() {
  tibble::tibble(
    query = character(),
    title = character(),
    description = character(),
    href = character(),
    output_formats = list(),
    default_output_format = character(),
    crs = list(),
    within_units = list(),
    width_units = list(),
    height_units = list(),
    raw = list()
  )
}

character_values <- function(x) {
  if (is.null(x)) return(character())
  values <- as.character(unlist(x, use.names = FALSE))
  values[!is.na(values) & nzchar(values)]
}

first_character <- function(x) {
  values <- character_values(x)
  if (length(values) == 0L) NA_character_ else values[[1L]]
}
