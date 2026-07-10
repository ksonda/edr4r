#' Inspect an EDR service or collection's advertised capabilities
#'
#' `edr_capabilities()` gathers the metadata needed to plan requests without
#' probing data endpoints. With no `collection_id`, it combines the landing
#' page, conformance declaration, and collection index. With a collection id,
#' it retains query-specific formats, CRS details, distance units, parameter
#' metadata, extents, and the raw collection document.
#'
#' Discovery responses use the client's in-memory cache, so repeated calls do
#' not issue redundant requests until `cache_ttl` expires. Set `refresh = TRUE`
#' to bypass the cache or call [edr_cache_clear()].
#'
#' @param client An [edr_client()].
#' @param collection_id Optional collection identifier. Omit it for
#'   service-level capabilities.
#' @param refresh If `TRUE`, bypass and replace cached discovery metadata.
#'
#' @return An object of class `edr_capabilities`. Service capabilities contain
#'   `landing`, `conformance`, and `collections`; collection capabilities
#'   contain `collection`, `summary`, `queries`, `parameters`,
#'   `output_formats`, and `output_crs`.
#' @export
edr_capabilities <- function(client, collection_id = NULL, refresh = FALSE) {
  check_client(client)
  check_refresh(refresh)

  if (is.null(collection_id)) {
    return(structure(
      list(
        scope = "service",
        base_url = client$base_url,
        landing = edr_landing(client, refresh = refresh),
        conformance = edr_conformance(client, refresh = refresh),
        collections = edr_collections(client, refresh = refresh)
      ),
      class = c("edr_capabilities", "list")
    ))
  }

  collection_id <- check_collection_id(collection_id)
  collection <- edr_collection(client, collection_id, refresh = refresh)
  summary <- collection_row(collection)
  structure(
    list(
      scope = "collection",
      base_url = client$base_url,
      collection_id = collection_id,
      collection = collection,
      summary = summary,
      queries = query_capability_rows(collection$data_queries %||% list()),
      parameters = parameters_tibble(collection),
      output_formats = character_values(collection$output_formats),
      output_crs = character_values(collection$crs)
    ),
    class = c("edr_capabilities", "list")
  )
}

#' Test an advertised EDR capability
#'
#' Checks collection query types and encodings, or service conformance classes,
#' using discovery metadata only. Format matching recognizes common aliases
#' such as `"covjson"` / `"CoverageJSON"` and
#' `"geojson"` / `"application/geo+json"`.
#'
#' @param x An [edr_client()] or an `edr_capabilities` object.
#' @param collection_id Collection to inspect when `x` is a client. Required
#'   for `query` or `format` checks.
#' @param query Optional scalar query type, e.g. `"cube"` or `"position"`.
#' @param format Optional scalar output format. If `query` is supplied,
#'   query-specific formats take precedence over collection-level formats.
#' @param conformance Optional conformance URI or final URI component such as
#'   `"core"` or `"covjson"`.
#' @param refresh If `TRUE`, bypass and replace cached discovery metadata.
#'
#' @return A single logical value. When multiple criteria are supplied, all
#'   must be advertised.
#' @export
edr_supports <- function(x,
                         collection_id = NULL,
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
  query <- optional_scalar_string(query, "query")
  format <- optional_scalar_string(format, "format")
  conformance <- optional_scalar_string(conformance, "conformance")
  if (is.null(query) && is.null(format) && is.null(conformance)) {
    cli::cli_abort(
      "Supply at least one of {.arg query}, {.arg format}, or {.arg conformance}."
    )
  }

  checks <- logical()
  collection_caps <- NULL
  if (!is.null(query) || !is.null(format)) {
    collection_caps <- collection_capabilities(
      x, collection_id = collection_id, refresh = refresh
    )
  }

  if (!is.null(query)) {
    query_index <- match(tolower(query), tolower(collection_caps$queries$query))
    checks <- c(checks, !is.na(query_index))
  } else {
    query_index <- NA_integer_
  }

  if (!is.null(format)) {
    advertised <- character()
    if (!is.na(query_index)) {
      advertised <- collection_caps$queries$output_formats[[query_index]]
    }
    if (length(advertised) == 0L) {
      advertised <- collection_caps$output_formats
    }
    checks <- c(
      checks,
      normalize_format_name(format) %in%
        vapply(advertised, normalize_format_name, character(1))
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
#' Performs small, read-only metadata requests and reports each check instead
#' of stopping at the first failure. This is intended for onboarding a new or
#' partially conformant endpoint; it never issues a data query.
#'
#' @inheritParams edr_capabilities
#' @param refresh If `TRUE` (default), perform fresh probes. Set to `FALSE` to
#'   allow cached metadata to satisfy checks.
#'
#' @return A tibble with `check`, `status` (`"pass"`, `"warn"`, `"fail"`, or
#'   `"skip"`), and `detail` columns.
#' @export
edr_diagnose <- function(client, collection_id = NULL, refresh = TRUE) {
  check_client(client)
  check_refresh(refresh)
  if (!is.null(collection_id)) {
    collection_id <- check_collection_id(collection_id)
  }

  results <- list()
  landing <- diagnostic_probe(
    "landing",
    function() edr_landing(client, refresh = refresh),
    function(value) {
      if (!is.list(value)) return(diagnostic_assessment("fail", "Response is not a JSON object."))
      if (length(value$links %||% list()) == 0L) {
        return(diagnostic_assessment("warn", "Landing page has no links."))
      }
      diagnostic_assessment("pass", "Landing page is a linked JSON document.")
    }
  )
  results[[length(results) + 1L]] <- landing$row

  conformance <- diagnostic_probe(
    "conformance",
    function() edr_conformance(client, refresh = refresh),
    function(value) {
      if (length(value) == 0L) {
        diagnostic_assessment("warn", "No conformance classes were advertised.")
      } else {
        diagnostic_assessment(
          "pass",
          paste(length(value), "conformance class(es) advertised.")
        )
      }
    }
  )
  results[[length(results) + 1L]] <- conformance$row

  collections <- diagnostic_probe(
    "collections",
    function() edr_collections(client, refresh = refresh),
    function(value) {
      if (!is.data.frame(value)) {
        return(diagnostic_assessment("fail", "Collection index was not tabular."))
      }
      if (nrow(value) == 0L) {
        diagnostic_assessment("warn", "The service advertised no collections.")
      } else {
        diagnostic_assessment(
          "pass",
          paste(nrow(value), "collection(s) advertised.")
        )
      }
    }
  )
  results[[length(results) + 1L]] <- collections$row

  if (!is.null(collection_id)) {
    collection <- diagnostic_probe(
      "collection",
      function() edr_collection(client, collection_id, refresh = refresh),
      function(value) {
        actual <- first_character(value$id)
        if (is.na(actual)) {
          diagnostic_assessment("warn", "Collection document has no id.")
        } else if (!identical(actual, collection_id)) {
          diagnostic_assessment(
            "warn",
            paste0("Requested '", collection_id, "' but document id is '", actual, "'.")
          )
        } else {
          diagnostic_assessment("pass", paste0("Loaded collection '", actual, "'."))
        }
      }
    )
    results[[length(results) + 1L]] <- collection$row

    if (is.null(collection$value)) {
      query_row <- diagnostic_row(
        "query metadata", "skip", "Collection metadata was unavailable."
      )
    } else {
      query_row <- tryCatch(
        {
          queries <- query_capability_rows(
            collection$value$data_queries %||% list()
          )
          if (nrow(queries) == 0L) {
            diagnostic_row(
              "query metadata", "warn", "No EDR query types were advertised."
            )
          } else {
            diagnostic_row(
              "query metadata", "pass",
              paste0("Advertised: ", paste(queries$query, collapse = ", "), ".")
            )
          }
        },
        error = function(e) diagnostic_row(
          "query metadata", "fail", conditionMessage(e)
        )
      )
    }
    results[[length(results) + 1L]] <- query_row
  }

  vctrs::vec_rbind(!!!results)
}

#' @export
format.edr_capabilities <- function(x, ...) {
  if (identical(x$scope, "service")) {
    return(c(
      cli::format_inline("<edr_capabilities/service>"),
      cli::format_inline("  base_url: {x$base_url}"),
      cli::format_inline("  collections: {nrow(x$collections)}"),
      cli::format_inline("  conformance classes: {length(x$conformance)}")
    ))
  }
  c(
    cli::format_inline("<edr_capabilities/collection>"),
    cli::format_inline("  collection: {x$collection_id}"),
    cli::format_inline("  queries: {nrow(x$queries)}"),
    cli::format_inline("  parameters: {nrow(x$parameters)}"),
    cli::format_inline("  formats: {paste(x$output_formats, collapse = ', ')}")
  )
}

#' @export
print.edr_capabilities <- function(x, ...) {
  cat(format(x, ...), sep = "\n")
  invisible(x)
}

collection_capabilities <- function(x, collection_id, refresh) {
  if (inherits(x, "edr_capabilities")) {
    if (!identical(x$scope, "collection")) {
      cli::cli_abort(
        "A service-level {.cls edr_capabilities} object cannot answer collection checks."
      )
    }
    if (!is.null(collection_id) && !identical(collection_id, x$collection_id)) {
      cli::cli_abort(
        "{.arg collection_id} does not match the supplied capabilities object."
      )
    }
    return(x)
  }
  if (is.null(collection_id)) {
    cli::cli_abort(
      "{.arg collection_id} is required for {.arg query} or {.arg format} checks."
    )
  }
  edr_capabilities(x, collection_id = collection_id, refresh = refresh)
}

service_capabilities <- function(x, refresh) {
  if (inherits(x, "edr_capabilities")) {
    if (!identical(x$scope, "service")) {
      cli::cli_abort(
        "A collection-level {.cls edr_capabilities} object cannot answer conformance checks."
      )
    }
    return(x)
  }
  edr_capabilities(x, refresh = refresh)
}

optional_scalar_string <- function(x, arg, call = rlang::caller_env()) {
  if (is.null(x)) return(NULL)
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(x)) {
    cli::cli_abort(
      "{.arg {arg}} must be a single non-empty string.",
      call = call
    )
  }
  x
}

normalize_format_name <- function(x) {
  key <- tolower(gsub("[^[:alnum:]+]", "", x))
  if (key %in% c(
    "covjson", "coveragejson", "applicationprscoverage+json",
    "applicationcoverage+json"
  )) return("covjson")
  if (key %in% c("geojson", "applicationgeo+json")) return("geojson")
  if (key %in% c("json", "applicationjson")) return("json")
  if (key %in% c("csv", "textcsv")) return("csv")
  key
}

conformance_is_advertised <- function(requested, advertised) {
  requested <- tolower(sub("/+$", "", requested))
  advertised <- tolower(sub("/+$", "", as.character(advertised)))
  if (grepl("/", requested, fixed = TRUE)) {
    return(requested %in% advertised)
  }
  any(vapply(
    strsplit(advertised, "/", fixed = TRUE),
    function(parts) length(parts) > 0L && identical(tail(parts, 1L), requested),
    logical(1)
  ))
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

diagnostic_assessment <- function(status, detail) {
  list(status = status, detail = detail)
}

diagnostic_row <- function(check, status, detail) {
  tibble::tibble(check = check, status = status, detail = detail)
}
