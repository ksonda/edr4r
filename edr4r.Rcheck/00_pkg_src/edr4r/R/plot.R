#' Plot an EDR response as a ggplot
#'
#' Convenience wrapper around [ggplot2::ggplot()] for the long tibble
#' returned by [covjson_to_tibble()]. Automatically chooses a sensible
#' view for time series, vertical profiles, and x/y grids.
#'
#' @param data Either a tidy tibble from [covjson_to_tibble()] or an
#'   `edr_response` / `edr_covjson` object (which we flatten with
#'   [covjson_to_tibble()] for you).
#' @param parameter Optional character vector restricting to a subset
#'   of parameters.
#' @param group Column in `data` used for the colour aesthetic.
#'   Defaults to `"coverage_id"` (one colour per location). Set to
#'   `NULL` to disable.
#' @param facet Column to facet by. Defaults to `"parameter"` so each
#'   variable gets its own panel; pass `NULL` to plot everything on
#'   one axis.
#' @param scales `facet_wrap()` scales argument. Default `"free_y"`
#'   gives each parameter its own y-axis range.
#' @param geom One of `"line"`, `"point"`, or `"both"`.
#' @param facet_labels If `TRUE` (default), facet strip labels include
#'   the unit (e.g. `"discharge (ft3/s)"`).
#' @param view Plot view. `"auto"` (default) detects grids from varying
#'   `x` and `y`, profiles from varying `z`, and otherwise falls back
#'   to a time-series view. Set to `"time"`, `"profile"`, or `"grid"` to
#'   force a specific layout.
#'
#' @return A `ggplot` object.
#' @export
#'
#' @examples
#' \dontrun{
#' cl <- edr_client("https://api.wwdh.internetofwater.app")
#' resp <- edr_location(cl, "rise-edr",
#'                      location_id    = 3514,
#'                      datetime       = "2023-01-01/2023-06-30",
#'                      parameter_name = "3")
#' edr_plot(resp)
#' }
edr_plot <- function(data,
                     parameter    = NULL,
                     group        = "coverage_id",
                     facet        = "parameter",
                     scales       = "free_y",
                     geom         = c("line", "point", "both"),
                     facet_labels = TRUE,
                     view         = c("auto", "time", "profile", "grid")) {
  check_installed_for("ggplot2", "build plots")
  geom <- match.arg(geom)
  view <- match.arg(view)
  data <- as_tidy_data(data)

  required <- "value"
  missing <- setdiff(required, names(data))
  if (length(missing) > 0L) {
    cli::cli_abort(
      "{.arg data} is missing required column{?s}: {.field {missing}}."
    )
  }
  if (!is.null(parameter)) {
    data <- data[data$parameter %in% parameter, , drop = FALSE]
    if (nrow(data) == 0L) {
      cli::cli_abort(
        "No rows match {.arg parameter} = {.val {parameter}}."
      )
    }
  }
  view <- detect_plot_view(data, view)

  # Facet labels that incorporate the unit, when available.
  if (isTRUE(facet_labels) && !is.null(facet) &&
      identical(facet, "parameter") &&
      all(c("parameter", "unit") %in% names(data))) {
    units <- vapply(
      split(data$unit, data$parameter),
      function(u) {
        u <- unique(u[!is.na(u) & nzchar(u)])
        if (length(u) >= 1L) u[[1]] else NA_character_
      },
      character(1)
    )
    pretty <- ifelse(is.na(units), names(units),
                     sprintf("%s (%s)", names(units), units))
    data$parameter <- factor(data$parameter,
                             levels = names(units), labels = pretty)
  }

  switch(view,
    time    = time_plot(data, group, facet, scales, geom),
    profile = profile_plot(data, group, facet, scales, geom),
    grid    = grid_plot(data, facet, scales)
  )
}

detect_plot_view <- function(data, view) {
  if (view != "auto") return(view)
  if (looks_like_grid(data)) return("grid")
  has_z <- "z" %in% names(data) && n_present_unique(data$z) > 1L
  if (has_z) return("profile")
  "time"
}

looks_like_grid <- function(data) {
  if (!all(c("x", "y") %in% names(data))) return(FALSE)
  ok <- !is.na(data$x) & !is.na(data$y)
  x <- data$x[ok]
  y <- data$y[ok]
  nx <- n_present_unique(x)
  ny <- n_present_unique(y)
  if (nx <= 1L || ny <= 1L) return(FALSE)
  npairs <- length(unique(paste(x, y, sep = "\r")))
  npairs == nx * ny
}

n_present_unique <- function(x) {
  length(unique(x[!is.na(x)]))
}

time_plot <- function(data, group, facet, scales, geom) {
  required <- c("datetime", "value")
  missing <- setdiff(required, names(data))
  if (length(missing) > 0L) {
    cli::cli_abort(
      "{.arg data} is missing required column{?s}: {.field {missing}}."
    )
  }
  mapping <- if (!is.null(group) && group %in% names(data)) {
    ggplot2::aes(
      x = .data$datetime, y = .data$value, colour = .data[[group]]
    )
  } else {
    ggplot2::aes(x = .data$datetime, y = .data$value)
  }
  p <- ggplot2::ggplot(data, mapping)

  if (geom %in% c("line", "both"))  p <- p + ggplot2::geom_line()
  if (geom %in% c("point", "both")) p <- p + ggplot2::geom_point(size = 0.7)

  finish_plot(p, data, facet, scales, colour = TRUE)
}

profile_plot <- function(data, group, facet, scales, geom) {
  required <- c("z", "value")
  missing <- setdiff(required, names(data))
  if (length(missing) > 0L) {
    cli::cli_abort(
      "{.arg data} is missing required column{?s}: {.field {missing}}."
    )
  }
  data <- data[!is.na(data$z) & !is.na(data$value), , drop = FALSE]
  if (nrow(data) == 0L) {
    cli::cli_abort("No rows have both {.field z} and {.field value}.")
  }
  data$.edr_profile_group <- profile_group(data, group, facet)

  mapping <- if (!is.null(group) && group %in% names(data)) {
    ggplot2::aes(
      x = .data$value, y = .data$z,
      colour = .data[[group]], group = .data$.edr_profile_group
    )
  } else {
    ggplot2::aes(
      x = .data$value, y = .data$z,
      group = .data$.edr_profile_group
    )
  }
  p <- ggplot2::ggplot(data, mapping)

  if (geom %in% c("line", "both"))  p <- p + ggplot2::geom_path()
  if (geom %in% c("point", "both")) p <- p + ggplot2::geom_point(size = 0.7)

  finish_plot(p, data, facet, scales, colour = !is.null(group) && group %in% names(data))
}

profile_group <- function(data, group, facet) {
  cols <- character(0)
  if (!is.null(group) && group %in% names(data)) cols <- c(cols, group)
  if ("datetime" %in% names(data) && n_present_unique(data$datetime) > 1L) {
    cols <- c(cols, "datetime")
  }
  if (!identical(facet, "parameter") &&
      "parameter" %in% names(data) && n_present_unique(data$parameter) > 1L) {
    cols <- c(cols, "parameter")
  }
  cols <- unique(cols)
  if (length(cols) == 0L) return(rep("profile", nrow(data)))
  do.call(paste, c(lapply(cols, function(col) as.character(data[[col]])), sep = "\r"))
}

grid_plot <- function(data, facet, scales) {
  required <- c("x", "y", "value")
  missing <- setdiff(required, names(data))
  if (length(missing) > 0L) {
    cli::cli_abort(
      "{.arg data} is missing required column{?s}: {.field {missing}}."
    )
  }
  data <- data[!is.na(data$x) & !is.na(data$y), , drop = FALSE]
  if (nrow(data) == 0L) {
    cli::cli_abort("No rows have both {.field x} and {.field y}.")
  }
  if (identical(facet, "parameter")) {
    data <- add_grid_panel(data)
    facet <- ".edr_panel"
  }

  p <- ggplot2::ggplot(
    data,
    ggplot2::aes(x = .data$x, y = .data$y, fill = .data$value)
  ) +
    ggplot2::geom_tile() +
    ggplot2::coord_equal()

  if (is.numeric(data$value)) {
    p <- p + ggplot2::scale_fill_viridis_c(na.value = "transparent")
  }

  # `coord_equal()` needs fixed facet scales; free scales error when
  # ggplot renders the grobs.
  finish_plot(p, data, facet, "fixed", colour = FALSE, fill = TRUE)
}

add_grid_panel <- function(data) {
  cols <- character(0)
  if ("coverage_id" %in% names(data) && n_present_unique(data$coverage_id) > 1L) {
    cols <- c(cols, "coverage_id")
  }
  if ("parameter" %in% names(data)) {
    cols <- c(cols, "parameter")
  }
  if ("datetime" %in% names(data) && n_present_unique(data$datetime) > 1L) {
    cols <- c(cols, "datetime")
  }
  if ("z" %in% names(data) && n_present_unique(data$z) > 1L) {
    cols <- c(cols, "z")
  }
  if (length(cols) == 0L) {
    data$.edr_panel <- "grid"
  } else {
    data$.edr_panel <- do.call(
      paste,
      c(lapply(cols, function(col) panel_value(col, data[[col]])), sep = " | ")
    )
  }
  data
}

panel_value <- function(col, x) {
  x <- as.character(x)
  if (identical(col, "z")) return(paste0("z=", x))
  x
}

finish_plot <- function(p, data, facet, scales, colour = FALSE, fill = FALSE) {
  if (!is.null(facet) && facet %in% names(data)) {
    p <- p + ggplot2::facet_wrap(
      ggplot2::vars(.data[[facet]]),
      scales = scales
    )
  }

  labels <- list(x = NULL, y = NULL)
  if (isTRUE(colour)) labels$colour <- NULL
  if (isTRUE(fill)) labels$fill <- NULL

  p +
    do.call(ggplot2::labs, labels) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(legend.position = "bottom")
}
