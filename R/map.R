#' Map EDR locations or coverage data
#'
#' Builds a [leaflet] map of station features or gridded/profile
#' CoverageJSON data. Station maps can show per-station popups with
#' inline plots and CSV downloads. Coverage maps keep all supplied
#' parameters, times, and vertical levels in the widget and expose
#' in-map controls for choosing the active slice.
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
#'   parameters get plotted in each popup.
#' @param plot_width,plot_height Popup plot dimensions in inches
#'   (passed to the underlying SVG device). Display size in pixels is
#'   `plot_width * plot_dpi` by `plot_height * plot_dpi`.
#' @param plot_dpi Display dots-per-inch for the inline SVG. Default 72;
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
#'   controls for available slice dimensions (`parameter`, `datetime`,
#'   and `z` for grids).
#' @param initial Named list of initial coverage-map selections, e.g.
#'   `list(parameter = "temperature", datetime = "2024-01-01", z = 0)`.
#' @param grid_opacity Fill opacity for gridded coverage cells.
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
                    grid_opacity       = 0.75) {
  check_installed_for("leaflet", "render maps")
  mode <- match.arg(mode)
  popup <- match.arg(popup)
  check_max_match_distance(max_match_distance)

  resolved_mode <- resolve_map_mode(locations, mode)
  if (resolved_mode %in% c("grid", "profile", "time")) {
    return(coverage_leaflet_map(
      locations,
      mode = resolved_mode,
      controls = controls,
      initial = initial,
      grid_opacity = grid_opacity,
      tile_provider = tile_provider,
      legend = legend
    ))
  }

  check_installed_for("sf", "render maps")
  locations <- as_locations_sf(locations)

  needs_data <- popup %in% c("plot", "csv", "plot+csv", "all")
  if (needs_data && is.null(data)) {
    cli::cli_abort(
      c("{.arg data} is required for popup mode {.val {popup}}.",
        i = "Pass a tidy tibble, a named list of tibbles, or use {.val table}.")
    )
  }

  attr_table <- sf::st_drop_geometry(locations)
  ids    <- detect_id_column(attr_table, id_col)
  labels <- detect_labels(attr_table, label_col, ids)
  per_feature_data <- per_feature_split(
    data, ids, location_col, locations, max_match_distance
  )
  # When `data` is NULL the matched/unmatched distinction doesn't apply —
  # everyone is drawn as a regular station marker.
  has_data <- if (is.null(data)) {
    rep(TRUE, length(ids))
  } else {
    !vapply(per_feature_data, is.null, logical(1))
  }

  # Drop data-less stations entirely if the caller doesn't want them.
  if (!is.null(data) && !show_unmatched) {
    keep <- has_data
    if (!any(keep)) {
      cli::cli_abort(
        c("No stations in {.arg locations} joined to {.arg data}.",
          i = "Check that ids overlap, or set {.code show_unmatched = TRUE}.")
      )
    }
    locations        <- locations[keep, , drop = FALSE]
    attr_table       <- attr_table[keep, , drop = FALSE]
    ids              <- ids[keep]
    labels           <- labels[keep]
    per_feature_data <- per_feature_data[keep]
    has_data         <- has_data[keep]
  }

  popups <- vapply(
    seq_along(ids),
    function(i) build_feature_popup(
      df          = per_feature_data[[i]],
      attrs       = if (popup %in% c("table", "all")) as.list(attr_table[i, , drop = FALSE]) else NULL,
      label       = labels[[i]],
      popup_mode  = popup,
      parameter   = parameter,
      plot_width  = plot_width,
      plot_height = plot_height,
      plot_dpi    = plot_dpi,
      csv_name    = paste0("station-", ids[[i]], ".csv")
    ),
    character(1)
  )

  # Reduce non-point geometries (lines, polygons, mixed) to centroids so
  # we can place a single marker per feature. sf warns on lon/lat
  # centroids; suppress that since it's expected for monitoring sites.
  geom <- sf::st_geometry(locations)
  if (!all(sf::st_geometry_type(geom) == "POINT")) {
    geom <- suppressWarnings(sf::st_centroid(geom))
  }
  coords <- sf::st_coordinates(geom)

  popup_opts <- leaflet::popupOptions(
    maxWidth = ceiling(plot_width * plot_dpi + 48)
  )

  m <- leaflet::leaflet() |>
    leaflet::addProviderTiles(tile_provider)

  # Draw unmatched first, matched on top — leaflet renders later layers
  # above earlier ones, so the data-bearing markers stay clickable even
  # in a dense cluster of grey ones.
  if (any(!has_data)) {
    idx <- which(!has_data)
    m <- leaflet::addCircleMarkers(
      m,
      lng         = coords[idx, 1],
      lat         = coords[idx, 2],
      radius      = max(marker_radius - 1L, 3L),
      color       = unmatched_color,
      stroke      = TRUE,
      weight      = 1,
      fillOpacity = 0.5,
      opacity     = 0.6,
      popup       = popups[idx],
      label       = labels[idx],
      popupOptions = popup_opts,
      group       = "No data in window"
    )
  }
  if (any(has_data)) {
    idx <- which(has_data)
    m <- leaflet::addCircleMarkers(
      m,
      lng         = coords[idx, 1],
      lat         = coords[idx, 2],
      radius      = marker_radius,
      color       = matched_color,
      stroke      = TRUE,
      weight      = 1,
      fillOpacity = 0.9,
      opacity     = 1,
      popup       = popups[idx],
      label       = labels[idx],
      popupOptions = popup_opts,
      group       = "Has data"
    )
  }

  if (isTRUE(legend) && !is.null(data) && any(has_data) && any(!has_data)) {
    m <- leaflet::addLegend(
      m,
      position = "bottomright",
      colors   = c(matched_color, unmatched_color),
      labels   = c("Has data", "No data in window"),
      opacity  = 0.9,
      title    = "Stations"
    )
  }

  if (nrow(coords) > 1L) {
    m <- leaflet::fitBounds(
      m,
      lng1 = min(coords[, 1]), lat1 = min(coords[, 2]),
      lng2 = max(coords[, 1]), lat2 = max(coords[, 2])
    )
  } else if (nrow(coords) == 1L) {
    m <- leaflet::setView(m, lng = coords[1, 1], lat = coords[1, 2], zoom = 9)
  }

  m
}

#' Save a map to a standalone HTML file
#'
#' Thin wrapper around [htmlwidgets::saveWidget()] for the leaflet
#' map returned by [edr_map()] or [edr_explore()]. With
#' `selfcontained = TRUE` (the default), embedded plot SVGs and CSV
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

coverage_leaflet_map <- function(data,
                                 mode,
                                 controls,
                                 initial,
                                 grid_opacity,
                                 tile_provider,
                                 legend) {
  check_installed_for("htmlwidgets", "render interactive coverage maps")
  data <- as_tidy_data(data)
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
  if (mode == "profile" && !all(c("x", "y", "z") %in% names(data))) {
    cli::cli_abort(
      "{.code mode = \"profile\"} requires {.field x}, {.field y}, and {.field z} columns."
    )
  }

  payload <- coverage_map_payload(data, mode, controls, initial, grid_opacity, legend)
  m <- leaflet::leaflet() |>
    leaflet::addProviderTiles(tile_provider)
  htmlwidgets::onRender(m, coverage_map_js(), data = payload)
}

coverage_map_payload <- function(data, mode, controls, initial,
                                 grid_opacity, legend) {
  data <- data[!is.na(data$x) & !is.na(data$y), , drop = FALSE]
  if (nrow(data) == 0L) {
    cli::cli_abort("Coverage map data must include at least one non-missing x/y coordinate.")
  }

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

  control_specs <- coverage_control_specs(data, mode)
  initial <- normalize_initial_selection(initial, control_specs)

  rows <- lapply(seq_len(nrow(data)), function(i) {
    row <- list(
      x = as.numeric(data$x[[i]]),
      y = as.numeric(data$y[[i]]),
      value = data$value[[i]],
      parameter = data$.edr_parameter[[i]],
      datetime = data$.edr_datetime[[i]],
      z = data$.edr_z[[i]],
      coverage_id = if ("coverage_id" %in% names(data)) as.character(data$coverage_id[[i]]) else ""
    )
    if (mode == "grid") {
      row$xmin <- as.numeric(data$.edr_xmin[[i]])
      row$xmax <- as.numeric(data$.edr_xmax[[i]])
      row$ymin <- as.numeric(data$.edr_ymin[[i]])
      row$ymax <- as.numeric(data$.edr_ymax[[i]])
    }
    row
  })

  list(
    mode = mode,
    rows = rows,
    controls = control_specs,
    controls_enabled = isTRUE(controls),
    initial = initial,
    opacity = grid_opacity,
    legend = isTRUE(legend),
    bounds = list(
      xmin = min(data$x, na.rm = TRUE),
      xmax = max(data$x, na.rm = TRUE),
      ymin = min(data$y, na.rm = TRUE),
      ymax = max(data$y, na.rm = TRUE)
    )
  )
}

coverage_control_specs <- function(data, mode) {
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
    selected <- initial[[key]] %||% vals[[1]]
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

coverage_map_js <- function() {
  "
function(el, x, payload) {
  var map = this;
  var rows = payload.rows || [];
  var active = payload.initial || {};
  var layer = L.layerGroup().addTo(map);
  var legendControl = null;

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
    var n = Number(v);
    return Number.isFinite(n) ? n : null;
  }

  function colorFor(value, min, max) {
    var v = finiteNumber(value);
    if (v === null) return '#bdbdbd';
    if (max <= min) return '#2c7fb8';
    var t = Math.max(0, Math.min(1, (v - min) / (max - min)));
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
    ['parameter', 'datetime', 'z', 'coverage_id', 'value'].forEach(function(key) {
      if (asText(row[key]) !== '') {
        out += '<tr><td style=\"color:#666;padding:2px 8px 2px 0\">' +
          escapeHtml(key) + '</td><td style=\"padding:2px\">' +
          escapeHtml(row[key]) + '</td></tr>';
      }
    });
    return out + '</table>';
  }

  function addLegend(min, max) {
    if (!payload.legend || payload.mode !== 'grid') return;
    if (legendControl) map.removeControl(legendControl);
    legendControl = L.control({position: 'bottomright'});
    legendControl.onAdd = function() {
      var div = L.DomUtil.create('div', 'edr-coverage-legend');
      div.style.background = 'rgba(255,255,255,0.92)';
      div.style.padding = '8px';
      div.style.borderRadius = '4px';
      div.style.boxShadow = '0 1px 4px rgba(0,0,0,0.25)';
      div.style.font = '12px system-ui, sans-serif';
      div.innerHTML =
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
          stroke: false,
          fillColor: colorFor(row.value, min, max),
          fillOpacity: payload.opacity == null ? 0.75 : payload.opacity
        }
      ).bindPopup(popupRows(row)).addTo(layer);
    });
    addLegend(min, max);
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
      L.circleMarker([Number(first.y), Number(first.x)], {
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
  if (payload.bounds) {
    map.fitBounds([
      [payload.bounds.ymin, payload.bounds.xmin],
      [payload.bounds.ymax, payload.bounds.xmax]
    ]);
  }
}
"
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
# nearest feature in `locations`. Returns a list aligned to `ids` (NULL
# where no coverage matched).
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
  groups <- split(df, key)

  out <- rep(list(NULL), length(ids))
  for (k in names(groups)) {
    sub <- groups[[k]]
    cov_xy <- c(sub$x[[1]], sub$y[[1]])
    d2 <- (feat_xy[, 1] - cov_xy[[1]])^2 + (feat_xy[, 2] - cov_xy[[2]])^2
    i <- which.min(d2)
    if (length(i) == 1L && !is.na(i) &&
        (is.null(max_match_distance) || sqrt(d2[[i]]) <= max_match_distance)) {
      out[[i]] <- sub
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
                                parameter,
                                plot_width,
                                plot_height,
                                plot_dpi,
                                csv_name) {
  display_px <- as.integer(plot_width * plot_dpi)
  if (is.null(df) || nrow(df) == 0L) {
    return(feature_popup_html(
      attrs = attrs, label = label, mode = "table",
      plot_width = display_px
    ))
  }
  if (!is.null(parameter)) {
    df <- df[df$parameter %in% parameter, , drop = FALSE]
  }
  plot_uri <- NULL
  csv_uri  <- NULL
  if (popup_mode %in% c("plot", "plot+csv", "all")) {
    p <- edr_plot(df, parameter = parameter)
    plot_uri <- plot_to_svg_uri(p, width = plot_width, height = plot_height)
  }
  if (popup_mode %in% c("csv", "plot+csv", "all")) {
    csv_uri <- csv_data_uri(df)
  }
  feature_popup_html(
    plot_uri     = plot_uri,
    csv_uri      = csv_uri,
    attrs        = attrs,
    label        = label,
    mode         = popup_mode,
    csv_filename = csv_name,
    plot_width   = display_px
  )
}
