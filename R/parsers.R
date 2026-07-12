#' Convert a CoverageJSON response to a tidy tibble
#'
#' Flattens a CoverageJSON `Coverage` or `CoverageCollection` into a
#' long tibble with one row per (coverage, parameter, domain position).
#' Handles primitive, regularly spaced, and composite tuple axes, including
#' the axes used by `Grid`, `PointSeries`, `MultiPointSeries`, and `Trajectory`
#' domains. Additional coordinate dimensions are appended as `.axis_*`
#' columns. Inline `NdArray` ranges are validated before they are flattened.
#'
#' @param x A CoverageJSON object: either an `edr_response` returned by
#'   [edr_location()] / [edr_area()] / [edr_cube()] (etc.) with
#'   `format = "covjson"`, or the raw parsed list.
#' @param datetime_as_posix If `TRUE` (default), attempts to parse the
#'   time axis to `POSIXct` (UTC). Falls back to character on failure.
#'
#' @return A tibble whose first columns are `coverage_id`, `parameter`,
#'   `parameter_label`, `unit`, `datetime`, `x`, `y`, `z`, and `value`.
#'   Columns that are absent from the source are filled with `NA`. Nonstandard
#'   CoverageJSON coordinates are appended without changing row cardinality,
#'   using names such as `.axis_realisations`. The tibble carries an
#'   `edr_covjson_metadata` attribute with versioned, per-coverage domain,
#'   axis, and effective referencing metadata.
#' @export
covjson_to_tibble <- function(x, datetime_as_posix = TRUE) {
  cov <- as_covjson(x)
  type <- cov$type %||% ""

  coverages <- switch(type,
    CoverageCollection = cov$coverages %||% list(),
    Coverage           = list(cov),
    # Some servers omit type; infer.
    if (!is.null(cov$coverages)) cov$coverages
    else if (!is.null(cov$domain)) list(cov)
    else cli::cli_abort("Input does not look like CoverageJSON (no coverages/domain).")
  )

  params <- cov$parameters %||% list()
  if (!is.list(params)) {
    cli::cli_abort("CoverageJSON {.field parameters} must be an object.")
  }
  if (length(coverages) == 0L) {
    return(set_covjson_metadata(
      empty_covjson_tibble(),
      new_covjson_metadata()
    ))
  }

  is_collection <- identical(type, "CoverageCollection") ||
    !is.null(cov$coverages)
  collection_domain_type <- if (is_collection) {
    cov$domainType
  } else {
    NULL
  }
  collection_referencing <- if (is_collection) {
    cov$referencing
  } else {
    NULL
  }

  per_cov <- purrr::map2(coverages, seq_along(coverages), function(cvg, i) {
    if (!is.list(cvg)) {
      cli::cli_abort(
        "Coverage {i} is external or malformed; only inline Coverage objects are supported."
      )
    }
    cid <- coverage_id(cvg, i)
    one_coverage(
      cvg,
      params,
      coverage_id = cid,
      coverage_index = i,
      inherited_domain_type = collection_domain_type,
      inherited_referencing = collection_referencing
    )
  })

  # Names of parameters demoted from numeric to character inside each
  # coverage (attached by one_coverage()).
  demoted <- unique(unlist(
    lapply(per_cov, attr, "edr_demoted"), use.names = FALSE
  ))

  # Outer reconciliation across coverages. When one coverage's `value`
  # column is numeric and another's is character (same response, possibly
  # different ranges of the same parameter), vec_rbind would fail with a
  # type-mismatch error. Cast numerics to character before binding, and
  # name any parameters that get demoted as a result.
  if (length(per_cov) > 1L) {
    types <- vapply(per_cov, function(t) typeof(t$value), character(1))
    if (length(unique(types)) > 1L) {
      forced <- unique(unlist(
        lapply(per_cov[types != "character"],
               function(t) unique(as.character(t$parameter))),
        use.names = FALSE
      ))
      demoted <- unique(c(demoted, forced))
      per_cov <- lapply(per_cov, function(t) {
        if (!is.character(t$value)) t$value <- as.character(t$value)
        t
      })
    }
  }

  out <- bind_covjson_tibbles(per_cov)

  if (length(demoted) > 0L) {
    cli::cli_warn(
      "Demoted to character: {.field {demoted}}; some values were non-numeric."
    )
  }

  if (isTRUE(datetime_as_posix) && "datetime" %in% names(out)) {
    out$datetime <- parse_datetime(out$datetime)
  }
  out
}

#' Convert a GeoJSON EDR response to an `sf` object
#'
#' @param x An `edr_response` wrapping GeoJSON (e.g. from
#'   [edr_locations()]) or a raw parsed GeoJSON list.
#' @return An `sf` object. Requires the `sf` package. If `sf` is not
#'   installed, returns a tibble of feature properties (without geometry)
#'   and warns.
#' @export
geojson_to_sf <- function(x) {
  pagination <- attr(x, "edr_pagination", exact = TRUE)
  gj <- as_geojson(x)

  if (!rlang::is_installed("sf")) {
    cli::cli_warn(
      "{.pkg sf} is not installed; returning properties without geometry."
    )
    return(restore_pagination_metadata(geojson_props_tibble(gj), pagination))
  }

  txt <- jsonlite::toJSON(gj, auto_unbox = TRUE, null = "null", digits = NA)
  res <- tryCatch(
    sf::read_sf(txt, quiet = TRUE),
    error = function(e) NULL
  )
  if (is.null(res)) {
    cli::cli_warn(
      "Could not parse GeoJSON geometry; returning properties only."
    )
    return(restore_pagination_metadata(geojson_props_tibble(gj), pagination))
  }
  out <- tibble::as_tibble(res) |> sf::st_as_sf()
  restore_pagination_metadata(out, pagination)
}

restore_pagination_metadata <- function(x, pagination) {
  if (!is.null(pagination)) {
    attr(x, "edr_pagination") <- pagination
  }
  x
}

# ---------------------------------------------------------------------
# CoverageJSON internals

as_covjson <- function(x) {
  if (inherits(x, "edr_covjson")) return(x$covjson)
  if (is.list(x) && !is.null(x$covjson)) return(x$covjson)
  if (is.list(x)) return(x)
  cli::cli_abort("Cannot interpret {.arg x} as CoverageJSON.")
}

coverage_id <- function(cvg, i) {
  cvg[["id"]] %||% cvg[["dct:identifier"]] %||%
    (cvg$properties %||% list())[["id"]] %||% as.character(i)
}

one_coverage <- function(cvg,
                         params,
                         coverage_id,
                         coverage_index,
                         inherited_domain_type = NULL,
                         inherited_referencing = NULL) {
  ranges <- cvg$ranges %||% list()

  params <- merge_coverage_parameters(
    params,
    cvg$parameters %||% list(),
    coverage_id
  )
  coverage_domain_type <- cvg$domainType %||% inherited_domain_type
  coverage_referencing <- if (!is.null(cvg$referencing)) {
    cvg$referencing
  } else {
    inherited_referencing
  }
  domain <- normalize_covjson_domain(
    cvg$domain,
    coverage_id,
    inherited_domain_type = coverage_domain_type,
    inherited_referencing = coverage_referencing
  )
  metadata <- new_covjson_metadata(covjson_coverage_metadata_row(
    domain,
    coverage_id = coverage_id,
    coverage_index = coverage_index
  ))
  if (length(ranges) == 0L) {
    return(set_covjson_metadata(empty_covjson_tibble(), metadata))
  }

  rows <- purrr::imap(ranges, function(rng, pname) {
    range_to_rows(rng, pname, domain, params, coverage_id)
  })

  # Reconcile `value` types across parameter ranges in this coverage.
  # Constant-time on the happy path: we read column type tags only, never
  # touch the values themselves. When numeric and character coexist (e.g.
  # numeric `storage` next to a categorical `qa_flag`), demote everyone to
  # character and remember which parameters started numeric so the
  # top-level call can name them in a single warning.
  types <- vapply(rows, function(r) typeof(r$value), character(1))
  demoted <- unique(unlist(
    lapply(rows, attr, "edr_demoted"), use.names = FALSE
  ))
  if (length(unique(types)) > 1L) {
    demoted <- unique(c(demoted, names(rows)[types != "character"]))
    rows <- lapply(rows, function(r) {
      if (!is.character(r$value)) r$value <- as.character(r$value)
      r
    })
  }

  out <- vctrs::vec_rbind(!!!rows)
  attr(out, "edr_demoted") <- demoted
  set_covjson_metadata(out, metadata)
}

merge_coverage_parameters <- function(parent, child, coverage_id) {
  if (!is.list(child)) {
    cli::cli_abort(
      "Coverage {.val {coverage_id}} has malformed {.field parameters}; expected an object."
    )
  }
  if (length(child) == 0L) return(parent)
  if (is.null(names(child)) || any(!nzchar(names(child)))) {
    cli::cli_abort(
      "Coverage {.val {coverage_id}} has unnamed parameter metadata."
    )
  }
  for (parameter_name in names(child)) {
    inherited <- parent[[parameter_name]]
    replacement <- child[[parameter_name]]
    if (is.list(inherited) && is.list(replacement)) {
      parent[[parameter_name]] <- utils::modifyList(
        inherited,
        replacement,
        keep.null = TRUE
      )
    } else {
      parent[parameter_name] <- child[parameter_name]
    }
  }
  parent
}

normalize_covjson_domain <- function(domain,
                                     coverage_id,
                                     inherited_domain_type = NULL,
                                     inherited_referencing = NULL) {
  if (is.character(domain)) {
    cli::cli_abort(
      "Coverage {.val {coverage_id}} uses an external domain; external CoverageJSON domains are not supported."
    )
  }
  if (is.null(domain) || !is.list(domain)) {
    cli::cli_abort(
      "Coverage {.val {coverage_id}} has no inline CoverageJSON domain."
    )
  }
  if (!is.null(domain$type) && !identical(domain$type, "Domain")) {
    cli::cli_abort(
      "Coverage {.val {coverage_id}} has domain type {.val {domain$type}}; expected {.val Domain}."
    )
  }

  axes <- domain$axes
  if (is.null(axes) || !is.list(axes) || length(axes) == 0L ||
      is.null(names(axes)) || any(!nzchar(names(axes)))) {
    cli::cli_abort(
      "Coverage {.val {coverage_id}} domain must contain named axes."
    )
  }

  normalized_axes <- lapply(names(axes), function(axis_name) {
    normalize_covjson_axis(axes[[axis_name]], axis_name, coverage_id)
  })
  names(normalized_axes) <- names(axes)

  coordinates <- list()
  for (axis_name in names(normalized_axes)) {
    axis <- normalized_axes[[axis_name]]
    for (coordinate_name in names(axis$coordinates)) {
      if (!is.null(coordinates[[coordinate_name]])) {
        cli::cli_abort(
          "Coverage {.val {coverage_id}} defines coordinate {.val {coordinate_name}} on more than one axis."
        )
      }
      coordinates[[coordinate_name]] <- list(
        axis = axis_name,
        values = axis$coordinates[[coordinate_name]]
      )
    }
  }

  axis_details <- vctrs::vec_rbind(!!!Map(
    function(axis, axis_name) {
      coordinate_names <- names(axis$coordinates)
      tibble::tibble(
        axis_name = rep(axis_name, length(coordinate_names)),
        coordinate_name = coordinate_names,
        column_name = unname(vapply(
          coordinate_names,
          covjson_coordinate_column,
          character(1)
        )),
        data_type = rep(axis$data_type, length(coordinate_names)),
        size = rep(as.integer(axis$size), length(coordinate_names))
      )
    },
    normalized_axes,
    names(normalized_axes)
  ))

  domain_type <- domain$domainType %||% inherited_domain_type
  if (!is.character(domain_type) || length(domain_type) != 1L ||
      is.na(domain_type)) {
    domain_type <- NA_character_
  }
  referencing <- if (!is.null(domain$referencing)) {
    domain$referencing
  } else {
    inherited_referencing %||% list()
  }

  list(
    axes = normalized_axes,
    coordinates = coordinates,
    axis_details = axis_details,
    domain_type = domain_type,
    referencing = referencing
  )
}

normalize_covjson_axis <- function(ax, axis_name, coverage_id) {
  if (!is.list(ax)) {
    cli::cli_abort(
      "Axis {.val {axis_name}} in coverage {.val {coverage_id}} must be an inline axis object."
    )
  }

  data_type <- ax$dataType %||% "primitive"
  if (!is.character(data_type) || length(data_type) != 1L || is.na(data_type)) {
    cli::cli_abort(
      "Axis {.val {axis_name}} in coverage {.val {coverage_id}} has an invalid {.field dataType}."
    )
  }

  has_values <- !is.null(ax$values)
  regular_members <- c("start", "stop", "num")
  has_any_regular <- any(vapply(regular_members, function(x) !is.null(ax[[x]]), logical(1)))
  has_all_regular <- all(vapply(regular_members, function(x) !is.null(ax[[x]]), logical(1)))

  if (has_values && has_any_regular) {
    cli::cli_abort(
      "Axis {.val {axis_name}} in coverage {.val {coverage_id}} cannot contain both {.field values} and regular-axis members."
    )
  }
  if (!has_values && !has_all_regular) {
    cli::cli_abort(
      "Axis {.val {axis_name}} in coverage {.val {coverage_id}} must contain {.field values} or all of {.field start}, {.field stop}, and {.field num}."
    )
  }

  if (identical(data_type, "polygon")) {
    cli::cli_abort(
      "Axis {.val {axis_name}} uses polygon values, which cannot be represented by {.fn covjson_to_tibble}."
    )
  }
  if (!data_type %in% c("primitive", "tuple")) {
    cli::cli_abort(
      "Axis {.val {axis_name}} in coverage {.val {coverage_id}} has unsupported {.field dataType} {.val {data_type}}."
    )
  }

  coordinate_names <- normalize_axis_coordinates(
    ax$coordinates,
    default = axis_name,
    axis_name = axis_name,
    coverage_id = coverage_id
  )

  if (identical(data_type, "primitive")) {
    if (length(coordinate_names) != 1L) {
      cli::cli_abort(
        "Primitive axis {.val {axis_name}} in coverage {.val {coverage_id}} must define exactly one coordinate."
      )
    }
    values <- if (has_values) {
      flatten_axis_values(ax$values, axis_name, coverage_id)
    } else {
      materialize_axis_values(ax, axis_name, coverage_id)
    }
    return(list(
      size = length(values),
      coordinates = stats::setNames(list(values), coordinate_names),
      data_type = data_type
    ))
  }

  if (!has_values) {
    cli::cli_abort(
      "Tuple axis {.val {axis_name}} in coverage {.val {coverage_id}} must use explicit {.field values}."
    )
  }
  if (is.null(ax$coordinates)) {
    cli::cli_abort(
      "Tuple axis {.val {axis_name}} in coverage {.val {coverage_id}} must define {.field coordinates}."
    )
  }

  tuple_values <- ax$values
  if (!is.list(tuple_values) || length(tuple_values) == 0L) {
    cli::cli_abort(
      "Tuple axis {.val {axis_name}} in coverage {.val {coverage_id}} must contain a non-empty array of tuples."
    )
  }
  tuple_size <- length(coordinate_names)
  valid_tuple <- vapply(tuple_values, function(tuple) {
    if (!is.list(tuple) && !is.atomic(tuple)) return(FALSE)
    if (length(tuple) != tuple_size) return(FALSE)
    all(vapply(tuple, is_axis_primitive, logical(1)))
  }, logical(1))
  if (any(!valid_tuple)) {
    bad <- which(!valid_tuple)[[1]]
    cli::cli_abort(
      "Tuple {bad} on axis {.val {axis_name}} in coverage {.val {coverage_id}} does not match its {tuple_size} coordinates."
    )
  }

  coordinate_values <- lapply(seq_len(tuple_size), function(i) {
    unlist(lapply(tuple_values, `[[`, i), use.names = FALSE)
  })
  names(coordinate_values) <- coordinate_names
  list(
    size = length(tuple_values),
    coordinates = coordinate_values,
    data_type = data_type
  )
}

normalize_axis_coordinates <- function(x, default, axis_name, coverage_id) {
  if (is.null(x)) return(default)
  coordinates <- unlist(x, use.names = FALSE)
  if (!is.character(coordinates) || length(coordinates) == 0L ||
      anyNA(coordinates) || any(!nzchar(coordinates)) || anyDuplicated(coordinates)) {
    cli::cli_abort(
      "Axis {.val {axis_name}} in coverage {.val {coverage_id}} has invalid {.field coordinates}."
    )
  }
  coordinates
}

is_axis_primitive <- function(x) {
  length(x) == 1L && !is.null(x) && !is.list(x) &&
    (is.character(x) || (is.numeric(x) && !is.logical(x))) && !is.na(x)
}

flatten_axis_values <- function(values, axis_name, coverage_id) {
  if (!is.list(values) && !is.atomic(values)) {
    cli::cli_abort(
      "Axis {.val {axis_name}} in coverage {.val {coverage_id}} has malformed {.field values}."
    )
  }
  if (length(values) == 0L) {
    cli::cli_abort(
      "Axis {.val {axis_name}} in coverage {.val {coverage_id}} must contain at least one value."
    )
  }
  pieces <- if (is.list(values)) values else as.list(values)
  if (!all(vapply(pieces, is_axis_primitive, logical(1)))) {
    cli::cli_abort(
      "Axis {.val {axis_name}} in coverage {.val {coverage_id}} must contain only scalar number or string values."
    )
  }
  unlist(pieces, use.names = FALSE)
}

materialize_axis_values <- function(ax, axis_name, coverage_id) {
  read_number <- function(member) {
    value <- ax[[member]]
    if (is.list(value)) value <- unlist(value, use.names = FALSE)
    if (!is.numeric(value) || is.logical(value) || length(value) != 1L ||
        is.na(value) || !is.finite(value)) {
      cli::cli_abort(
        "Regular axis {.val {axis_name}} in coverage {.val {coverage_id}} has invalid {.field {member}}."
      )
    }
    as.numeric(value)
  }

  start <- read_number("start")
  stop <- read_number("stop")
  raw_num <- read_number("num")
  if (raw_num != floor(raw_num) || raw_num < 1) {
    cli::cli_abort(
      "Regular axis {.val {axis_name}} in coverage {.val {coverage_id}} requires {.field num} to be a positive integer."
    )
  }
  n <- as.integer(raw_num)
  if (n == 1L && !isTRUE(all.equal(start, stop))) {
    cli::cli_abort(
      "Regular axis {.val {axis_name}} in coverage {.val {coverage_id}} requires equal {.field start} and {.field stop} when {.field num} is 1."
    )
  }
  if (n == 1L) return(start)
  seq(start, stop, length.out = n)
}

range_to_rows <- function(rng, pname, domain, params, coverage_id) {
  normalized <- normalize_ndarray(rng, pname, domain$axes, coverage_id)
  values <- normalized$values
  axis_names <- normalized$axis_names

  # Build the coordinate grid aligned to `values` (row-major: last axis
  # varies fastest), for the axes this range actually spans.
  if (length(axis_names) == 0L) {
    grid <- data.frame(.dummy = 1L)
    grid$.dummy <- NULL
  } else {
    spanned <- lapply(axis_names, function(a) seq_len(domain$axes[[a]]$size))
    names(spanned) <- axis_names
    # expand.grid varies the first column fastest; reverse so the last
    # axisName (which varies fastest in CovJSON) lines up, then reorder.
    g <- expand.grid(rev(spanned), KEEP.OUT.ATTRS = FALSE)
    names(g) <- rev(axis_names)
    grid <- g[, axis_names, drop = FALSE]
  }

  n <- length(values)

  # Resolve each output axis to a value vector of length n.
  get_axis <- function(name) {
    coordinate <- domain$coordinates[[name]]
    if (is.null(coordinate)) return(rep(NA, n))
    vals <- coordinate$values
    coordinate_axis <- coordinate$axis
    if (coordinate_axis %in% axis_names) {
      idx <- grid[[coordinate_axis]]
      vals[idx]
    } else {
      rep(vals[[1]], n)
    }
  }

  value_demoted <- isTRUE(attr(values, "edr_demoted"))
  attr(values, "edr_demoted") <- NULL
  out <- tibble::tibble(
    coverage_id     = coverage_id,
    parameter       = pname,
    parameter_label = param_label(params, pname),
    unit            = param_unit(params, pname),
    datetime        = as.character(get_axis("t")),
    x               = as.numeric(get_axis("x")),
    y               = as.numeric(get_axis("y")),
    z               = as.numeric(get_axis("z")),
    value           = values
  )
  custom_coordinates <- setdiff(
    names(domain$coordinates),
    c("t", "x", "y", "z")
  )
  for (coordinate_name in custom_coordinates) {
    out[[covjson_coordinate_column(coordinate_name)]] <- get_axis(coordinate_name)
  }
  if (value_demoted) {
    attr(out, "edr_demoted") <- pname
  }
  out
}

normalize_ndarray <- function(rng, pname, axes, coverage_id) {
  if (is.character(rng)) {
    cli::cli_abort(
      "Range {.val {pname}} in coverage {.val {coverage_id}} is external; external CoverageJSON ranges are not supported."
    )
  }
  if (!is.list(rng)) {
    cli::cli_abort(
      "Range {.val {pname}} in coverage {.val {coverage_id}} must be an inline NdArray object."
    )
  }

  range_type <- rng$type
  if (identical(range_type, "TiledNdArray")) {
    cli::cli_abort(
      "Range {.val {pname}} in coverage {.val {coverage_id}} uses {.val TiledNdArray}, which is not yet supported."
    )
  }
  if (!identical(range_type, "NdArray")) {
    actual <- range_type %||% "missing"
    cli::cli_abort(
      "Range {.val {pname}} in coverage {.val {coverage_id}} has type {.val {actual}}; expected {.val NdArray}."
    )
  }
  if (is.null(rng$values)) {
    cli::cli_abort(
      "NdArray range {.val {pname}} in coverage {.val {coverage_id}} has no {.field values}."
    )
  }

  values <- flatten_range_values(rng$values, pname, coverage_id)
  n_values <- length(values)

  shape <- normalize_range_shape(rng$shape, pname, coverage_id)
  axis_names <- normalize_range_axis_names(rng$axisNames, pname, coverage_id)
  if (is.null(rng$shape) && length(axis_names) > 0L) {
    cli::cli_abort(
      "NdArray range {.val {pname}} in coverage {.val {coverage_id}} has {.field axisNames} but no {.field shape}."
    )
  }
  if (length(shape) > 0L && is.null(rng$axisNames)) {
    cli::cli_abort(
      "NdArray range {.val {pname}} in coverage {.val {coverage_id}} has a non-scalar {.field shape} but no {.field axisNames}."
    )
  }
  if (length(shape) != length(axis_names)) {
    cli::cli_abort(
      "NdArray range {.val {pname}} in coverage {.val {coverage_id}} has {length(shape)} shape dimensions but {length(axis_names)} axis names."
    )
  }
  expected_values <- prod(as.double(shape))
  if (expected_values != n_values) {
    cli::cli_abort(
      "NdArray range {.val {pname}} in coverage {.val {coverage_id}} shape requires {expected_values} values, not {n_values}."
    )
  }

  unknown_axes <- setdiff(axis_names, names(axes))
  if (length(unknown_axes) > 0L) {
    cli::cli_abort(
      "NdArray range {.val {pname}} in coverage {.val {coverage_id}} references unknown domain axes: {.val {unknown_axes}}."
    )
  }
  if (length(axis_names) > 0L) {
    axis_sizes <- vapply(axis_names, function(x) axes[[x]]$size, integer(1))
    wrong_size <- which(as.double(shape) != as.double(axis_sizes))
    if (length(wrong_size) > 0L) {
      i <- wrong_size[[1]]
      cli::cli_abort(
        "NdArray range {.val {pname}} axis {.val {axis_names[[i]]}} has shape {shape[[i]]}, but the domain axis has {axis_sizes[[i]]} values."
      )
    }
  }
  omitted_axes <- setdiff(names(axes), axis_names)
  non_scalar_omitted <- omitted_axes[vapply(
    axes[omitted_axes],
    function(x) x$size != 1L,
    logical(1)
  )]
  if (length(non_scalar_omitted) > 0L) {
    cli::cli_abort(
      "NdArray range {.val {pname}} omits non-scalar domain axes: {.val {non_scalar_omitted}}."
    )
  }

  data_type <- rng$dataType
  if (!is.null(data_type) &&
      (!is.character(data_type) || length(data_type) != 1L ||
       is.na(data_type) || !data_type %in% c("float", "integer", "string"))) {
    cli::cli_abort(
      "NdArray range {.val {pname}} in coverage {.val {coverage_id}} has invalid {.field dataType}."
    )
  }

  list(
    values = coerce_values(values, n_values, data_type, pname),
    shape = shape,
    axis_names = axis_names
  )
}

normalize_range_shape <- function(x, pname, coverage_id) {
  if (is.null(x)) return(numeric())
  shape <- unlist(x, use.names = FALSE)
  if (length(shape) == 0L) return(numeric())
  if (!is.numeric(shape) || is.logical(shape) || anyNA(shape) ||
      any(!is.finite(shape)) || any(shape < 1) || any(shape != floor(shape))) {
    cli::cli_abort(
      "NdArray range {.val {pname}} in coverage {.val {coverage_id}} has an invalid {.field shape}; dimensions must be positive integers."
    )
  }
  as.double(shape)
}

normalize_range_axis_names <- function(x, pname, coverage_id) {
  if (is.null(x)) return(character())
  axis_names <- unlist(x, use.names = FALSE)
  if (length(axis_names) == 0L) return(character())
  if (!is.character(axis_names) || anyNA(axis_names) ||
      any(!nzchar(axis_names)) || anyDuplicated(axis_names)) {
    cli::cli_abort(
      "NdArray range {.val {pname}} in coverage {.val {coverage_id}} has invalid {.field axisNames}."
    )
  }
  axis_names
}

flatten_range_values <- function(values, pname, coverage_id) {
  if (!is.list(values) && !is.atomic(values)) {
    cli::cli_abort(
      "NdArray range {.val {pname}} in coverage {.val {coverage_id}} has malformed {.field values}."
    )
  }
  if (length(values) == 0L) {
    cli::cli_abort(
      "NdArray range {.val {pname}} in coverage {.val {coverage_id}} must contain at least one value."
    )
  }

  pieces <- if (is.list(values)) values else as.list(values)
  kinds <- vapply(pieces, function(value) {
    if (is.null(value) || (length(value) == 1L && is.na(value))) return("missing")
    if (length(value) != 1L || is.list(value)) return("invalid")
    if (is.character(value)) return("string")
    if (is.numeric(value) && !is.logical(value)) return("number")
    "invalid"
  }, character(1))
  if (any(kinds == "invalid")) {
    bad <- which(kinds == "invalid")[[1]]
    cli::cli_abort(
      "Value {bad} in NdArray range {.val {pname}} is not a scalar number, string, or null."
    )
  }

  out <- unlist(lapply(pieces, function(value) {
    if (is.null(value) || (length(value) == 1L && is.na(value))) NA else value
  }), use.names = FALSE)
  attr(out, "edr_value_kinds") <- kinds
  out
}

coerce_values <- function(values, n, data_type = NULL, pname = "") {
  if (length(values) != n) {
    cli::cli_abort("Internal CoverageJSON value-length mismatch.")
  }
  kinds <- attr(values, "edr_value_kinds") %||% rep("missing", n)
  attr(values, "edr_value_kinds") <- NULL

  if (!is.null(data_type)) {
    expected_kind <- if (identical(data_type, "string")) "string" else "number"
    wrong_kind <- kinds != "missing" & kinds != expected_kind
    if (any(wrong_kind)) {
      if (identical(expected_kind, "string")) {
        cli::cli_abort(
          "NdArray range {.val {pname}} declares {.field dataType} {.val {data_type}}, but its values contain numbers."
        )
      }
      # Some otherwise usable EDR servers (including USGS waterdata) declare
      # numeric CoverageJSON ranges but serialize the values as JSON strings.
      # Honour the declared type when coercion stays finite and avoids obvious
      # overflow, underflow, or unsafe integer rounding. Real text still fails
      # rather than being silently converted to missing values.
      string_values <- values[kinds == "string"]
      parsed_strings <- suppressWarnings(as.numeric(string_values))
      lexical_number <- grepl(
        "^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$",
        string_values
      )
      mantissa <- sub("[eE].*$", "", string_values)
      underflow <- parsed_strings == 0 & grepl("[1-9]", mantissa)
      unsafe_integer <- identical(data_type, "integer") &
        abs(parsed_strings) >= 2^53
      if (any(!lexical_number | is.na(parsed_strings) |
              !is.finite(parsed_strings) | underflow | unsafe_integer)) {
        cli::cli_abort(
          "NdArray range {.val {pname}} declares {.field dataType} {.val {data_type}}, but its values contain strings that are not valid numbers or cannot be represented safely."
        )
      }
    }
    if (identical(data_type, "string")) return(as.character(values))

    out <- suppressWarnings(as.numeric(values))
    if (identical(data_type, "integer") &&
        any(!is.na(out) & out != floor(out))) {
      cli::cli_abort(
        "NdArray range {.val {pname}} declares integer data but contains non-integer values."
      )
    }
    return(out)
  }

  num <- suppressWarnings(as.numeric(values))
  present <- !is.na(values)
  parsed <- !is.na(num)
  if (any(present & !parsed)) {
    # Any real non-numeric payload means numeric conversion would lose data.
    out <- as.character(values)
    attr(out, "edr_demoted") <- any(parsed)
    return(out)
  }
  num
}

param_label <- function(params, pname) {
  p <- params[[pname]]
  if (is.null(p)) return(NA_character_)
  localized(p$observedProperty$label) %||% pname
}

param_unit <- function(params, pname) {
  p <- params[[pname]]
  if (is.null(p)) return(NA_character_)
  u <- p$unit
  if (is.null(u)) return(NA_character_)
  localized(u$symbol) %||% localized(u$label) %||% NA_character_
}

# Pull an "en" (or first) value from a CovJSON localized label, which
# may be a bare string or a language-keyed list.
localized <- function(x) {
  if (is.null(x)) return(NULL)
  if (is.character(x) && length(x) == 1L) return(x)
  if (is.list(x)) {
    if (!is.null(x$en)) return(as.character(x$en))
    if (!is.null(x[["value"]])) return(as.character(x[["value"]]))
    flat <- unlist(x, use.names = FALSE)
    if (length(flat) >= 1L) return(as.character(flat[[1]]))
  }
  NULL
}

parse_datetime <- function(x) {
  if (!is.character(x)) return(x)
  if (length(x) == 0L || all(is.na(x))) return(x)

  parsed <- rep(NA_real_, length(x))
  present <- !is.na(x)
  for (i in which(present)) {
    value <- x[[i]]
    result <- NA_real_

    # RFC 3339 timestamps. Normalize `Z` and colon-bearing offsets before
    # passing them to base R's portable `%z` parser.
    if (grepl(
      "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:\\.\\d+)?(?:Z|[+-]\\d{2}:?\\d{2})$",
      value,
      perl = TRUE
    )) {
      normalized <- sub("Z$", "+0000", value)
      normalized <- sub("([+-]\\d{2}):(\\d{2})$", "\\1\\2", normalized)
      result <- suppressWarnings(as.numeric(as.POSIXct(
        normalized,
        format = "%Y-%m-%dT%H:%M:%OS%z",
        tz = "UTC"
      )))
    } else if (grepl(
      "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:\\.\\d+)?$",
      value,
      perl = TRUE
    )) {
      # Keep compatibility with servers that omit an offset by treating
      # such timestamps as UTC, as the old parser did.
      result <- suppressWarnings(as.numeric(as.POSIXct(
        value,
        format = "%Y-%m-%dT%H:%M:%OS",
        tz = "UTC"
      )))
    } else if (grepl("^\\d{4}-\\d{2}-\\d{2}$", value)) {
      result <- suppressWarnings(as.numeric(as.POSIXct(
        value,
        format = "%Y-%m-%d",
        tz = "UTC"
      )))
    }
    parsed[[i]] <- result
  }

  failed <- present & is.na(parsed)
  if (any(failed)) {
    bad <- unique(x[failed])
    cli::cli_warn(c(
      "Could not parse every datetime value; keeping the datetime column as character.",
      "x" = "Unparsed value{?s}: {.val {bad}}"
    ))
    return(x)
  }

  as.POSIXct(parsed, origin = "1970-01-01", tz = "UTC")
}

empty_covjson_tibble <- function() {
  tibble::tibble(
    coverage_id     = character(),
    parameter       = character(),
    parameter_label = character(),
    unit            = character(),
    datetime        = character(),
    x               = numeric(),
    y               = numeric(),
    z               = numeric(),
    value           = numeric()
  )
}

# ---------------------------------------------------------------------
# GeoJSON internals

as_geojson <- function(x) {
  if (inherits(x, "edr_geojson")) return(x$geojson)
  if (is.list(x) && !is.null(x$geojson)) return(x$geojson)
  if (is.list(x) && !is.null(x$type)) return(x)
  cli::cli_abort("Cannot interpret {.arg x} as GeoJSON.")
}

geojson_props_tibble <- function(gj) {
  features <- gj$features %||% list()
  if (length(features) == 0L) return(tibble::tibble())
  # vec_rbind, not map_dfr: see note in edr_collections().
  rows <- lapply(features, function(f) {
    props <- f$properties %||% list()
    props <- lapply(props, function(v) if (is.null(v)) NA else v)
    id <- f$id %||% NA
    tibble::as_tibble(c(list(id = id), props))
  })
  vctrs::vec_rbind(!!!rows)
}
