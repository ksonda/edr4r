#' Inspect advertised EDR capabilities
#'
#' `edr_capabilities()` gathers discovery metadata without probing any data
#' query endpoint. With neither id it returns a service snapshot. With a
#' `collection_id` it returns a collection snapshot, and with both a
#' `collection_id` and `instance_id` it returns an instance snapshot.
#'
#' Discovery responses use the client's process-local in-memory cache. Set
#' `refresh = TRUE` to bypass matching entries, or call [edr_cache_clear()].
#' Capability values report what the server advertises; they do not prove that
#' the corresponding query succeeds.
#'
#' @param client An [edr_client()].
#' @param collection_id Optional collection identifier.
#' @param instance_id Optional instance identifier. Requires `collection_id`.
#' @param refresh If `TRUE`, bypass and replace cached discovery metadata.
#'
#' @return An `edr_capabilities` object with a scope-specific subclass:
#'   `edr_service_capabilities`, `edr_collection_capabilities`, or
#'   `edr_instance_capabilities`. Service snapshots contain `landing`,
#'   `conformance`, and `collections`. Collection and instance snapshots
#'   contain raw metadata, a normalized one-row `summary`, `queries`,
#'   `parameters`, `output_formats`, and `output_crs`.
#' @export
edr_capabilities <- function(client,
                             collection_id = NULL,
                             instance_id = NULL,
                             refresh = FALSE) {
  check_client(client)
  check_refresh(refresh)

  if (!is.null(collection_id)) {
    collection_id <- check_collection_id(collection_id)
  }
  if (!is.null(instance_id)) {
    instance_id <- check_capability_instance_id(instance_id)
    if (is.null(collection_id)) {
      cli::cli_abort(
        "{.arg collection_id} is required when {.arg instance_id} is supplied."
      )
    }
  }

  if (is.null(collection_id)) {
    return(structure(
      list(
        scope = "service",
        base_url = client$base_url,
        landing = edr_landing(client, refresh = refresh),
        conformance = edr_conformance(client, refresh = refresh),
        collections = edr_collections(client, refresh = refresh)
      ),
      class = c("edr_service_capabilities", "edr_capabilities", "list")
    ))
  }

  if (is.null(instance_id)) {
    metadata <- edr_collection(client, collection_id, refresh = refresh)
    return(metadata_capabilities(
      metadata,
      scope = "collection",
      base_url = client$base_url,
      collection_id = collection_id
    ))
  }

  metadata <- edr_instance(
    client,
    collection_id = collection_id,
    instance_id = instance_id,
    refresh = refresh
  )
  metadata_capabilities(
    metadata,
    scope = "instance",
    base_url = client$base_url,
    collection_id = collection_id,
    instance_id = instance_id
  )
}

metadata_capabilities <- function(metadata,
                                  scope,
                                  base_url,
                                  collection_id,
                                  instance_id = NULL) {
  check_metadata_object(metadata, paste0(tools::toTitleCase(scope), " response"))
  summary <- collection_row(metadata)
  fields <- list(
    scope = scope,
    base_url = base_url,
    collection_id = collection_id
  )
  if (identical(scope, "instance")) fields$instance_id <- instance_id
  fields[[scope]] <- metadata
  fields$summary <- summary
  fields$queries <- summary$query_details[[1L]]
  fields$query_error <- summary$query_error[[1L]]
  fields$parameters <- parameters_tibble(metadata)
  fields$output_formats <- summary$output_formats[[1L]]
  fields$output_crs <- summary$output_crs[[1L]]
  structure(
    fields,
    class = c(
      paste0("edr_", scope, "_capabilities"),
      "edr_capabilities",
      "list"
    )
  )
}

#' Test an advertised EDR capability
#'
#' Query names are matched case-insensitively. Format matching recognizes
#' common names and media types, including MIME parameters. With `query` and
#' `format`, query-specific formats take precedence and collection-level
#' formats are used only when the query advertises none. With `format` alone,
#' all top-level and query-specific formats are searched.
#'
#' Conformance checks accept full URIs, unambiguous final components such as
#' `"covjson"`, and namespace shorthand such as `"edr/core"` or
#' `"common/core"`. Bare `"core"` is rejected because multiple OGC API
#' standards advertise a core conformance class.
#'
#' @param x An [edr_client()] or an `edr_capabilities` snapshot.
#' @param collection_id Collection to inspect when `x` is a client. Required
#'   for query or format checks unless `x` is already collection/instance
#'   scoped.
#' @param instance_id Optional instance to inspect. Requires `collection_id`
#'   when `x` is a client.
#' @param query Optional scalar query type, such as `"cube"` or `"position"`.
#' @param format Optional scalar output format or media type.
#' @param conformance Optional conformance URI, namespace shorthand, or
#'   unambiguous final URI component.
#' @param refresh If `TRUE`, bypass and replace cached discovery metadata.
#'
#' @return A single logical value. Multiple criteria use AND semantics.
#'   `FALSE` means the capability was not advertised in the inspected
#'   metadata; it does not prove the server cannot implement it.
#' @export
edr_supports <- function(x,
                         collection_id = NULL,
                         instance_id = NULL,
                         query = NULL,
                         format = NULL,
                         conformance = NULL,
                         refresh = FALSE) {
  if (!is_edr_client(x) && !inherits(x, "edr_capabilities")) {
    cli::cli_abort(
      "{.arg x} must be an {.cls edr_client} or {.cls edr_capabilities}."
    )
  }
  check_refresh(refresh)
  collection_id <- optional_scalar_string(collection_id, "collection_id")
  instance_id <- optional_scalar_string(instance_id, "instance_id")
  query <- optional_scalar_string(query, "query")
  format <- optional_scalar_string(format, "format")
  conformance <- optional_scalar_string(conformance, "conformance")

  if (!is.null(collection_id)) collection_id <- check_collection_id(collection_id)
  if (!is.null(instance_id)) {
    instance_id <- check_capability_instance_id(instance_id)
    if (is.null(collection_id) && is_edr_client(x)) {
      cli::cli_abort(
        "{.arg collection_id} is required when {.arg instance_id} is supplied."
      )
    }
  }
  if (is.null(query) && is.null(format) && is.null(conformance)) {
    cli::cli_abort(
      "Supply at least one of {.arg query}, {.arg format}, or {.arg conformance}."
    )
  }

  checks <- logical()
  metadata_caps <- NULL
  if (!is.null(query) || !is.null(format)) {
    metadata_caps <- scoped_metadata_capabilities(
      x,
      collection_id = collection_id,
      instance_id = instance_id,
      refresh = refresh
    )
  }

  query_index <- NA_integer_
  if (!is.null(query)) {
    query_index <- match(tolower(query), tolower(metadata_caps$queries$query))
    checks <- c(checks, !is.na(query_index))
  }

  if (!is.null(format)) {
    advertised <- if (!is.null(query)) {
      if (is.na(query_index)) {
        character()
      } else {
        query_formats(metadata_caps$queries, query_index)
      }
    } else {
      all_advertised_formats(metadata_caps)
    }
    if (!is.null(query) && !is.na(query_index) && length(advertised) == 0L) {
      advertised <- metadata_caps$output_formats
    }
    checks <- c(
      checks,
      normalize_format_name(format) %in% normalize_format_names(advertised)
    )
  }

  if (!is.null(conformance)) {
    service_caps <- service_capabilities(x, refresh = refresh)
    checks <- c(
      checks,
      conformance_is_advertised(conformance, service_caps$conformance)
    )
  }

  all(checks)
}

#' Diagnose an EDR endpoint's discovery surface
#'
#' Performs small, read-only metadata requests and reports each check rather
#' than stopping at the first network or schema failure. No data query is
#' issued. Argument errors still stop immediately.
#'
#' @inheritParams edr_capabilities
#' @param refresh If `TRUE` (default), perform fresh probes and replace
#'   successful cache entries. Use `FALSE` to permit cached metadata.
#'
#' @return A tibble with stable `check`, `status` (`"pass"`, `"warn"`,
#'   `"fail"`, or `"skip"`), and `detail` columns.
#' @export
edr_diagnose <- function(client,
                         collection_id = NULL,
                         instance_id = NULL,
                         refresh = TRUE) {
  check_client(client)
  check_refresh(refresh)
  if (!is.null(collection_id)) collection_id <- check_collection_id(collection_id)
  if (!is.null(instance_id)) {
    instance_id <- check_capability_instance_id(instance_id)
    if (is.null(collection_id)) {
      cli::cli_abort(
        "{.arg collection_id} is required when {.arg instance_id} is supplied."
      )
    }
  }

  rows <- list()
  add <- function(row) rows[[length(rows) + 1L]] <<- row

  landing <- diagnostic_probe(
    "landing",
    function() edr_landing(client, refresh = refresh),
    function(value) diagnostic_assessment("pass", "Landing page is a JSON object.")
  )
  add(landing$row)
  add(if (is.null(landing$value)) {
    diagnostic_row("discovery links", "skip", "Landing metadata was unavailable.")
  } else {
    assess_discovery_links(landing$value)
  })

  conformance <- diagnostic_probe(
    "conformance",
    function() edr_conformance(client, refresh = refresh),
    function(value) {
      if (length(value) == 0L) {
        diagnostic_assessment("warn", "No conformance classes were advertised.")
      } else {
        diagnostic_assessment(
          "pass", paste(length(value), "conformance class(es) advertised.")
        )
      }
    }
  )
  add(conformance$row)
  add(if (is.null(conformance$value)) {
    diagnostic_row("EDR core conformance", "skip", "Conformance metadata was unavailable.")
  } else if (has_edr_core_conformance(conformance$value)) {
    diagnostic_row("EDR core conformance", "pass", "An EDR core class is advertised.")
  } else {
    diagnostic_row("EDR core conformance", "warn", "No EDR core class was advertised.")
  })

  collections <- diagnostic_probe(
    "collections",
    function() edr_collections(client, refresh = refresh),
    function(value) {
      if (nrow(value) == 0L) {
        diagnostic_assessment("warn", "The service advertised no collections.")
      } else {
        diagnostic_assessment("pass", paste(nrow(value), "collection(s) advertised."))
      }
    }
  )
  add(collections$row)
  add(assess_identifier_column(
    collections$value,
    check = "collection ids",
    unavailable = "Collection index was unavailable."
  ))

  if (is.null(collection_id)) return(vctrs::vec_rbind(!!!rows))

  add(assess_membership(
    collections$value,
    collection_id,
    check = "collection advertised",
    noun = "collection"
  ))
  collection <- diagnostic_probe(
    "collection",
    function() edr_collection(client, collection_id, refresh = refresh),
    function(value) assess_detail_id(value, collection_id, "collection")
  )
  add(collection$row)

  target <- collection
  if (!is.null(instance_id)) {
    instances <- diagnostic_probe(
      "instances",
      function() edr_instances(client, collection_id, refresh = refresh),
      function(value) {
        if (nrow(value) == 0L) {
          diagnostic_assessment("warn", "The collection advertised no instances.")
        } else {
          diagnostic_assessment("pass", paste(nrow(value), "instance(s) advertised."))
        }
      }
    )
    add(instances$row)
    add(assess_identifier_column(
      instances$value,
      check = "instance ids",
      unavailable = "Instance index was unavailable."
    ))
    add(assess_membership(
      instances$value,
      instance_id,
      check = "instance advertised",
      noun = "instance"
    ))
    target <- diagnostic_probe(
      "instance",
      function() edr_instance(
        client, collection_id, instance_id, refresh = refresh
      ),
      function(value) assess_detail_id(value, instance_id, "instance")
    )
    add(target$row)
  }

  metadata_rows <- diagnose_metadata_surface(target$value)
  for (row in metadata_rows) add(row)
  vctrs::vec_rbind(!!!rows)
}

#' @export
format.edr_capabilities <- function(x, ...) {
  scope <- capability_scope(x)
  if (identical(scope, "service")) {
    return(c(
      cli::format_inline("<edr_capabilities/service>"),
      cli::format_inline("  base_url: {x$base_url}"),
      cli::format_inline("  collections: {nrow(x$collections)}"),
      cli::format_inline("  conformance classes: {length(x$conformance)}")
    ))
  }
  id_line <- if (identical(scope, "instance")) {
    cli::format_inline("  instance: {x$collection_id}/{x$instance_id}")
  } else {
    cli::format_inline("  collection: {x$collection_id}")
  }
  advertised_formats <- all_advertised_formats(x)
  c(
    cli::format_inline("<edr_capabilities/{scope}>"),
    id_line,
    cli::format_inline("  queries: {nrow(x$queries)}"),
    cli::format_inline("  parameters: {nrow(x$parameters)}"),
    cli::format_inline("  formats: {paste(advertised_formats, collapse = ', ')}")
  )
}

#' @export
print.edr_capabilities <- function(x, ...) {
  cat(format(x, ...), sep = "\n")
  invisible(x)
}

scoped_metadata_capabilities <- function(x,
                                         collection_id,
                                         instance_id,
                                         refresh) {
  if (inherits(x, "edr_capabilities")) {
    scope <- capability_scope(x)
    if (identical(scope, "service")) {
      cli::cli_abort(
        "A service-level {.cls edr_capabilities} object cannot answer collection or instance checks."
      )
    }
    if (!is.null(collection_id) && !identical(collection_id, x$collection_id)) {
      cli::cli_abort(
        "{.arg collection_id} does not match the supplied capabilities object."
      )
    }
    if (identical(scope, "collection") && !is.null(instance_id)) {
      cli::cli_abort(
        "A collection-level capability snapshot cannot answer instance checks."
      )
    }
    if (identical(scope, "instance") && !is.null(instance_id) &&
        !identical(instance_id, x$instance_id)) {
      cli::cli_abort(
        "{.arg instance_id} does not match the supplied capabilities object."
      )
    }
    return(x)
  }
  if (is.null(collection_id)) {
    cli::cli_abort(
      "{.arg collection_id} is required for {.arg query} or {.arg format} checks."
    )
  }
  edr_capabilities(
    x,
    collection_id = collection_id,
    instance_id = instance_id,
    refresh = refresh
  )
}

service_capabilities <- function(x, refresh) {
  if (inherits(x, "edr_capabilities")) {
    if (!identical(capability_scope(x), "service")) {
      cli::cli_abort(
        "Only a service-level {.cls edr_capabilities} object can answer conformance checks."
      )
    }
    return(x)
  }
  edr_capabilities(x, refresh = refresh)
}

capability_scope <- function(x, call = rlang::caller_env()) {
  if (!inherits(x, "edr_capabilities") ||
      !is.character(x$scope) || length(x$scope) != 1L ||
      is.na(x$scope) || !x$scope %in% c("service", "collection", "instance")) {
    cli::cli_abort("Malformed {.cls edr_capabilities} object.", call = call)
  }
  expected_class <- paste0("edr_", x$scope, "_capabilities")
  required <- switch(x$scope,
    service = c("base_url", "landing", "conformance", "collections"),
    collection = c(
      "base_url", "collection_id", "collection", "summary", "queries",
      "parameters", "output_formats", "output_crs"
    ),
    instance = c(
      "base_url", "collection_id", "instance_id", "instance", "summary",
      "queries", "parameters", "output_formats", "output_crs"
    )
  )
  if (!inherits(x, expected_class) || !all(required %in% names(x))) {
    cli::cli_abort("Malformed {.cls edr_capabilities} object.", call = call)
  }
  x$scope
}

query_formats <- function(queries, index) {
  values <- queries$output_formats[[index]]
  default <- queries$default_output_format[[index]]
  if (!is.na(default) && nzchar(default)) values <- c(values, default)
  unique(values)
}

all_advertised_formats <- function(x) {
  values <- x$output_formats
  if (nrow(x$queries) > 0L) {
    values <- c(
      values,
      unlist(x$queries$output_formats, use.names = FALSE),
      x$queries$default_output_format
    )
  }
  unique(values[!is.na(values) & nzchar(values)])
}

optional_scalar_string <- function(x, arg, call = rlang::caller_env()) {
  if (is.null(x)) return(NULL)
  if (!is.character(x) || length(x) != 1L || is.na(x) ||
      !nzchar(trimws(x))) {
    cli::cli_abort(
      "{.arg {arg}} must be a single non-empty string.",
      call = call
    )
  }
  trimws(x)
}

check_capability_instance_id <- function(instance_id,
                                         call = rlang::caller_env()) {
  instance_id <- optional_scalar_string(instance_id, "instance_id", call = call)
  if (grepl("/", instance_id, fixed = TRUE)) {
    cli::cli_abort(
      c(
        "{.arg instance_id} must not contain {.val /}.",
        i = "Instance ids are used as HTTP path segments."
      ),
      call = call
    )
  }
  instance_id
}

normalize_format_names <- function(x) {
  if (length(x) == 0L) return(character())
  unique(vapply(x, normalize_format_name, character(1)))
}

normalize_format_name <- function(x) {
  x <- trimws(as.character(x)[[1L]])
  x <- sub(";.*$", "", x)
  key <- tolower(gsub("[^[:alnum:]+]", "", x))
  aliases <- list(
    covjson = c(
      "covjson", "coveragejson", "applicationprscoverage+json",
      "applicationcoverage+json", "applicationvndcov+json"
    ),
    geojson = c("geojson", "applicationgeo+json"),
    json = c("json", "applicationjson"),
    csv = c("csv", "textcsv"),
    netcdf = c("netcdf", "nc", "applicationnetcdf", "applicationxnetcdf"),
    geotiff = c(
      "geotiff", "tif", "tiff", "imagetiff", "imagegeotiff",
      "applicationgeotiff", "applicationxgeotiff"
    ),
    grib2 = c(
      "grib2", "grib", "applicationgrib", "applicationxgrib2",
      "applicationwmogrib"
    ),
    html = c("html", "texthtml")
  )
  for (canonical in names(aliases)) {
    if (key %in% aliases[[canonical]]) return(canonical)
  }
  key
}

conformance_is_advertised <- function(requested, advertised) {
  requested <- tolower(sub("/+$", "", trimws(requested)))
  advertised <- tolower(sub("/+$", "", trimws(as.character(advertised))))
  advertised <- advertised[nzchar(advertised)]

  if (grepl("^[a-z][a-z0-9+.-]*://", requested) ||
      grepl("^urn:", requested)) {
    return(requested %in% advertised)
  }
  if (identical(requested, "core")) {
    cli::cli_abort(
      "Bare {.val core} is ambiguous; use namespace shorthand such as {.val edr/core} or {.val common/core}."
    )
  }

  # Keep the package's long-standing `covjson` spelling useful even though
  # the EDR conformance-class URI uses `coveragejson`.
  if (identical(requested, "covjson")) requested <- "coveragejson"
  requested <- sub("/covjson$", "/coveragejson", requested)
  advertised <- sub("/covjson$", "/coveragejson", advertised)

  pieces <- strsplit(requested, "/", fixed = TRUE)[[1L]]
  if (length(pieces) == 2L && pieces[[1L]] %in% c("edr", "common")) {
    namespace <- pieces[[1L]]
    class_name <- pieces[[2L]]
    namespace_match <- if (identical(namespace, "edr")) {
      grepl("ogcapi[-_/]?edr|/edr[-_/]", advertised, perl = TRUE)
    } else {
      grepl("ogcapi[-_/]?common|/common[-_/]", advertised, perl = TRUE)
    }
    return(any(namespace_match & endsWith(advertised, paste0("/", class_name))))
  }
  if (length(pieces) > 1L) return(FALSE)
  any(endsWith(advertised, paste0("/", requested)))
}

has_edr_core_conformance <- function(advertised) {
  advertised <- tolower(sub("/+$", "", as.character(advertised)))
  any(
    grepl("ogcapi[-_/]?edr|/edr[-_/]", advertised, perl = TRUE) &
      endsWith(advertised, "/core")
  )
}

diagnostic_probe <- function(check, fetch, assess) {
  tryCatch(
    {
      value <- fetch()
      assessment <- assess(value)
      list(
        value = value,
        row = diagnostic_row(check, assessment$status, assessment$detail)
      )
    },
    error = function(e) list(
      value = NULL,
      row = diagnostic_row(check, "fail", conditionMessage(e))
    )
  )
}

assess_discovery_links <- function(landing) {
  links <- landing$links
  if (!is.list(links) || length(links) == 0L) {
    return(diagnostic_row("discovery links", "warn", "Landing page has no links."))
  }
  rels <- vapply(links, function(link) {
    if (is.list(link)) first_character(link$rel) else NA_character_
  }, character(1))
  hrefs <- vapply(links, function(link) {
    if (is.list(link)) first_character(link$href) else NA_character_
  }, character(1))
  has_collections <- any(tolower(rels) %in% c("data", "collections"), na.rm = TRUE) ||
    any(grepl("/collections(?:[?#]|$)", hrefs, perl = TRUE), na.rm = TRUE)
  has_conformance <- any(tolower(rels) == "conformance", na.rm = TRUE) ||
    any(grepl("/conformance(?:[?#]|$)", hrefs, perl = TRUE), na.rm = TRUE)
  missing <- c("collections"[!has_collections], "conformance"[!has_conformance])
  if (length(missing) == 0L) {
    diagnostic_row("discovery links", "pass", "Collections and conformance links are advertised.")
  } else {
    diagnostic_row(
      "discovery links", "warn",
      paste0("Missing expected link(s): ", paste(missing, collapse = ", "), ".")
    )
  }
}

assess_identifier_column <- function(value, check, unavailable) {
  if (is.null(value)) return(diagnostic_row(check, "skip", unavailable))
  if (!is.data.frame(value) || !"id" %in% names(value)) {
    return(diagnostic_row(check, "fail", "No id column was available."))
  }
  ids <- value$id
  if (any(is.na(ids) | !nzchar(ids))) {
    return(diagnostic_row(check, "fail", "One or more identifiers are missing."))
  }
  if (anyDuplicated(ids)) {
    return(diagnostic_row(check, "fail", "Identifiers are not unique."))
  }
  diagnostic_row(check, "pass", paste(length(ids), "unique identifier(s)."))
}

assess_membership <- function(value, id, check, noun) {
  if (is.null(value)) {
    return(diagnostic_row(check, "skip", paste(tools::toTitleCase(noun), "index was unavailable.")))
  }
  if (!is.data.frame(value) || !"id" %in% names(value)) {
    return(diagnostic_row(check, "skip", "No usable id column was available."))
  }
  if (id %in% value$id) {
    diagnostic_row(check, "pass", paste0("The ", noun, " is present in the index."))
  } else {
    diagnostic_row(check, "warn", paste0("The ", noun, " is not present in the index."))
  }
}

assess_detail_id <- function(value, expected, noun) {
  check_metadata_object(value, paste0(tools::toTitleCase(noun), " response"))
  actual <- first_character(value$id)
  if (is.na(actual)) {
    diagnostic_assessment("warn", paste(tools::toTitleCase(noun), "document has no id."))
  } else if (!identical(actual, expected)) {
    diagnostic_assessment(
      "warn",
      paste0("Requested '", expected, "' but document id is '", actual, "'.")
    )
  } else {
    diagnostic_assessment("pass", paste0("Loaded ", noun, " '", actual, "'."))
  }
}

diagnose_metadata_surface <- function(metadata) {
  checks <- c("query metadata", "query links", "parameter metadata", "format metadata")
  if (is.null(metadata)) {
    return(lapply(checks, function(check) {
      diagnostic_row(check, "skip", "Detailed metadata was unavailable.")
    }))
  }

  query_result <- tryCatch(
    list(value = query_capability_rows(metadata$data_queries %||% list()), error = NULL),
    error = function(e) list(value = NULL, error = conditionMessage(e))
  )
  query_row <- if (!is.null(query_result$error)) {
    diagnostic_row("query metadata", "fail", query_result$error)
  } else if (nrow(query_result$value) == 0L) {
    diagnostic_row("query metadata", "warn", "No EDR query types were advertised.")
  } else {
    diagnostic_row(
      "query metadata", "pass",
      paste0("Advertised: ", paste(query_result$value$query, collapse = ", "), ".")
    )
  }

  link_row <- if (is.null(query_result$value)) {
    diagnostic_row("query links", "skip", "Query metadata was unusable.")
  } else if (nrow(query_result$value) == 0L) {
    diagnostic_row("query links", "skip", "No query metadata was advertised.")
  } else {
    missing <- query_result$value$query[
      is.na(query_result$value$href) | !nzchar(query_result$value$href)
    ]
    if (length(missing) == 0L) {
      diagnostic_row("query links", "pass", "Every advertised query has a link.")
    } else {
      diagnostic_row(
        "query links", "warn",
        paste0("Missing query link(s): ", paste(missing, collapse = ", "), ".")
      )
    }
  }

  parameter_row <- tryCatch(
    {
      value <- parameters_tibble(metadata)
      if (nrow(value) == 0L) {
        diagnostic_row("parameter metadata", "warn", "No parameters were advertised.")
      } else {
        diagnostic_row("parameter metadata", "pass", paste(nrow(value), "parameter(s) parsed."))
      }
    },
    error = function(e) diagnostic_row("parameter metadata", "fail", conditionMessage(e))
  )

  format_row <- tryCatch(
    {
      summary <- collection_row(metadata)
      queries <- summary$query_details[[1L]]
      formats <- c(
        summary$output_formats[[1L]],
        if (nrow(queries) > 0L) unlist(queries$output_formats, use.names = FALSE),
        if (nrow(queries) > 0L) queries$default_output_format
      )
      formats <- unique(formats[!is.na(formats) & nzchar(formats)])
      if (length(formats) == 0L) {
        diagnostic_row("format metadata", "warn", "No output formats were advertised.")
      } else {
        diagnostic_row(
          "format metadata", "pass",
          paste0("Advertised: ", paste(formats, collapse = ", "), ".")
        )
      }
    },
    error = function(e) diagnostic_row("format metadata", "fail", conditionMessage(e))
  )
  list(query_row, link_row, parameter_row, format_row)
}

diagnostic_assessment <- function(status, detail) {
  list(status = status, detail = detail)
}

diagnostic_row <- function(check, status, detail) {
  tibble::tibble(check = check, status = status, detail = detail)
}
