#' Convert a CoverageJSON response to a tidy tibble
#'
#' Flattens a CoverageJSON `Coverage` or `CoverageCollection` into a
#' long tibble with one row per (coverage, parameter, time-step). Handles
#' the `Point` and `PointSeries` domain types used by station-based EDR
#' providers, and falls back to a general N-dimensional unrolling for
#' `Grid`-like domains.
#'
#' @param x A CoverageJSON object: either an `edr_response` returned by
#'   [edr_location()] / [edr_area()] / [edr_cube()] (etc.) with
#'   `format = "covjson"`, or the raw parsed list.
#' @param datetime_as_posix If `TRUE` (default), attempts to parse the
#'   time axis to `POSIXct` (UTC). Falls back to character on failure.
#'
#' @return A tibble with columns `coverage_id`, `parameter`,
#'   `parameter_label`, `unit`, `datetime`, `x`, `y`, `z`, and `value`.
#'   Columns that are absent from the source are filled with `NA`.
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
  if (length(coverages) == 0L) return(empty_covjson_tibble())

  per_cov <- purrr::imap(coverages, function(cvg, i) {
    cid <- coverage_id(cvg, i)
    one_coverage(cvg, params, coverage_id = cid)
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

  out <- vctrs::vec_rbind(!!!per_cov)

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
  gj <- as_geojson(x)

  if (!rlang::is_installed("sf")) {
    cli::cli_warn(
      "{.pkg sf} is not installed; returning properties without geometry."
    )
    return(geojson_props_tibble(gj))
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
    return(geojson_props_tibble(gj))
  }
  tibble::as_tibble(res) |> sf::st_as_sf()
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

one_coverage <- function(cvg, params, coverage_id) {
  domain <- cvg$domain %||% list()
  axes   <- domain$axes %||% list()
  ranges <- cvg$ranges %||% list()
  if (length(ranges) == 0L) return(empty_covjson_tibble())

  # Pull scalar/array axis values we care about.
  axis_vals <- list(
    x = axis_numeric(axes$x),
    y = axis_numeric(axes$y),
    z = axis_numeric(axes$z),
    t = axis_chr(axes$t)
  )

  rows <- purrr::imap(ranges, function(rng, pname) {
    range_to_rows(rng, pname, axes, axis_vals, params, coverage_id)
  })

  # Reconcile `value` types across parameter ranges in this coverage.
  # Constant-time on the happy path: we read column type tags only, never
  # touch the values themselves. When numeric and character coexist (e.g.
  # numeric `storage` next to a categorical `qa_flag`), demote everyone to
  # character and remember which parameters started numeric so the
  # top-level call can name them in a single warning.
  types <- vapply(rows, function(r) typeof(r$value), character(1))
  demoted <- character(0)
  if (length(unique(types)) > 1L) {
    demoted <- names(rows)[types != "character"]
    rows <- lapply(rows, function(r) {
      if (!is.character(r$value)) r$value <- as.character(r$value)
      r
    })
  }

  out <- vctrs::vec_rbind(!!!rows)
  attr(out, "edr_demoted") <- demoted
  out
}

range_to_rows <- function(rng, pname, axes, axis_vals, params, coverage_id) {
  values <- null_to_na(rng$values %||% list())
  axis_names <- unlist(rng$axisNames %||% list(), use.names = FALSE)

  # Build the coordinate grid aligned to `values` (row-major: last axis
  # varies fastest), for the axes this range actually spans.
  if (length(axis_names) == 0L) {
    grid <- data.frame(.dummy = seq_along(values))
    grid$.dummy <- NULL
  } else {
    spanned <- lapply(axis_names, function(a) seq_along(axis_values_for(a, axes)))
    names(spanned) <- axis_names
    # expand.grid varies the first column fastest; reverse so the last
    # axisName (which varies fastest in CovJSON) lines up, then reorder.
    g <- expand.grid(rev(spanned), KEEP.OUT.ATTRS = FALSE)
    names(g) <- rev(axis_names)
    grid <- g[, axis_names, drop = FALSE]
  }

  n <- max(length(values), nrow(grid), 1L)

  # Resolve each output axis to a value vector of length n.
  get_axis <- function(name) {
    vals <- axis_vals[[name]]
    if (is.null(vals)) return(rep(NA, n))
    if (name %in% axis_names) {
      idx <- grid[[name]]
      vals[idx]
    } else if (length(vals) == 1L) {
      rep(vals[[1]], n)
    } else if (length(vals) == n) {
      vals
    } else {
      rep(NA, n)
    }
  }

  tibble::tibble(
    coverage_id     = coverage_id,
    parameter       = pname,
    parameter_label = param_label(params, pname),
    unit            = param_unit(params, pname),
    datetime        = as.character(get_axis("t")),
    x               = as.numeric(get_axis("x")),
    y               = as.numeric(get_axis("y")),
    z               = as.numeric(get_axis("z")),
    value           = coerce_values(values, n)
  )
}

axis_values_for <- function(name, axes) {
  ax <- axes[[name]]
  if (is.null(ax)) return(NA)
  ax$values %||% NA
}

axis_numeric <- function(ax) {
  if (is.null(ax)) return(NULL)
  v <- ax$values %||% NULL
  if (is.null(v)) return(NULL)
  suppressWarnings(as.numeric(unlist(v, use.names = FALSE)))
}

axis_chr <- function(ax) {
  if (is.null(ax)) return(NULL)
  v <- ax$values %||% NULL
  if (is.null(v)) return(NULL)
  as.character(unlist(v, use.names = FALSE))
}

coerce_values <- function(values, n) {
  if (length(values) == 0L) return(rep(NA_real_, n))
  num <- suppressWarnings(as.numeric(values))
  if (all(is.na(num)) && !all(is.na(values))) {
    # Non-numeric payload; keep as character.
    return(as.character(values))
  }
  num
}

null_to_na <- function(values) {
  if (is.list(values)) {
    values <- lapply(values, function(v) if (is.null(v) || length(v) == 0L) NA else v)
    return(unlist(values, use.names = FALSE))
  }
  values
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
  fmts <- c(
    "%Y-%m-%dT%H:%M:%OSZ", "%Y-%m-%dT%H:%M:%SZ",
    "%Y-%m-%dT%H:%M:%OS",  "%Y-%m-%dT%H:%M:%S",
    "%Y-%m-%d"
  )
  for (f in fmts) {
    p <- suppressWarnings(as.POSIXct(x, format = f, tz = "UTC"))
    if (!all(is.na(p) | is.na(x))) return(p)
  }
  x
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
  purrr::map_dfr(features, function(f) {
    props <- f$properties %||% list()
    props <- lapply(props, function(v) if (is.null(v)) NA else v)
    id <- f$id %||% NA
    tibble::as_tibble(c(list(id = id), props))
  })
}
