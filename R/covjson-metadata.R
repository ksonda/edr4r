# Internal helpers for metadata attached to tidy CoverageJSON rows.

empty_covjson_coverage_metadata <- function() {
  tibble::tibble(
    coverage_index = integer(),
    coverage_id = character(),
    domain_type = character(),
    axis_names = list(),
    coordinate_names = list(),
    axes = list(),
    referencing = list()
  )
}

new_covjson_metadata <- function(coverages = empty_covjson_coverage_metadata()) {
  list(
    version = 1L,
    coverages = coverages
  )
}

get_covjson_metadata <- function(x) {
  attr(x, "edr_covjson_metadata", exact = TRUE)
}

set_covjson_metadata <- function(x, metadata) {
  if (!is.null(metadata)) {
    attr(x, "edr_covjson_metadata") <- metadata
  }
  x
}

covjson_coordinate_column <- function(coordinate_name) {
  switch(
    coordinate_name,
    t = "datetime",
    x = "x",
    y = "y",
    z = "z",
    paste0(".axis_", coordinate_name)
  )
}

covjson_coverage_metadata_row <- function(domain, coverage_id, coverage_index) {
  tibble::tibble(
    coverage_index = as.integer(coverage_index),
    coverage_id = as.character(coverage_id),
    domain_type = domain$domain_type,
    axis_names = list(names(domain$axes)),
    coordinate_names = list(names(domain$coordinates)),
    axes = list(domain$axis_details),
    referencing = list(domain$referencing)
  )
}

bind_covjson_metadata <- function(pieces) {
  metadata <- lapply(pieces, get_covjson_metadata)
  metadata <- metadata[!vapply(metadata, is.null, logical(1))]
  if (length(metadata) == 0L) return(NULL)

  versions <- vapply(metadata, function(x) x$version, integer(1))
  if (any(versions != 1L)) {
    cli::cli_abort("Unsupported internal CoverageJSON metadata version.")
  }
  rows <- lapply(metadata, `[[`, "coverages")
  new_covjson_metadata(vctrs::vec_rbind(!!!rows))
}

restore_covjson_metadata <- function(x, pieces) {
  set_covjson_metadata(x, bind_covjson_metadata(pieces))
}

add_covjson_metadata_provenance <- function(x, ...) {
  metadata <- get_covjson_metadata(x)
  if (is.null(metadata)) return(x)

  values <- list(...)
  if (length(values) == 0L) return(x)
  if (is.null(names(values)) || any(!nzchar(names(values)))) {
    cli::cli_abort("Internal CoverageJSON provenance columns must be named.")
  }

  rows <- metadata$coverages
  for (column in rev(names(values))) {
    value <- values[[column]]
    if (length(value) != 1L) {
      cli::cli_abort("Internal CoverageJSON provenance values must be scalar.")
    }
    repeated <- rep(value, nrow(rows))
    if (column %in% names(rows)) {
      rows[[column]] <- repeated
    } else {
      rows <- rlang::exec(
        tibble::add_column,
        rows,
        !!!stats::setNames(list(repeated), column),
        .before = 1L
      )
    }
  }
  metadata$coverages <- rows
  set_covjson_metadata(x, metadata)
}

covjson_conflicting_columns <- function(pieces) {
  columns <- unique(unlist(lapply(pieces, names), use.names = FALSE))
  columns[vapply(columns, function(column) {
    values <- lapply(pieces, function(piece) {
      if (column %in% names(piece)) piece[[column]] else NULL
    })
    values <- values[!vapply(values, is.null, logical(1))]
    inherits(
      tryCatch(
        vctrs::vec_ptype_common(!!!values),
        error = function(e) e
      ),
      "error"
    )
  }, logical(1))]
}

covjson_column_is_castable <- function(column, pieces) {
  values <- lapply(pieces, function(piece) {
    if (column %in% names(piece)) piece[[column]] else NULL
  })
  values <- values[!vapply(values, is.null, logical(1))]
  all(vapply(
    values,
    function(value) is.atomic(value) && is.null(dim(value)),
    logical(1)
  ))
}

bind_covjson_tibbles <- function(pieces) {
  pieces <- pieces[!vapply(pieces, is.null, logical(1))]
  if (length(pieces) == 0L) return(empty_covjson_tibble())
  if (length(pieces) == 1L) return(pieces[[1L]])

  original_pieces <- pieces
  candidate <- tryCatch(
    vctrs::vec_rbind(!!!pieces),
    error = function(e) e
  )
  if (inherits(candidate, "error")) {
    conflicts <- covjson_conflicting_columns(pieces)
    custom_conflicts <- conflicts[startsWith(conflicts, ".axis_")]
    if (length(conflicts) == 0L ||
        !setequal(conflicts, custom_conflicts) ||
        !all(vapply(
          custom_conflicts,
          covjson_column_is_castable,
          logical(1),
          pieces = pieces
        ))) {
      rlang::cnd_signal(candidate)
    }

    for (column in custom_conflicts) {
      pieces <- lapply(pieces, function(piece) {
        if (column %in% names(piece)) {
          piece[[column]] <- as.character(piece[[column]])
        }
        piece
      })
    }
    cli::cli_warn(
      "Demoted custom CoverageJSON coordinate column{?s} to character: {.field {custom_conflicts}}; coordinate types differed across coverages."
    )
    candidate <- vctrs::vec_rbind(!!!pieces)
  }

  restore_covjson_metadata(candidate, original_pieces)
}

covjson_axis_columns <- function(data, varying = FALSE) {
  columns <- names(data)[startsWith(names(data), ".axis_")]
  if (isTRUE(varying)) {
    columns <- columns[vapply(
      columns,
      function(column) n_present_unique(data[[column]]) > 1L,
      logical(1)
    )]
  }
  columns
}

covjson_axis_label <- function(data, column) {
  metadata <- get_covjson_metadata(data)
  if (!is.null(metadata) && nrow(metadata$coverages) > 0L) {
    details <- metadata$coverages$axes
    labels <- unique(unlist(lapply(details, function(x) {
      if (!is.data.frame(x) || !all(c("coordinate_name", "column_name") %in% names(x))) {
        return(character())
      }
      as.character(x$coordinate_name[x$column_name == column])
    }), use.names = FALSE))
    labels <- labels[!is.na(labels) & nzchar(labels)]
    if (length(labels) == 1L) return(labels[[1L]])
  }
  sub("^\\.axis_", "", column)
}

covjson_scalar_character <- function(x) {
  if (!is.character(x) || length(x) == 0L || is.na(x[[1L]]) ||
      !nzchar(x[[1L]])) {
    return(NA_character_)
  }
  as.character(x[[1L]])
}

covjson_reference_connections <- function(referencing) {
  if (is.null(referencing) || length(referencing) == 0L) return(list())
  if (!is.list(referencing)) return(list(structure(
    list(),
    edr_malformed = TRUE
  )))
  if (all(c("coordinates", "system") %in% names(referencing))) {
    return(list(referencing))
  }
  unname(referencing)
}

covjson_horizontal_reference <- function(referencing) {
  connections <- covjson_reference_connections(referencing)
  relevant <- lapply(connections, function(connection) {
    if (!is.list(connection) || isTRUE(attr(connection, "edr_malformed"))) {
      return(list(status = "unknown", type = NA_character_, id = NA_character_))
    }
    coordinates <- unlist(connection$coordinates, use.names = FALSE)
    if (!is.character(coordinates) || anyNA(coordinates)) {
      return(list(status = "unknown", type = NA_character_, id = NA_character_))
    }
    if (!any(coordinates %in% c("x", "y"))) return(NULL)
    if (!all(c("x", "y") %in% coordinates)) {
      return(list(status = "unknown", type = NA_character_, id = NA_character_))
    }
    system <- connection$system
    if (!is.list(system)) {
      return(list(status = "unknown", type = NA_character_, id = NA_character_))
    }
    type <- covjson_scalar_character(system$type)
    id <- covjson_scalar_character(system$id)
    type_key <- if (is.na(type)) "" else type
    status <- switch(
      type_key,
      GeographicCRS = "geographic",
      ProjectedCRS = "projected",
      "unknown"
    )
    list(status = status, type = type, id = id)
  })
  relevant <- relevant[!vapply(relevant, is.null, logical(1))]
  if (length(relevant) == 0L) {
    return(list(status = "missing", type = NA_character_, id = NA_character_))
  }
  signatures <- unique(vapply(relevant, function(x) {
    paste(x$status, x$type %||% "", x$id %||% "", sep = "\r")
  }, character(1)))
  if (length(signatures) > 1L) {
    return(list(status = "ambiguous", type = NA_character_, id = NA_character_))
  }
  relevant[[1L]]
}

covjson_horizontal_references <- function(data) {
  metadata <- get_covjson_metadata(data)
  if (is.null(metadata)) return(NULL)
  coverages <- covjson_metadata_rows_for_data(data, metadata$coverages)
  if (nrow(coverages) == 0L) return(list())
  lapply(seq_len(nrow(coverages)), function(i) {
    reference <- covjson_horizontal_reference(coverages$referencing[[i]])
    reference$coverage_id <- coverages$coverage_id[[i]]
    reference
  })
}

covjson_metadata_rows_for_data <- function(data, coverages) {
  keys <- intersect(
    c(".request_id", ".location_id", "coverage_id"),
    intersect(names(data), names(coverages))
  )
  if (length(keys) == 0L) return(coverages)
  if (nrow(data) == 0L) return(coverages[0, , drop = FALSE])

  data_keys <- vctrs::vec_unique(tibble::as_tibble(data[keys]))
  metadata_keys <- tibble::as_tibble(coverages[keys])
  keep <- !is.na(vctrs::vec_match(metadata_keys, data_keys))
  coverages[keep, , drop = FALSE]
}

trim_covjson_metadata <- function(data) {
  metadata <- get_covjson_metadata(data)
  if (is.null(metadata)) return(data)
  metadata$coverages <- covjson_metadata_rows_for_data(
    data,
    metadata$coverages
  )
  set_covjson_metadata(data, metadata)
}

canonical_covjson_horizontal_crs <- function(reference) {
  id <- reference$id
  if (identical(reference$status, "geographic") && !is.na(id) && grepl(
    "(?:CRS84h?|EPSG(?:(?:/0)?/|:{1,2})(?:4326|4979))$",
    id,
    ignore.case = TRUE,
    perl = TRUE
  )) {
    return("WGS84")
  }
  paste(reference$status, reference$type %||% "", id %||% "", sep = "|")
}

check_covjson_crs_consistency <- function(data, map = FALSE,
                                          call = rlang::caller_env()) {
  references <- covjson_horizontal_references(data)
  if (is.null(references) || length(references) == 0L) return(invisible(NULL))

  statuses <- vapply(references, `[[`, character(1), "status")
  if (isTRUE(map) && any(statuses == "projected")) {
    projected <- references[statuses == "projected"]
    ids <- unique(vapply(projected, function(x) {
      if (is.na(x$id)) "unknown" else x$id
    }, character(1)))
    cli::cli_abort(
      c(
        "Coverage coordinates use a projected CRS and cannot be sent to Leaflet as longitude/latitude.",
        "x" = "Projected CRS{?es}: {.val {ids}}",
        "i" = "Request a geographic response such as {.code crs = \"CRS84\"} or transform complete grid-cell geometry before mapping."
      ),
      class = "edr_map_crs_error",
      call = call
    )
  }
  unsupported_geographic <- statuses == "geographic" & vapply(
    references,
    canonical_covjson_horizontal_crs,
    character(1)
  ) != "WGS84" & !is.na(vapply(references, `[[`, character(1), "id"))
  if (isTRUE(map) && any(unsupported_geographic)) {
    ids <- unique(vapply(references[unsupported_geographic], `[[`,
                         character(1), "id"))
    cli::cli_abort(
      c(
        "Coverage coordinates use a geographic CRS that is not recognized as WGS 84/CRS84 for Leaflet.",
        "x" = "Geographic CRS{?es}: {.val {ids}}",
        "i" = "Request a response in CRS84 or EPSG:4326 before mapping."
      ),
      class = "edr_map_crs_error",
      call = call
    )
  }
  if (any(statuses == "ambiguous")) {
    cli::cli_abort(
      "Coverage metadata defines conflicting horizontal reference systems.",
      class = "edr_map_crs_error",
      call = call
    )
  }

  known <- references[statuses %in% c("geographic", "projected")]
  signatures <- unique(vapply(
    known,
    canonical_covjson_horizontal_crs,
    character(1)
  ))
  if (length(signatures) > 1L) {
    cli::cli_abort(
      "Coverage rows combine distinct horizontal coordinate reference systems.",
      class = "edr_map_crs_error",
      call = call
    )
  }

  missing_geographic_id <- statuses == "geographic" & vapply(
    references,
    function(x) is.na(x$id),
    logical(1)
  )
  if (isTRUE(map) &&
      any(statuses %in% c("missing", "unknown") | missing_geographic_id)) {
    cli::cli_warn(
      c(
        "CoverageJSON does not provide one unambiguous horizontal CRS for every mapped coverage.",
        "i" = "Coordinates are being treated as longitude/latitude only after range validation."
      ),
      class = "edr_map_crs_warning"
    )
  }
  invisible(references)
}

check_leaflet_coordinate_ranges <- function(data, mode,
                                            call = rlang::caller_env()) {
  x_columns <- "x"
  y_columns <- "y"
  if (identical(mode, "grid")) {
    x_columns <- c(x_columns, ".edr_xmin", ".edr_xmax")
    y_columns <- c(y_columns, ".edr_ymin", ".edr_ymax")
  }
  x <- unlist(lapply(x_columns, function(column) data[[column]]), use.names = FALSE)
  y <- unlist(lapply(y_columns, function(column) data[[column]]), use.names = FALSE)
  x <- suppressWarnings(as.numeric(x))
  y <- suppressWarnings(as.numeric(y))
  if (length(x) == 0L || length(y) == 0L || any(!is.finite(x)) ||
      any(!is.finite(y))) {
    cli::cli_abort(
      "Coverage map coordinates and grid bounds must be finite numbers.",
      class = "edr_map_crs_error",
      call = call
    )
  }
  if (any(x < -180 | x > 180) || any(y < -90 | y > 90)) {
    cli::cli_abort(
      c(
        "Coverage map coordinates fall outside longitude/latitude bounds.",
        "i" = "Leaflet requires longitude in [-180, 180] and latitude in [-90, 90].",
        "i" = "Request a geographic CRS or transform complete coverage geometry before mapping."
      ),
      class = "edr_map_crs_error",
      call = call
    )
  }
  invisible(data)
}
