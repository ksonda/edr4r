#' Map EDR locations or coverage data
#'
#' Builds a [leaflet] map of station features or gridded/profile
#' CoverageJSON data. Station maps can show per-station popups with
#' interactive time-series charts and CSV downloads. Coverage maps keep
#' all supplied parameters, times, and vertical levels in the widget and
#' expose in-map controls for choosing the active slice; grid cells open
#' popups with a time-series chart for the clicked cell.
#'
#' `data` can be one of:
#'
#' * `NULL` -- just markers with the sf attribute table as a popup
#'   (when `popup = "table"` or `popup = "all"`).
#' * A long tibble (the output of [covjson_to_tibble()]) with one
#'   column matching the locations' id column. Set `location_col =`
#'   to the column in `data` that holds the location id and `id_col =`
#'   to the column in `locations`.
#' * A named list of tibbles, keyed by feature id. This is what
#'   [edr_explore()] passes when it fetches one time series per
#'   station — and the right shape when each station has its own
#'   CovJSON response, because server-assigned `coverage_id`s like
#'   `"1"` won't naturally match the feature id.
#'
#' @param locations An `sf` object from [edr_locations()], an
#'   `edr_response` wrapping GeoJSON, or tidy coverage data from
#'   [covjson_to_tibble()] / a CoverageJSON `edr_response`.
#' @param data See above. Defaults to `NULL`.
#' @param popup One of `"plot+csv"` (default), `"plot"`, `"csv"`,
#'   `"table"`, or `"all"`.
#' @param location_col Column in `data` carrying the location id when
#'   `data` is a single tibble. Default `"coverage_id"`.
#' @param id_col Column in `locations` to join on. If `NULL`, the
#'   function looks for `"id"` then `"_id"` then the first character
#'   column.
#' @param label_col Column in `locations` used for the popup heading.
#'   If `NULL`, tries `"name"`, `"locationName"`, `"title"`, then the
#'   detected id column.
#' @param parameter Optional character vector restricting which
#'   parameters are displayed. On station maps, the filtered rows also
#'   determine whether a station is marked as having data. On coverage
#'   maps, only matching rows are included in the widget payload.
#' @param plot_width,plot_height Popup chart dimensions in inches.
#'   Display size in pixels is `plot_width * plot_dpi` by
#'   `plot_height * plot_dpi`, with a larger minimum size for readable
#'   interactive popups.
#' @param plot_dpi Display dots-per-inch for popup charts. Default 72;
#'   bump to 90+ if popups look small on hi-DPI displays.
#' @param tile_provider Leaflet basemap. Default `"CartoDB.Positron"`.
#' @param marker_radius Marker radius in pixels for stations that have
#'   time-series data. Data-less stations are drawn one pixel smaller.
#' @param matched_color Marker colour for stations that joined to a
#'   coverage in `data`. Default deep blue.
#' @param unmatched_color Marker colour for stations without data
#'   (only relevant when `data` is supplied and `show_unmatched = TRUE`).
#'   Default light grey.
#' @param show_unmatched If `TRUE` (default), data-less stations are
#'   drawn in `unmatched_color` so the user can see the full station
#'   network. Set to `FALSE` to drop them entirely. Ignored when
#'   `data` is `NULL`.
#' @param legend If `TRUE` (default), add a legend distinguishing
#'   stations with data from those without. Suppressed automatically
#'   when there are no unmatched markers to label.
#' @param max_match_distance Optional maximum coordinate distance for
#'   spatially matching `data` rows with `x` / `y` columns to stations.
#'   Units are those of the station coordinates. `NULL` (default) keeps
#'   the nearest-station fallback unlimited.
#' @param mode Map mode. `"auto"` (default) uses station markers for
#'   spatial feature inputs, grid cells for gridded coverage data, and
#'   profile markers for vertical profiles. Use `"stations"`, `"grid"`,
#'   or `"profile"` to force a mode.
#' @param controls If `TRUE` (default), coverage maps include in-map
#'   controls for available slice dimensions (`parameter`, `datetime`, `z`,
#'   and any varying `.axis_*` CoverageJSON coordinates).
#' @param initial Named list of initial coverage-map selections, e.g.
#'   `list(parameter = "temperature", datetime = "2024-01-01", z = 0)`.
#' @param grid_opacity Fill opacity for gridded coverage cells.
#' @param grid_transform Colour transform for grid values: `"identity"`
#'   (default), `"sqrt"`, or `"log1p"`. The legend continues to report
#'   values on the original scale.
#'
#' @return A `leaflet` htmlwidget. Pass it to [edr_save_html()] to
#'   write a selfcontained HTML file.
#' @export
edr_map <- function(locations,
                    data               = NULL,
                    popup              = c("plot+csv", "plot", "csv", "table", "all"),
                    location_col       = "coverage_id",
                    id_col             = NULL,
                    label_col          = NULL,
                    parameter          = NULL,
                    plot_width         = 7,
                    plot_height        = 3.5,
                    plot_dpi           = 72,
                    tile_provider      = "CartoDB.Positron",
                    marker_radius      = 6,
                    matched_color      = "#2C7FB8",
                    unmatched_color    = "#BBBBBB",
                    show_unmatched     = TRUE,
                    legend             = TRUE,
                    max_match_distance = NULL,
                    mode               = c("auto", "stations", "grid", "profile"),
                    controls           = TRUE,
                    initial            = list(),
                    grid_opacity       = 0.75,
                    grid_transform     = c("identity", "sqrt", "log1p")) {
  check_installed_for("leaflet", "render maps")
  mode <- match.arg(mode)
  popup <- match.arg(popup)
  grid_transform <- match.arg(grid_transform)
  check_max_match_distance(max_match_distance)

  resolved_mode <- resolve_map_mode(locations, mode)
  if (resolved_mode %in% c("grid", "profile", "time")) {
    return(coverage_leaflet_map(
      locations,
      mode = resolved_mode,
      parameter = parameter,
      controls = controls,
      initial = initial,
      grid_opacity = grid_opacity,
      grid_transform = grid_transform,
      tile_provider = tile_provider,
      legend = legend
    ))
  }

  m <- leaflet::leaflet() |>
    leaflet::addProviderTiles(tile_provider)
  edr_add_stations(
    m,
    locations = locations,
    data = data,
    popup = popup,
    location_col = location_col,
    id_col = id_col,
    label_col = label_col,
    parameter = parameter,
    plot_width = plot_width,
    plot_height = plot_height,
    plot_dpi = plot_dpi,
    marker_radius = marker_radius,
    matched_color = matched_color,
    unmatched_color = unmatched_color,
    show_unmatched = show_unmatched,
    legend = legend,
    max_match_distance = max_match_distance,
    group = NULL,
    fit = TRUE
  )
}

#' Save a map to a standalone HTML file
#'
#' Thin wrapper around [htmlwidgets::saveWidget()] for the leaflet
#' map returned by [edr_map()] or [edr_explore()]. With
#' `selfcontained = TRUE` (the default), popup chart data and CSV
#' download links live inside the file -- no sidecar directory.
#'
#' @param map A `leaflet` or `htmlwidget`.
#' @param file Path to write to.
#' @param selfcontained If `TRUE`, embed all assets in the file.
#' @param ... Forwarded to [htmlwidgets::saveWidget()].
#'
#' @return Invisibly returns `file`.
#' @export
edr_save_html <- function(map, file, selfcontained = TRUE, ...) {
  check_installed_for("htmlwidgets", "save HTML maps")
  htmlwidgets::saveWidget(map, file = file,
                          selfcontained = selfcontained, ...)
  invisible(file)
}

# ---------------------------------------------------------------------
# internals

resolve_map_mode <- function(locations, mode) {
  if (mode != "auto") return(mode)
  if (inherits(locations, "sf") || inherits(locations, "edr_geojson") ||
      (!is.data.frame(locations) && is.list(locations) && !is.null(locations$type) &&
       identical(locations$type, "FeatureCollection"))) {
    return("stations")
  }
  data <- tryCatch(as_tidy_data(locations), error = function(e) NULL)
  if (is.null(data)) return("stations")
  detect_plot_view(data, "auto")
}

filter_parameter_rows <- function(data, parameter,
                                  call = rlang::caller_env()) {
  if (is.null(parameter)) return(data)
  if (!is.character(parameter) || length(parameter) == 0L ||
      anyNA(parameter) || any(!nzchar(parameter))) {
    cli::cli_abort(
      "{.arg parameter} must be a non-empty character vector without missing values.",
      call = call
    )
  }
  if (!"parameter" %in% names(data)) {
    cli::cli_abort(
      "{.arg parameter} can only be used when mapped data includes a {.field parameter} column.",
      call = call
    )
  }
  values <- as.character(data$parameter)
  keep <- !is.na(values) & values %in% parameter
  data[keep, , drop = FALSE]
}

coverage_leaflet_map <- function(data,
                                 mode,
                                 controls,
                                 initial,
                                 grid_opacity,
                                 grid_transform,
                                 tile_provider,
                                 legend,
                                 parameter = NULL) {
  check_installed_for("htmlwidgets", "render interactive coverage maps")
  data <- as_tidy_data(data)
  data <- filter_parameter_rows(data, parameter)
  if (nrow(data) == 0L) {
    cli::cli_abort(
      "No coverage rows match the requested {.arg parameter}."
    )
  }
  if (mode == "time") {
    cli::cli_abort(
      c("Could not infer a coverage map mode from {.arg locations}.",
        i = "Use {.fn edr_plot} for time-series-only coverage data, or pass {.code mode = \"grid\"} / {.code mode = \"profile\"}.")
    )
  }
  if (mode == "grid" && !looks_like_grid(data)) {
    cli::cli_abort(
      "{.code mode = \"grid\"} requires data with a complete x/y lattice."
    )
  }
  if (mode == "grid") check_grid_transform(data, grid_transform)
  if (mode == "profile" && !all(c("x", "y", "z") %in% names(data))) {
    cli::cli_abort(
      "{.code mode = \"profile\"} requires {.field x}, {.field y}, and {.field z} columns."
    )
  }

  payload <- coverage_map_payload(
    data, mode, controls, initial, grid_opacity, legend, grid_transform
  )
  m <- leaflet::leaflet() |>
    leaflet::addProviderTiles(tile_provider)
  htmlwidgets::onRender(m, coverage_map_js(), data = payload)
}

check_grid_transform <- function(data, transform,
                                 call = rlang::caller_env()) {
  values <- suppressWarnings(as.numeric(data$value))
  values <- values[is.finite(values)]
  if (identical(transform, "sqrt") && any(values < 0)) {
    cli::cli_abort(
      "{.code grid_transform = \"sqrt\"} requires non-negative grid values.",
      call = call
    )
  }
  if (identical(transform, "log1p") && any(values <= -1)) {
    cli::cli_abort(
      "{.code grid_transform = \"log1p\"} requires grid values greater than -1.",
      call = call
    )
  }
  invisible(transform)
}

coverage_map_payload <- function(data, mode, controls, initial,
                                 grid_opacity, legend,
                                 grid_transform = "identity") {
  data <- data[!is.na(data$x) & !is.na(data$y), , drop = FALSE]
  if (nrow(data) == 0L) {
    cli::cli_abort("Coverage map data must include at least one non-missing x/y coordinate.")
  }

  axis_columns <- covjson_axis_columns(data)
  axis_labels <- stats::setNames(vapply(
    axis_columns,
    function(column) covjson_axis_label(data, column),
    character(1)
  ), axis_columns)

  data$.edr_parameter <- if ("parameter" %in% names(data)) {
    as.character(data$parameter)
  } else {
    "value"
  }
  data$.edr_datetime <- if ("datetime" %in% names(data)) {
    as.character(data$datetime)
  } else {
    ""
  }
  data$.edr_z <- if ("z" %in% names(data)) {
    ifelse(is.na(data$z), "", as.character(data$z))
  } else {
    ""
  }

  if (mode == "grid") {
    data <- add_grid_bounds(data)
  }
  check_leaflet_coordinate_ranges(data, mode)
  check_covjson_crs_consistency(data, map = TRUE)

  control_specs <- coverage_control_specs(
    data,
    mode,
    axis_columns = axis_columns,
    axis_labels = axis_labels
  )
  initial <- normalize_initial_selection(initial, control_specs)

  rows <- lapply(seq_len(nrow(data)), function(i) {
    row <- list(
      x = as.numeric(data$x[[i]]),
      y = as.numeric(data$y[[i]]),
      value = data$value[[i]],
      parameter = data$.edr_parameter[[i]],
      datetime = data$.edr_datetime[[i]],
      z = data$.edr_z[[i]],
      unit = if ("unit" %in% names(data)) as.character(data$unit[[i]]) else "",
      coverage_id = if ("coverage_id" %in% names(data)) as.character(data$coverage_id[[i]]) else ""
    )
    if (mode == "grid") {
      row$xmin <- as.numeric(data$.edr_xmin[[i]])
      row$xmax <- as.numeric(data$.edr_xmax[[i]])
      row$ymin <- as.numeric(data$.edr_ymin[[i]])
      row$ymax <- as.numeric(data$.edr_ymax[[i]])
    }
    for (column in axis_columns) {
      value <- data[[column]][[i]]
      row[[column]] <- if (length(value) == 0L || is.na(value)) {
        ""
      } else {
        as.character(value)
      }
    }
    row
  })

  list(
    mode = mode,
    rows = rows,
    controls = control_specs,
    controls_enabled = isTRUE(controls),
    axis_keys = axis_columns,
    axis_labels = as.list(axis_labels),
    initial = initial,
    opacity = grid_opacity,
    transform = grid_transform,
    legend = isTRUE(legend),
    bounds = list(
      xmin = min(data$x, na.rm = TRUE),
      xmax = max(data$x, na.rm = TRUE),
      ymin = min(data$y, na.rm = TRUE),
      ymax = max(data$y, na.rm = TRUE)
    )
  )
}

coverage_control_specs <- function(data,
                                   mode,
                                   axis_columns = covjson_axis_columns(data),
                                   axis_labels = stats::setNames(
                                     sub("^\\.axis_", "", axis_columns),
                                     axis_columns
                                   )) {
  specs <- list()
  add <- function(specs, key, label, values) {
    values <- unique(values[!is.na(values)])
    if (length(values) > 1L) {
      specs[[length(specs) + 1L]] <- list(
        key = key,
        label = label,
        values = as.character(values)
      )
    }
    specs
  }
  specs <- add(specs, "parameter", "Parameter", data$.edr_parameter)
  specs <- add(specs, "datetime", "Time", data$.edr_datetime[nzchar(data$.edr_datetime)])
  if (mode == "grid") {
    specs <- add(specs, "z", "Z", data$.edr_z[nzchar(data$.edr_z)])
  }
  for (column in axis_columns) {
    specs <- add(
      specs,
      column,
      axis_labels[[column]] %||% sub("^\\.axis_", "", column),
      data[[column]]
    )
  }
  specs
}

normalize_initial_selection <- function(initial, control_specs) {
  if (is.null(initial)) initial <- list()
  if (!is.list(initial)) {
    cli::cli_abort("{.arg initial} must be a named list.")
  }
  out <- list()
  for (spec in control_specs) {
    key <- spec$key
    vals <- spec$values
    friendly_key <- if (startsWith(key, ".axis_")) {
      sub("^\\.axis_", "", key)
    } else {
      key
    }
    selected <- initial[[key]] %||% initial[[friendly_key]] %||% vals[[1]]
    selected <- as.character(selected[[1]])
    if (!selected %in% vals) selected <- vals[[1]]
    out[[key]] <- selected
  }
  out
}

add_grid_bounds <- function(data) {
  x_edges <- axis_cell_edges(data$x)
  y_edges <- axis_cell_edges(data$y)
  xi <- match(data$x, x_edges$values)
  yi <- match(data$y, y_edges$values)
  data$.edr_xmin <- x_edges$lower[xi]
  data$.edr_xmax <- x_edges$upper[xi]
  data$.edr_ymin <- y_edges$lower[yi]
  data$.edr_ymax <- y_edges$upper[yi]
  data
}

axis_cell_edges <- function(values) {
  u <- sort(unique(as.numeric(values[!is.na(values)])))
  if (length(u) == 0L) {
    cli::cli_abort("Grid axes must include at least one finite value.")
  }
  if (length(u) == 1L) {
    delta <- 0.05
    return(list(values = u, lower = u - delta, upper = u + delta))
  }
  mids <- (u[-1L] + u[-length(u)]) / 2
  first_width <- mids[[1]] - u[[1]]
  last_width <- u[[length(u)]] - mids[[length(mids)]]
  list(
    values = u,
    lower = c(u[[1]] - first_width, mids),
    upper = c(mids, u[[length(u)]] + last_width)
  )
}

popup_chart_js <- function() {
  paste0(
    "
function(el, x) {
  var map = this;
",
    popup_chart_renderer_js(),
    "
  map.on('popupopen', function(e) {
    edrRenderPopupCharts(e.popup.getElement());
  });
}
"
  )
}

popup_chart_renderer_js <- function() {
  "
  function edrAsText(v) {
    return v === null || v === undefined ? '' : String(v);
  }

  function edrEscapeHtml(v) {
    return edrAsText(v)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/\"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function edrFiniteNumber(v) {
    if (v === null || v === undefined ||
        (typeof v === 'string' && v.trim() === '')) return null;
    var n = Number(v);
    return Number.isFinite(n) ? n : null;
  }

  function edrFormatNumber(v) {
    var n = edrFiniteNumber(v);
    if (n === null) return '';
    if (Math.abs(n) >= 1000 || (Math.abs(n) > 0 && Math.abs(n) < 0.01)) {
      return n.toExponential(3);
    }
    return Number(n.toPrecision(5)).toString();
  }

  function edrSeriesName(row) {
    var bits = [];
    if (edrAsText(row.parameter) !== '') bits.push(edrAsText(row.parameter));
    if (edrAsText(row.z) !== '') bits.push('z=' + edrAsText(row.z));
    if (edrAsText(row.axes) !== '') bits.push(edrAsText(row.axes));
    if (bits.length === 0) bits.push('value');
    if (edrAsText(row.unit) !== '') bits[bits.length - 1] += ' (' + edrAsText(row.unit) + ')';
    return bits.join(' | ');
  }

  function edrParseX(value, index) {
    var text = edrAsText(value);
    var parsed = Date.parse(text);
    if (text !== '' && Number.isFinite(parsed)) {
      return {value: parsed, isDate: true, label: text};
    }
    var num = edrFiniteNumber(text);
    if (num !== null) {
      return {value: num, isDate: false, label: text};
    }
    return {value: index, isDate: false, label: text || String(index + 1)};
  }

  function edrFormatX(value, isDate) {
    if (isDate) {
      var d = new Date(value);
      if (!Number.isFinite(d.getTime())) return '';
      var iso = d.toISOString();
      return iso.slice(0, 10) + (iso.slice(11, 16) === '00:00' ? '' : ' ' + iso.slice(11, 16));
    }
    return edrFormatNumber(value);
  }

  function edrTicks(min, max, n) {
    if (!Number.isFinite(min) || !Number.isFinite(max)) return [];
    if (max <= min) max = min + 1;
    var out = [];
    for (var i = 0; i < n; i++) {
      out.push(min + (max - min) * i / Math.max(1, n - 1));
    }
    return out;
  }

  function edrReadChartSpec(holder) {
    try {
      return JSON.parse(decodeURIComponent(holder.getAttribute('data-edr-chart') || ''));
    } catch (e) {
      return null;
    }
  }

  function edrPopupChartHtml(spec) {
    var width = Math.max(360, Number(spec.width) || 560);
    var height = Math.max(240, Number(spec.height) || 300);
    var encoded = encodeURIComponent(JSON.stringify(spec));
    return '<div class=\"edr-popup-chart\" data-edr-chart=\"' +
      edrEscapeHtml(encoded) +
      '\" style=\"width:' + width + 'px;max-width:100%;height:' + height + 'px\"></div>';
  }

  function edrRenderPopupCharts(root) {
    if (!root || !root.querySelectorAll) return;
    var holders = root.querySelectorAll('.edr-popup-chart');
    Array.prototype.forEach.call(holders, function(holder) {
      if (holder._edrRendered) return;
      var spec = edrReadChartSpec(holder);
      holder._edrRendered = true;
      edrRenderPopupChart(holder, spec);
    });
  }

  function edrRenderPopupChart(holder, spec) {
    spec = spec || {};
    var rows = spec.rows || [];
    var colors = ['#2c7fb8', '#d95f02', '#1b9e77', '#7570b3', '#e7298a', '#66a61e'];
    var points = [];
    rows.forEach(function(row, i) {
      var y = edrFiniteNumber(row.value);
      if (y === null) return;
      var x = edrParseX(row.x || row.datetime, i);
      points.push({
        x: x.value,
        xLabel: x.label,
        isDate: x.isDate,
        y: y,
        series: edrSeriesName(row),
        row: row
      });
    });
    if (points.length === 0) {
      holder.innerHTML = '<div style=\"padding:12px;color:#666\">No numeric values to plot.</div>';
      return;
    }

    var useDate = points.every(function(p) { return p.isDate; });
    var series = [];
    points.forEach(function(p) {
      if (series.indexOf(p.series) < 0) series.push(p.series);
    });
    var colorForSeries = {};
    series.forEach(function(name, i) {
      colorForSeries[name] = colors[i % colors.length];
    });

    var width = Math.max(360, Number(spec.width) || holder.clientWidth || 560);
    var height = Math.max(240, Number(spec.height) || 300);
    var margin = {top: edrAsText(spec.title) === '' ? 34 : 50, right: 22, bottom: 44, left: 58};
    var innerW = Math.max(1, width - margin.left - margin.right);
    var innerH = Math.max(1, height - margin.top - margin.bottom);
    var minX = Math.min.apply(null, points.map(function(p) { return p.x; }));
    var maxX = Math.max.apply(null, points.map(function(p) { return p.x; }));
    var minY = Math.min.apply(null, points.map(function(p) { return p.y; }));
    var maxY = Math.max.apply(null, points.map(function(p) { return p.y; }));
    if (maxX <= minX) maxX = minX + 1;
    if (maxY <= minY) {
      var pad = Math.abs(minY) || 1;
      minY -= pad * 0.5;
      maxY += pad * 0.5;
    }

    function sx(x) { return margin.left + (x - minX) / (maxX - minX) * innerW; }
    function sy(y) { return margin.top + (maxY - y) / (maxY - minY) * innerH; }

    var xTicks = edrTicks(minX, maxX, 5);
    var yTicks = edrTicks(minY, maxY, 5);
    var grid = '';
    yTicks.forEach(function(t) {
      var y = sy(t);
      grid += '<line x1=\"' + margin.left + '\" y1=\"' + y.toFixed(1) +
        '\" x2=\"' + (width - margin.right) + '\" y2=\"' + y.toFixed(1) +
        '\" stroke=\"#e5e7eb\" />';
      grid += '<text x=\"' + (margin.left - 8) + '\" y=\"' + (y + 3).toFixed(1) +
        '\" text-anchor=\"end\" font-size=\"10\" fill=\"#4b5563\">' +
        edrEscapeHtml(edrFormatNumber(t)) + '</text>';
    });
    xTicks.forEach(function(t) {
      var x = sx(t);
      grid += '<line x1=\"' + x.toFixed(1) + '\" y1=\"' + margin.top +
        '\" x2=\"' + x.toFixed(1) + '\" y2=\"' + (height - margin.bottom) +
        '\" stroke=\"#f0f2f5\" />';
      grid += '<text x=\"' + x.toFixed(1) + '\" y=\"' + (height - 16) +
        '\" text-anchor=\"middle\" font-size=\"10\" fill=\"#4b5563\">' +
        edrEscapeHtml(edrFormatX(t, useDate)) + '</text>';
    });

    var screenPoints = [];
    var paths = '';
    series.forEach(function(name) {
      var pts = points.filter(function(p) { return p.series === name; })
        .sort(function(a, b) { return a.x - b.x; });
      var path = pts.map(function(p, i) {
        p.sx = sx(p.x);
        p.sy = sy(p.y);
        p.color = colorForSeries[name];
        screenPoints.push(p);
        return (i === 0 ? 'M' : 'L') + p.sx.toFixed(1) + ',' + p.sy.toFixed(1);
      }).join(' ');
      paths += '<path d=\"' + path + '\" fill=\"none\" stroke=\"' +
        colorForSeries[name] + '\" stroke-width=\"2\" stroke-linejoin=\"round\" stroke-linecap=\"round\" />';
      pts.forEach(function(p) {
        paths += '<circle cx=\"' + p.sx.toFixed(1) + '\" cy=\"' + p.sy.toFixed(1) +
          '\" r=\"2.7\" fill=\"white\" stroke=\"' + colorForSeries[name] + '\" stroke-width=\"1.5\" />';
      });
    });

    var legend = '';
    series.slice(0, 4).forEach(function(name, i) {
      var lx = margin.left + i * 120;
      var ly = edrAsText(spec.title) === '' ? 18 : 34;
      legend += '<circle cx=\"' + lx + '\" cy=\"' + ly + '\" r=\"4\" fill=\"' + colorForSeries[name] + '\" />' +
        '<text x=\"' + (lx + 8) + '\" y=\"' + (ly + 3) + '\" font-size=\"11\" fill=\"#374151\">' +
        edrEscapeHtml(name.length > 18 ? name.slice(0, 17) + '...' : name) + '</text>';
    });

    var title = edrAsText(spec.title) === '' ? '' :
      '<text x=\"' + margin.left + '\" y=\"18\" font-size=\"13\" font-weight=\"600\" fill=\"#111827\">' +
      edrEscapeHtml(spec.title) + '</text>';

    holder.style.position = 'relative';
    holder.style.height = height + 'px';
    holder.innerHTML =
      '<svg class=\"edr-popup-chart-svg\" width=\"100%\" height=\"100%\" viewBox=\"0 0 ' + width + ' ' + height + '\" role=\"img\" aria-label=\"time series chart\" style=\"display:block;background:white;border:1px solid #d1d5db;border-radius:6px\">' +
      '<rect width=\"100%\" height=\"100%\" fill=\"white\" />' +
      title + legend + grid +
      '<line x1=\"' + margin.left + '\" y1=\"' + (height - margin.bottom) + '\" x2=\"' + (width - margin.right) + '\" y2=\"' + (height - margin.bottom) + '\" stroke=\"#9ca3af\" />' +
      '<line x1=\"' + margin.left + '\" y1=\"' + margin.top + '\" x2=\"' + margin.left + '\" y2=\"' + (height - margin.bottom) + '\" stroke=\"#9ca3af\" />' +
      paths +
      '<line class=\"edr-hover-line\" x1=\"0\" x2=\"0\" y1=\"' + margin.top + '\" y2=\"' + (height - margin.bottom) + '\" stroke=\"#111827\" stroke-dasharray=\"3 3\" opacity=\"0\" />' +
      '<circle class=\"edr-hover-dot\" cx=\"0\" cy=\"0\" r=\"4\" fill=\"#111827\" opacity=\"0\" />' +
      '<rect class=\"edr-hover-overlay\" x=\"' + margin.left + '\" y=\"' + margin.top + '\" width=\"' + innerW + '\" height=\"' + innerH + '\" fill=\"transparent\" style=\"cursor:crosshair\" />' +
      '</svg>' +
      '<div class=\"edr-chart-tooltip\" style=\"display:none;position:absolute;z-index:5;pointer-events:none;background:rgba(17,24,39,0.94);color:white;border-radius:4px;padding:6px 8px;font:12px system-ui,sans-serif;box-shadow:0 2px 8px rgba(0,0,0,0.25)\"></div>';

    var svg = holder.querySelector('svg');
    var overlay = holder.querySelector('.edr-hover-overlay');
    var line = holder.querySelector('.edr-hover-line');
    var dot = holder.querySelector('.edr-hover-dot');
    var tip = holder.querySelector('.edr-chart-tooltip');
    if (!svg || !overlay || !screenPoints.length) return;

    overlay.addEventListener('mousemove', function(evt) {
      var box = svg.getBoundingClientRect();
      var mx = (evt.clientX - box.left) / Math.max(1, box.width) * width;
      var my = (evt.clientY - box.top) / Math.max(1, box.height) * height;
      var best = null;
      var bestD = Infinity;
      screenPoints.forEach(function(p) {
        var dx = p.sx - mx;
        var dy = p.sy - my;
        var d = dx * dx + dy * dy;
        if (d < bestD) {
          bestD = d;
          best = p;
        }
      });
      if (!best) return;
      line.setAttribute('x1', best.sx);
      line.setAttribute('x2', best.sx);
      line.setAttribute('opacity', '0.55');
      dot.setAttribute('cx', best.sx);
      dot.setAttribute('cy', best.sy);
      dot.setAttribute('fill', best.color);
      dot.setAttribute('opacity', '1');
      tip.style.display = 'block';
      tip.innerHTML = '<strong>' + edrEscapeHtml(best.series) + '</strong><br>' +
        edrEscapeHtml(best.xLabel) + '<br>value: ' + edrEscapeHtml(edrFormatNumber(best.y));
      var left = best.sx / width * box.width + 12;
      var top = best.sy / height * box.height - 12;
      tip.style.left = Math.min(Math.max(4, left), Math.max(4, box.width - 180)) + 'px';
      tip.style.top = Math.max(4, top) + 'px';
    });
    overlay.addEventListener('mouseleave', function() {
      line.setAttribute('opacity', '0');
      dot.setAttribute('opacity', '0');
      tip.style.display = 'none';
    });
  }
"
}

coverage_map_js <- function() {
  paste0(
    "
function(el, x, payload) {
  var map = this;
  var rows = payload.rows || [];
  var active = payload.initial || {};
  var paneName = null;
  if (payload.mode === 'grid') {
    paneName = 'edr-coverage-' + (el.id || 'map');
    var coveragePane = map.getPane(paneName) || map.createPane(paneName);
    coveragePane.style.zIndex = '350';
    coveragePane.classList.add('edr-coverage-pane');
  }
  var layer = L.layerGroup().addTo(map);
  var legendControl = null;
",
    popup_chart_renderer_js(),
    "

  map.on('popupopen', function(e) {
    edrRenderPopupCharts(e.popup.getElement());
  });

  function asText(v) {
    return v === null || v === undefined ? '' : String(v);
  }

  function escapeHtml(v) {
    return asText(v)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/\"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function rowMatches(row) {
    for (var key in active) {
      if (Object.prototype.hasOwnProperty.call(active, key) &&
          asText(row[key]) !== asText(active[key])) {
        return false;
      }
    }
    return true;
  }

  function finiteNumber(v) {
    if (v === null || v === undefined ||
        (typeof v === 'string' && v.trim() === '')) return null;
    var n = Number(v);
    return Number.isFinite(n) ? n : null;
  }

  function transformValue(value) {
    var v = finiteNumber(value);
    if (v === null) return null;
    if (payload.transform === 'sqrt') return v < 0 ? null : Math.sqrt(v);
    if (payload.transform === 'log1p') return v <= -1 ? null : Math.log1p(v);
    return v;
  }

  function colorFor(value, min, max) {
    var v = transformValue(value);
    if (v === null) return '#bdbdbd';
    var scaledMin = transformValue(min);
    var scaledMax = transformValue(max);
    if (scaledMin === null || scaledMax === null || scaledMax <= scaledMin) return '#2c7fb8';
    var t = Math.max(0, Math.min(1, (v - scaledMin) / (scaledMax - scaledMin)));
    var stops = [
      [68, 1, 84],
      [59, 82, 139],
      [33, 145, 140],
      [94, 201, 98],
      [253, 231, 37]
    ];
    var scaled = t * (stops.length - 1);
    var i = Math.min(stops.length - 2, Math.floor(scaled));
    var f = scaled - i;
    var a = stops[i], b = stops[i + 1];
    var r = Math.round(a[0] + (b[0] - a[0]) * f);
    var g = Math.round(a[1] + (b[1] - a[1]) * f);
    var bl = Math.round(a[2] + (b[2] - a[2]) * f);
    return 'rgb(' + r + ',' + g + ',' + bl + ')';
  }

  function popupRows(row) {
    var out = '<table style=\"border-collapse:collapse;font-size:12px\">';
    var keys = ['parameter', 'datetime', 'z', 'coverage_id', 'value']
      .concat(payload.axis_keys || []);
    keys.forEach(function(key) {
      if (asText(row[key]) !== '') {
        var label = payload.axis_labels && payload.axis_labels[key] ?
          payload.axis_labels[key] : key;
        out += '<tr><td style=\"color:#666;padding:2px 8px 2px 0\">' +
          escapeHtml(label) + '</td><td style=\"padding:2px\">' +
          escapeHtml(row[key]) + '</td></tr>';
      }
    });
    return out + '</table>';
  }

  function addLegend(min, max, slice) {
    if (!payload.legend || payload.mode !== 'grid') return;
    if (legendControl) map.removeControl(legendControl);
    var parameters = [];
    var units = [];
    (slice || []).forEach(function(row) {
      var parameter = asText(row.parameter);
      var unit = asText(row.unit);
      if (parameter !== '' && parameters.indexOf(parameter) < 0) parameters.push(parameter);
      if (unit !== '' && units.indexOf(unit) < 0) units.push(unit);
    });
    var legendTitle = parameters.length === 1 ? parameters[0] : '';
    if (units.length === 1) {
      legendTitle += (legendTitle === '' ? '' : ' ') + '(' + units[0] + ')';
    }
    legendControl = L.control({position: 'bottomright'});
    legendControl.onAdd = function() {
      var div = L.DomUtil.create('div', 'edr-coverage-legend');
      div.style.background = 'rgba(255,255,255,0.92)';
      div.style.padding = '8px';
      div.style.borderRadius = '4px';
      div.style.boxShadow = '0 1px 4px rgba(0,0,0,0.25)';
      div.style.font = '12px system-ui, sans-serif';
      div.innerHTML =
        (legendTitle === '' ? '' : '<div style=\"font-weight:600;margin-bottom:5px\">' +
          escapeHtml(legendTitle) + '</div>') +
        '<div style=\"width:140px;height:10px;background:linear-gradient(to right,#440154,#3b528b,#21918c,#5ec962,#fde725);margin-bottom:4px\"></div>' +
        '<div style=\"display:flex;justify-content:space-between;gap:8px\"><span>' +
        escapeHtml(Number(min).toPrecision(4)) + '</span><span>' +
        escapeHtml(Number(max).toPrecision(4)) + '</span></div>';
      return div;
    };
    legendControl.addTo(map);
  }

  function profileSvg(groupRows) {
    var pts = groupRows.map(function(row) {
      return {z: finiteNumber(row.z), value: finiteNumber(row.value)};
    }).filter(function(p) {
      return p.z !== null && p.value !== null;
    }).sort(function(a, b) {
      return a.z - b.z;
    });
    if (pts.length === 0) return '<div>No numeric profile values.</div>';
    var w = 240, h = 150, pad = 24;
    var minV = Math.min.apply(null, pts.map(function(p) { return p.value; }));
    var maxV = Math.max.apply(null, pts.map(function(p) { return p.value; }));
    var minZ = Math.min.apply(null, pts.map(function(p) { return p.z; }));
    var maxZ = Math.max.apply(null, pts.map(function(p) { return p.z; }));
    if (maxV <= minV) maxV = minV + 1;
    if (maxZ <= minZ) maxZ = minZ + 1;
    function sx(v) { return pad + (v - minV) / (maxV - minV) * (w - 2 * pad); }
    function sy(z) { return h - pad - (z - minZ) / (maxZ - minZ) * (h - 2 * pad); }
    var path = pts.map(function(p, i) {
      return (i === 0 ? 'M' : 'L') + sx(p.value).toFixed(1) + ',' + sy(p.z).toFixed(1);
    }).join(' ');
    var circles = pts.map(function(p) {
      return '<circle cx=\"' + sx(p.value).toFixed(1) + '\" cy=\"' +
        sy(p.z).toFixed(1) + '\" r=\"2.5\" fill=\"#2c7fb8\" />';
    }).join('');
    return '<svg width=\"' + w + '\" height=\"' + h + '\" viewBox=\"0 0 ' + w + ' ' + h + '\">' +
      '<rect width=\"100%\" height=\"100%\" fill=\"white\" />' +
      '<line x1=\"' + pad + '\" y1=\"' + (h - pad) + '\" x2=\"' + (w - pad) + '\" y2=\"' + (h - pad) + '\" stroke=\"#999\" />' +
      '<line x1=\"' + pad + '\" y1=\"' + pad + '\" x2=\"' + pad + '\" y2=\"' + (h - pad) + '\" stroke=\"#999\" />' +
      '<path d=\"' + path + '\" fill=\"none\" stroke=\"#2c7fb8\" stroke-width=\"2\" />' +
      circles +
      '<text x=\"' + pad + '\" y=\"' + (h - 6) + '\" font-size=\"10\" fill=\"#555\">' + escapeHtml(minV.toPrecision(3)) + '</text>' +
      '<text x=\"' + (w - pad) + '\" y=\"' + (h - 6) + '\" text-anchor=\"end\" font-size=\"10\" fill=\"#555\">' + escapeHtml(maxV.toPrecision(3)) + '</text>' +
      '<text x=\"4\" y=\"' + pad + '\" font-size=\"10\" fill=\"#555\">z ' + escapeHtml(maxZ.toPrecision(3)) + '</text>' +
      '</svg>';
  }

  function gridTimeSeriesRows(row) {
    var targetParameter = Object.prototype.hasOwnProperty.call(active, 'parameter') ? active.parameter : row.parameter;
    var targetZ = Object.prototype.hasOwnProperty.call(active, 'z') ? active.z : row.z;
    var targetCoverage = row.coverage_id;
    var out = rows.filter(function(candidate) {
      if (asText(candidate.x) !== asText(row.x) || asText(candidate.y) !== asText(row.y)) return false;
      if (asText(candidate.parameter) !== asText(targetParameter)) return false;
      if (asText(targetZ) !== '' && asText(candidate.z) !== asText(targetZ)) return false;
      if (asText(targetCoverage) !== '' && asText(candidate.coverage_id) !== asText(targetCoverage)) return false;
      var axisKeys = payload.axis_keys || [];
      for (var i = 0; i < axisKeys.length; i++) {
        var axisKey = axisKeys[i];
        if (asText(candidate[axisKey]) !== asText(row[axisKey])) return false;
      }
      return true;
    });
    out.sort(function(a, b) {
      var ad = Date.parse(asText(a.datetime));
      var bd = Date.parse(asText(b.datetime));
      if (Number.isFinite(ad) && Number.isFinite(bd)) return ad - bd;
      return asText(a.datetime).localeCompare(asText(b.datetime));
    });
    return out;
  }

  function gridPopupHtml(row) {
    var tsRows = gridTimeSeriesRows(row);
    var title = 'x ' + asText(row.x) + ', y ' + asText(row.y);
    var chartRows = tsRows.map(function(r, i) {
      return {
        x: asText(r.datetime) || String(i + 1),
        value: r.value,
        parameter: r.parameter,
        unit: r.unit,
        coverage_id: r.coverage_id,
        z: r.z
      };
    });
    return '<div style=\"font-family:system-ui,sans-serif;font-size:12px;max-width:620px\">' +
      '<div style=\"font-weight:600;margin-bottom:6px\">' + escapeHtml(title) + '</div>' +
      popupRows(row) +
      '<div style=\"font-size:11px;color:#4b5563;margin:8px 0 4px\">Time series for this grid cell</div>' +
      edrPopupChartHtml({title: title, width: 580, height: 320, rows: chartRows}) +
      '</div>';
  }

  function renderGrid(slice) {
    var numeric = slice.map(function(row) {
      return finiteNumber(row.value);
    }).filter(function(v) { return v !== null; });
    var min = numeric.length ? Math.min.apply(null, numeric) : 0;
    var max = numeric.length ? Math.max.apply(null, numeric) : 1;
    slice.forEach(function(row) {
      if ([row.xmin, row.xmax, row.ymin, row.ymax].some(function(v) { return finiteNumber(v) === null; })) return;
      L.rectangle(
        [[Number(row.ymin), Number(row.xmin)], [Number(row.ymax), Number(row.xmax)]],
        {
          pane: paneName,
          className: 'edr-coverage-cell',
          stroke: false,
          fillColor: colorFor(row.value, min, max),
          fillOpacity: payload.opacity == null ? 0.75 : payload.opacity
        }
      ).bindPopup(gridPopupHtml(row), {maxWidth: 680, minWidth: 560}).addTo(layer);
    });
    addLegend(min, max, slice);
  }

  function renderProfiles(slice) {
    var groups = {};
    slice.forEach(function(row) {
      var key = asText(row.x) + '|' + asText(row.y) + '|' + asText(row.coverage_id);
      if (!groups[key]) groups[key] = [];
      groups[key].push(row);
    });
    Object.keys(groups).forEach(function(key) {
      var groupRows = groups[key];
      var first = groupRows[0];
      var lat = finiteNumber(first.y);
      var lng = finiteNumber(first.x);
      if (lat === null || lng === null) return;
      L.circleMarker([lat, lng], {
        radius: 7,
        color: '#2c7fb8',
        weight: 1,
        fillOpacity: 0.85
      }).bindPopup(
        '<div style=\"font-family:system-ui,sans-serif;font-size:12px;max-width:280px\">' +
        popupRows(first) + profileSvg(groupRows) + '</div>'
      ).addTo(layer);
    });
  }

  function render() {
    layer.clearLayers();
    if (legendControl) {
      map.removeControl(legendControl);
      legendControl = null;
    }
    var slice = rows.filter(rowMatches);
    if (payload.mode === 'grid') renderGrid(slice);
    if (payload.mode === 'profile') renderProfiles(slice);
  }

  if (payload.controls_enabled && payload.controls && payload.controls.length) {
    var control = L.control({position: 'topright'});
    control.onAdd = function() {
      var div = L.DomUtil.create('div', 'edr-coverage-control');
      div.style.background = 'rgba(255,255,255,0.94)';
      div.style.padding = '8px';
      div.style.borderRadius = '4px';
      div.style.boxShadow = '0 1px 4px rgba(0,0,0,0.25)';
      div.style.font = '12px system-ui, sans-serif';
      L.DomEvent.disableClickPropagation(div);
      payload.controls.forEach(function(spec) {
        var label = document.createElement('label');
        label.style.display = 'block';
        label.style.marginBottom = '6px';
        label.textContent = spec.label + ' ';
        var select = document.createElement('select');
        select.style.maxWidth = '180px';
        spec.values.forEach(function(value) {
          var opt = document.createElement('option');
          opt.value = value;
          opt.textContent = value;
          if (asText(active[spec.key]) === asText(value)) opt.selected = true;
          select.appendChild(opt);
        });
        select.addEventListener('change', function() {
          active[spec.key] = select.value;
          render();
        });
        label.appendChild(select);
        div.appendChild(label);
      });
      return div;
    };
    control.addTo(map);
  }

  render();
  if (payload.station_fit && payload.station_fit.type === 'view') {
    map.setView(
      [payload.station_fit.lat, payload.station_fit.lng],
      payload.station_fit.zoom || 9
    );
  } else if (payload.station_fit && payload.station_fit.type === 'bounds') {
    map.fitBounds([
      [payload.station_fit.ymin, payload.station_fit.xmin],
      [payload.station_fit.ymax, payload.station_fit.xmax]
    ]);
  } else if (payload.bounds) {
    map.fitBounds([
      [payload.bounds.ymin, payload.bounds.xmin],
      [payload.bounds.ymax, payload.bounds.xmax]
    ]);
  }
}
"
  )
}

detect_id_column <- function(df, id_col) {
  if (!is.null(id_col)) {
    if (!id_col %in% names(df)) {
      cli::cli_abort(
        "{.arg id_col} = {.val {id_col}} is not a column in {.arg locations}."
      )
    }
    return(as.character(df[[id_col]]))
  }
  for (candidate in c("id", "_id", "feature_id")) {
    if (candidate %in% names(df)) return(as.character(df[[candidate]]))
  }
  char_cols <- names(df)[vapply(df,
    function(x) is.character(x) || is.factor(x) || is.integer(x) || is.numeric(x),
    logical(1)
  )]
  if (length(char_cols) >= 1L) return(as.character(df[[char_cols[[1]]]]))
  cli::cli_abort(
    "Could not infer an id column in {.arg locations}; pass {.arg id_col}."
  )
}

detect_labels <- function(df, label_col, ids) {
  if (!is.null(label_col)) {
    if (!label_col %in% names(df)) {
      cli::cli_abort(
        "{.arg label_col} = {.val {label_col}} is not a column in {.arg locations}."
      )
    }
    return(as.character(df[[label_col]]))
  }
  for (candidate in c("name", "locationName", "title", "label")) {
    if (candidate %in% names(df)) return(as.character(df[[candidate]]))
  }
  ids
}

# Returns a list of per-feature data frames (or NULLs) aligned to `ids`.
#
# Joins `data` to `locations` in three modes:
#   - Named list of tibbles keyed by feature id → direct lookup.
#   - Tibble whose `location_col` matches some `ids` → id-based join.
#   - Tibble with x/y columns (e.g. from edr_cube / edr_area) where
#     `coverage_id` is a server-assigned sequence number that doesn't
#     match feature ids → spatial-proximity join via centroid distance.
per_feature_split <- function(data, ids, location_col, locations,
                              max_match_distance = NULL) {
  if (is.null(data)) return(rep(list(NULL), length(ids)))
  if (is.list(data) && !is.data.frame(data)) {
    return(lapply(ids, function(i) data[[as.character(i)]]))
  }
  df <- as_tidy_data(data)

  # 1. Try id-based join.
  if (location_col %in% names(df)) {
    candidate <- as.character(df[[location_col]])
    if (any(candidate %in% ids)) {
      split_df <- split(df, candidate)
      return(lapply(ids, function(i) split_df[[as.character(i)]]))
    }
  }

  # 2. Spatial fallback via x/y columns (the shape covjson_to_tibble
  #    produces from /cube and /area responses).
  if (all(c("x", "y") %in% names(df))) {
    return(spatial_split(df, locations, ids, max_match_distance))
  }

  cli::cli_abort(
    c("Could not match {.arg data} to {.arg locations}.",
      i = "Pass {.arg data} as a named list keyed by feature id, or include {.field {location_col}} / {.field x} + {.field y} columns.")
  )
}

# Group `df` by its (x, y) coordinates and assign each group to the
# nearest feature in `locations`. Multiple groups assigned to the same
# feature are appended in first-observed group order. Returns a list
# aligned to `ids` (NULL where no coverage matched).
spatial_split <- function(df, locations, ids, max_match_distance = NULL) {
  geom <- sf::st_geometry(locations)
  if (!all(sf::st_geometry_type(geom) == "POINT")) {
    geom <- suppressWarnings(sf::st_centroid(geom))
  }
  feat_xy <- sf::st_coordinates(geom)

  # Drop rows with missing x or y, then group by unique pair.
  ok  <- !is.na(df$x) & !is.na(df$y)
  df  <- df[ok, , drop = FALSE]
  key <- paste(df$x, df$y, sep = "_")
  group_keys <- unique(key)

  out <- rep(list(NULL), length(ids))
  for (k in group_keys) {
    sub <- df[key == k, , drop = FALSE]
    cov_xy <- c(sub$x[[1]], sub$y[[1]])
    d2 <- (feat_xy[, 1] - cov_xy[[1]])^2 + (feat_xy[, 2] - cov_xy[[2]])^2
    i <- which.min(d2)
    if (length(i) == 1L && !is.na(i) &&
        (is.null(max_match_distance) || sqrt(d2[[i]]) <= max_match_distance)) {
      out[[i]] <- vctrs::vec_rbind(out[[i]], sub)
    }
  }
  out
}

check_max_match_distance <- function(max_match_distance,
                                     call = rlang::caller_env()) {
  if (is.null(max_match_distance)) return(invisible())
  if (!is.numeric(max_match_distance) || length(max_match_distance) != 1L ||
      !is.finite(max_match_distance) || max_match_distance < 0) {
    cli::cli_abort(
      "{.arg max_match_distance} must be a single non-negative number or NULL.",
      call = call
    )
  }
  invisible()
}

build_feature_popup <- function(df,
                                attrs,
                                label,
                                popup_mode,
                                plot_width,
                                plot_height,
                                plot_dpi,
                                csv_name) {
  display_px <- popup_chart_width_px(plot_width, plot_dpi)
  display_height_px <- popup_chart_height_px(plot_height, plot_dpi)
  if (is.null(df) || nrow(df) == 0L) {
    return(feature_popup_html(
      attrs = attrs, label = label, mode = "table",
      plot_width = display_px,
      plot_height = display_height_px
    ))
  }
  chart_payload <- NULL
  csv_uri  <- NULL
  if (popup_mode %in% c("plot", "plot+csv", "all")) {
    chart_payload <- interactive_chart_payload(
      df,
      title = label,
      width = display_px,
      height = display_height_px
    )
  }
  if (popup_mode %in% c("csv", "plot+csv", "all")) {
    csv_uri <- csv_data_uri(df)
  }
  feature_popup_html(
    chart_payload = chart_payload,
    csv_uri      = csv_uri,
    attrs        = attrs,
    label        = label,
    mode         = popup_mode,
    csv_filename = csv_name,
    plot_width   = display_px,
    plot_height  = display_height_px
  )
}
