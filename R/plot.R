#' Plot an EDR time-series response as a ggplot
#'
#' Convenience wrapper around [ggplot2::ggplot()] for the long tibble
#' returned by [covjson_to_tibble()]. By default each parameter gets its
#' own facet (so different units don't share a y-axis), and each
#' location is drawn in its own colour.
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
                     facet_labels = TRUE) {
  check_installed_for("ggplot2", "build plots")
  geom <- match.arg(geom)
  data <- as_tidy_data(data)

  required <- c("datetime", "value")
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

  if (!is.null(facet) && facet %in% names(data)) {
    p <- p + ggplot2::facet_wrap(
      ggplot2::vars(.data[[facet]]),
      scales = scales
    )
  }

  p +
    ggplot2::labs(x = NULL, y = NULL, colour = NULL) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(legend.position = "bottom")
}
