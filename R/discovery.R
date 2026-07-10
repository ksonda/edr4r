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
    body <- edr_request(client, "/", format = "json")
    check_metadata_object(body, "Landing page")
    body
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
    check_metadata_object(body, "Conformance response")
    character_values(body$conformsTo)
  })
}

#' List collections offered by the service
#'
#' @inheritParams edr_landing
#' @return A tibble with one row per collection. Always includes `id`,
#'   `title`, `description`, spatial/temporal/vertical extent columns,
#'   `extent_crs` (`crs` is retained as a compatibility alias), `output_crs`,
#'   `output_formats`, `parameters`, `data_queries`, `query_details`,
#'   `query_error`, `has_instances`, and `links` columns. `extent_bbox` is a
#'   convenience view of the first bounding box; all spatial extents are
#'   retained in `extent_bboxes` and `extent_spatial` list columns.
#' @export
edr_collections <- function(client, refresh = FALSE) {
  check_client(client)
  cached_discovery(client, "collections", refresh, function() {
    body <- edr_request(client, "collections", format = "json")
    check_metadata_object(body, "Collections response")
    if (!"collections" %in% names(body) || !is.list(body$collections) ||
        (length(body$collections) > 0L && !is.null(names(body$collections)))) {
      cli::cli_abort(
        "Collections response must contain a {.field collections} array."
      )
    }
    collections <- body$collections
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
      body <- edr_request(
        client,
        paste0("collections/", collection_id),
        format = "json"
      )
      check_metadata_object(body, "Collection response")
      body
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
      body <- edr_request(
        client,
        paste0("collections/", collection_id, "/queryables"),
        format = "json"
      )
      check_metadata_object(body, "Queryables response")
      body
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
#'   `id`, `name`, `description`, unit and observed-property metadata,
#'   `data_type`, `measurement_type`, `extent`, category metadata, and `raw`.
#' @export
edr_parameters <- function(client, collection_id, refresh = FALSE) {
  collection_id <- check_collection_id(collection_id)
  body <- edr_collection(client, collection_id, refresh = refresh)
  parameters_tibble(body)
}

parameters_tibble <- function(body) {
  check_metadata_object(body, "Collection response")
  params <- body$parameter_names %||% body$parameters %||% list()
  if (length(params) == 0L) {
    return(empty_parameters_tibble())
  }
  if (!is.list(params)) {
    cli::cli_abort(
      "Collection parameter metadata must be a JSON object."
    )
  }
  keys <- names(params)
  if (is.null(keys)) keys <- rep(NA_character_, length(params))
  rows <- Map(parameter_row, params, keys)
  vctrs::vec_rbind(!!!rows)
}

# ---------------------------------------------------------------------
# parameter helpers (check_collection_id / collection_row /
# empty_collections_tibble live below, alongside the collection helpers)

parameter_row <- function(p, key) {
  if (!is.list(p)) p <- list(description = as.character(p))
  obs <- p$observedProperty %||% list()
  if (!is.list(obs)) obs <- list(id = obs)
  unit <- p$unit %||% list()
  if (!is.list(unit)) unit <- list(symbol = unit)
  symbol <- unit$symbol
  tibble::tibble(
    id                = first_character(p$id %||% key),
    name              = localized(p$label) %||%
      localized(p$name) %||%
      localized(obs$label) %||%
      NA_character_,
    description       = localized(p$description) %||%
      localized(obs$description) %||%
      NA_character_,
    parameter_type    = first_character(p$type),
    unit_symbol       = extract_unit_symbol(symbol),
    unit_label        = localized(unit$label) %||% NA_character_,
    unit_id            = first_character(unit$id %||%
      if (is.list(symbol)) symbol$type else NULL),
    unit_type          = first_character(unit$type),
    observed_property = first_character(obs$id),
    observed_property_label = localized(obs$label) %||% NA_character_,
    observed_property_description = localized(obs$description) %||% NA_character_,
    data_type          = first_character(p$dataType),
    measurement_type   = list(p$measurementType %||% list()),
    extent             = list(p$extent %||% list()),
    categories         = list(obs$categories %||% list()),
    category_encoding  = list(p$categoryEncoding %||% list()),
    raw                = list(p)
  )
}

# unit$symbol may be a bare string or a {value, type} list.
extract_unit_symbol <- function(s) {
  if (is.null(s)) return(NA_character_)
  if (is.character(s) && length(s) >= 1L) return(s[[1L]])
  if (is.list(s)) {
    return(first_character(s$value %||% s$symbol %||% s$label))
  }
  NA_character_
}

empty_parameters_tibble <- function() {
  tibble::tibble(
    id                = character(),
    name              = character(),
    description       = character(),
    parameter_type    = character(),
    unit_symbol       = character(),
    unit_label        = character(),
    unit_id            = character(),
    unit_type          = character(),
    observed_property = character(),
    observed_property_label = character(),
    observed_property_description = character(),
    data_type          = character(),
    measurement_type   = list(),
    extent             = list(),
    categories         = list(),
    category_encoding  = list(),
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
  if (is.null(c) || !is.list(c)) {
    cli::cli_abort("Collection metadata must be a JSON object.")
  }
  extent <- c$extent
  if (!is.list(extent)) extent <- list()
  spatial <- extent$spatial
  if (!is.list(spatial)) spatial <- list()
  bboxes <- normalize_bboxes(spatial$bbox)
  bbox <- if (length(bboxes) > 0L) bboxes[[1L]] else NA_real_
  extent_crs <- first_character(spatial$crs)

  query_parse <- parse_query_capabilities(c$data_queries %||% list())
  query_details <- query_parse$rows
  dq <- if (nrow(query_details) > 0L) {
    query_details$query
  } else {
    query_names_best_effort(c$data_queries)
  }

  links <- c$links
  if (!is.list(links)) links <- list()
  parameters <- parameter_keys(c$parameter_names %||% c$parameters %||% list())
  link_hrefs <- vapply(links, function(link) {
    if (is.list(link)) first_character(link$href) else NA_character_
  }, character(1))
  link_rels <- vapply(links, function(link) {
    if (is.list(link)) first_character(link$rel) else NA_character_
  }, character(1))
  has_instances <- "instances" %in% dq ||
    any(tolower(link_rels) == "instances", na.rm = TRUE) ||
    any(grepl("/instances(?:/|[?#]|$)", link_hrefs, perl = TRUE), na.rm = TRUE)

  tibble::tibble(
    id          = first_character(c$id),
    title       = localized(c$title) %||% NA_character_,
    description = localized(c$description) %||% NA_character_,
    extent_bbox = list(unname(unlist(bbox, use.names = FALSE))),
    extent_bboxes = list(bboxes),
    extent_crs  = extent_crs,
    crs         = extent_crs,
    extent_spatial = list(spatial),
    extent_temporal = list(extent$temporal %||% list()),
    extent_vertical = list(extent$vertical %||% list()),
    output_crs = list(character_values(c$crs)),
    output_formats = list(character_values(c$output_formats)),
    parameters = list(parameters),
    data_queries = list(dq),
    query_details = list(query_details),
    query_error = query_parse$error,
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
    extent_bboxes = list(),
    extent_crs  = character(),
    crs         = character(),
    extent_spatial = list(),
    extent_temporal = list(),
    extent_vertical = list(),
    output_crs = list(),
    output_formats = list(),
    parameters = list(),
    data_queries = list(),
    query_details = list(),
    query_error = character(),
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

query_capability_row <- function(query_metadata, query_name) {
  if (!is.character(query_name) || length(query_name) != 1L ||
      is.na(query_name) || !nzchar(query_name)) {
    cli::cli_abort("EDR query names must be non-empty strings.")
  }
  if (is.null(query_metadata)) query_metadata <- list()
  if (!is.list(query_metadata)) {
    cli::cli_abort(
      "Metadata for query {.val {query_name}} must be a JSON object."
    )
  }
  link <- query_metadata$link %||% query_metadata
  if (!is.list(link)) {
    cli::cli_abort(
      "The {.field link} for query {.val {query_name}} must be a JSON object."
    )
  }
  variables <- link$variables %||% query_metadata$variables %||% list()
  if (!is.list(variables)) {
    cli::cli_abort(
      "The {.field variables} for query {.val {query_name}} must be a JSON object."
    )
  }
  crs_details <- variables$crs_details %||% list()
  if (!is.list(crs_details)) {
    cli::cli_abort(
      "The {.field crs_details} for query {.val {query_name}} must be an array."
    )
  }
  crs <- vapply(crs_details, function(detail) {
    if (is.list(detail)) first_character(detail$crs) else first_character(detail)
  }, character(1))
  crs <- crs[!is.na(crs) & nzchar(crs)]

  output_formats <- character_values(
    variables$output_formats %||%
      query_metadata$output_formats %||%
      link$output_formats
  )
  default_output_format <- first_character(
    variables$default_output_format %||%
      query_metadata$default_output_format %||%
      link$default_output_format
  )

  query_type <- first_character(variables$query_type)
  if (is.na(query_type)) query_type <- query_name

  tibble::tibble(
    query = query_name,
    query_type = query_type,
    title = first_character(variables$title %||% query_metadata$title),
    description = first_character(variables$description %||% query_metadata$description),
    href = first_character(link$href),
    rel = first_character(link$rel),
    media_type = first_character(link$type),
    output_formats = list(output_formats),
    default_output_format = default_output_format,
    crs = list(crs),
    crs_details = list(crs_details),
    within_units = list(character_values(variables$within_units)),
    width_units = list(character_values(variables$width_units)),
    height_units = list(character_values(variables$height_units)),
    raw = list(query_metadata)
  )
}

empty_query_capabilities_tibble <- function() {
  tibble::tibble(
    query = character(),
    query_type = character(),
    title = character(),
    description = character(),
    href = character(),
    rel = character(),
    media_type = character(),
    output_formats = list(),
    default_output_format = character(),
    crs = list(),
    crs_details = list(),
    within_units = list(),
    width_units = list(),
    height_units = list(),
    raw = list()
  )
}

parse_query_capabilities <- function(data_queries) {
  if (is.null(data_queries) || length(data_queries) == 0L) {
    return(list(rows = empty_query_capabilities_tibble(), error = NA_character_))
  }
  if (!is.list(data_queries) || is.null(names(data_queries)) ||
      any(is.na(names(data_queries)) | !nzchar(names(data_queries)))) {
    error <- tryCatch(
      {
        query_capability_rows(data_queries)
        NA_character_
      },
      error = conditionMessage
    )
    return(list(rows = empty_query_capabilities_tibble(), error = error))
  }

  parsed <- Map(function(query, query_name) {
    tryCatch(
      list(row = query_capability_row(query, query_name), error = NULL),
      error = function(e) list(
        row = NULL,
        error = paste0(query_name, ": ", conditionMessage(e))
      )
    )
  }, data_queries, names(data_queries))
  rows <- lapply(parsed, `[[`, "row")
  rows <- rows[!vapply(rows, is.null, logical(1))]
  errors <- unlist(lapply(parsed, `[[`, "error"), use.names = FALSE)
  list(
    rows = if (length(rows) == 0L) {
      empty_query_capabilities_tibble()
    } else {
      vctrs::vec_rbind(!!!rows)
    },
    error = if (length(errors) == 0L) NA_character_ else paste(errors, collapse = "; ")
  )
}

query_names_best_effort <- function(data_queries) {
  if (!is.list(data_queries) || length(data_queries) == 0L) return(character())
  nms <- names(data_queries)
  if (!is.null(nms)) {
    nms <- nms[!is.na(nms) & nzchar(nms)]
    if (length(nms) > 0L) return(unique(nms))
  }
  values <- vapply(data_queries, function(query) {
    if (!is.list(query)) return(NA_character_)
    link <- query$link %||% query
    if (!is.list(link)) return(NA_character_)
    variables <- link$variables %||% query$variables
    if (!is.list(variables)) return(NA_character_)
    first_character(variables$query_type)
  }, character(1))
  unique(values[!is.na(values) & nzchar(values)])
}

parameter_keys <- function(parameters) {
  if (!is.list(parameters) || length(parameters) == 0L) return(character())
  keys <- names(parameters)
  if (is.null(keys)) keys <- rep(NA_character_, length(parameters))
  ids <- Map(function(parameter, key) {
    if (is.list(parameter)) first_character(parameter$id %||% key) else first_character(key)
  }, parameters, keys)
  values <- unlist(ids, use.names = FALSE)
  unique(values[!is.na(values) & nzchar(values)])
}

normalize_bboxes <- function(x) {
  if (is.null(x)) return(list())
  if (is.atomic(x)) return(list(unname(x)))
  if (!is.list(x)) return(list())
  lapply(x, function(bbox) unname(unlist(bbox, use.names = FALSE)))
}

check_metadata_object <- function(x, label, call = rlang::caller_env()) {
  if (is.null(x) || !is.list(x) ||
      (length(x) > 0L && is.null(names(x)))) {
    cli::cli_abort("{label} must be a JSON object.", call = call)
  }
  invisible(x)
}

character_values <- function(x) {
  if (is.null(x)) return(character())
  values <- as.character(unlist(x, use.names = FALSE))
  unique(values[!is.na(values) & nzchar(values)])
}

first_character <- function(x) {
  values <- character_values(x)
  if (length(values) == 0L) NA_character_ else values[[1L]]
}
