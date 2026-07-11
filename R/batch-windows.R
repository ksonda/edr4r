# Internal helpers for finite station-by-time request plans.

batch_datetime_windows <- function(datetime,
                                   chunk = NULL,
                                   max_windows = Inf,
                                   n_locations = 1L,
                                   max_requests = NULL,
                                   call = rlang::caller_env()) {
  label <- if (is.character(datetime) && length(datetime) == 2L) {
    paste(datetime, collapse = "/")
  } else {
    batch_datetime_label(datetime)
  }
  if (is.null(chunk)) return(label)

  spec <- parse_batch_chunk(chunk, call = call)
  interval <- parse_batch_interval(label, call = call)
  if (!isTRUE(interval$start < interval$end)) {
    cli::cli_abort(
      "The {.arg datetime} start must be before its end when {.arg chunk} is supplied.",
      call = call
    )
  }

  windows <- character()
  left <- interval$start
  index <- 1
  repeat {
    candidate <- if (batch_chunk_reaches_end(
      interval$start, interval$end, spec, index
    )) {
      interval$end
    } else {
      batch_chunk_boundary(
        interval$start,
        spec = spec,
        index = index,
        type = interval$type
      )
    }
    right <- if (candidate > interval$end) interval$end else candidate
    if (!isTRUE(right > left)) {
      cli::cli_abort(
        "{.arg chunk} did not advance the request interval.",
        call = call
      )
    }

    windows <- c(
      windows,
      paste0(
        format_batch_boundary(left, interval$type, interval$precision),
        "/",
        format_batch_boundary(right, interval$type, interval$precision)
      )
    )
    if (isTRUE(right >= interval$end)) break

    if (length(windows) >= max_windows) {
      abort_batch_window_cap(
        max_windows = max_windows,
        n_locations = n_locations,
        max_requests = max_requests,
        call = call
      )
    }
    left <- right
    index <- index + 1
  }
  windows
}

batch_chunk_reaches_end <- function(start, end, spec, index) {
  amount <- as.double(spec$amount) * as.double(index)
  if (spec$unit %in% c("day", "week")) {
    days <- amount * if (identical(spec$unit, "week")) 7 else 1
    span_days <- as.numeric(difftime(end, start, units = "days"))
    return(days >= span_days)
  }

  months <- amount * if (identical(spec$unit, "year")) 12 else 1
  start_index <- as.integer(format(start, "%Y", tz = "UTC")) * 12 +
    as.integer(format(start, "%m", tz = "UTC"))
  end_index <- as.integer(format(end, "%Y", tz = "UTC")) * 12 +
    as.integer(format(end, "%m", tz = "UTC"))
  # Equality still needs anchored day/time arithmetic (Jan 1 + one month is
  # before Feb 15); a strictly later target month is necessarily past `end`.
  months > (end_index - start_index)
}

parse_batch_chunk <- function(chunk, call = rlang::caller_env()) {
  if (!is.character(chunk) || length(chunk) != 1L || is.na(chunk)) {
    cli::cli_abort(
      paste0(
        "{.arg chunk} must be one positive-integer calendar interval, ",
        "such as {.val 1 day}, {.val 2 weeks}, {.val 1 month}, or {.val 1 year}."
      ),
      call = call
    )
  }
  value <- tolower(trimws(chunk))
  match <- regexec(
    "^([1-9][0-9]*)[[:space:]]*(day|week|month|year)s?$",
    value,
    perl = TRUE
  )
  parts <- regmatches(value, match)[[1L]]
  if (length(parts) != 3L) {
    cli::cli_abort(
      paste0(
        "{.arg chunk} must be one positive-integer calendar interval, ",
        "such as {.val 1 day}, {.val 2 weeks}, {.val 1 month}, or {.val 1 year}."
      ),
      call = call
    )
  }
  amount <- suppressWarnings(as.numeric(parts[[2L]]))
  if (!is.finite(amount) || amount > .Machine$integer.max) {
    cli::cli_abort("{.arg chunk} is too large.", call = call)
  }
  list(amount = as.integer(amount), unit = parts[[3L]])
}

parse_batch_interval <- function(datetime, call = rlang::caller_env()) {
  if (!is.character(datetime) || length(datetime) != 1L ||
      is.na(datetime) || !nzchar(datetime)) {
    cli::cli_abort(
      "{.arg chunk} requires a bounded {.arg datetime} interval.",
      call = call
    )
  }
  bounds <- trimws(strsplit(datetime, "/", fixed = TRUE)[[1L]])
  if (length(bounds) != 2L || any(!nzchar(bounds)) || any(bounds == "..")) {
    cli::cli_abort(
      "{.arg chunk} requires a bounded {.arg datetime} interval.",
      call = call
    )
  }
  date_only <- grepl("^\\d{4}-\\d{2}-\\d{2}$", bounds)
  if (all(date_only)) {
    parsed <- suppressWarnings(as.Date(bounds, format = "%Y-%m-%d"))
    if (anyNA(parsed)) {
      cli::cli_abort(
        "{.arg datetime} contains an invalid calendar date.",
        call = call
      )
    }
    return(list(
      start = parsed[[1L]], end = parsed[[2L]], type = "date", precision = 0L
    ))
  }
  if (any(date_only)) {
    cli::cli_abort(
      "{.arg datetime} must use the same date or timestamp precision at both bounds.",
      call = call
    )
  }

  precision <- vapply(bounds, batch_fractional_precision, integer(1))
  if (any(precision > 6L)) {
    cli::cli_abort(
      "{.arg datetime} supports at most six fractional-second digits when {.arg chunk} is supplied.",
      call = call
    )
  }

  parsed <- vapply(
    bounds,
    parse_batch_timestamp,
    numeric(1),
    call = call
  )
  output_precision <- max(precision)
  representable <- mapply(
    batch_fraction_is_representable,
    parsed,
    bounds,
    MoreArgs = list(precision = output_precision),
    USE.NAMES = FALSE
  )
  if (!all(representable)) {
    value <- bounds[[which(!representable)[[1L]]]]
    cli::cli_abort(c(
      "The fractional seconds in {.val {value}} cannot be represented without loss.",
      i = "Use fewer fractional-second digits or a datetime closer to the POSIX epoch."
    ), call = call)
  }
  list(
    start = as.POSIXct(parsed[[1L]], origin = "1970-01-01", tz = "UTC"),
    end = as.POSIXct(parsed[[2L]], origin = "1970-01-01", tz = "UTC"),
    type = "timestamp",
    precision = output_precision
  )
}

batch_fractional_precision <- function(value) {
  nchar(batch_fractional_digits(value))
}

batch_fractional_digits <- function(value) {
  match <- regexec(
    "\\.([0-9]+)(?:Z|[+-]\\d{2}:?\\d{2})?$",
    value,
    perl = TRUE
  )
  parts <- regmatches(value, match)[[1L]]
  if (length(parts) == 0L) "" else parts[[2L]]
}

batch_fraction_is_representable <- function(epoch, value, precision) {
  if (precision == 0L) return(TRUE)
  scale <- 10^precision
  actual <- round((epoch - floor(epoch)) * scale)
  if (actual >= scale) actual <- 0
  digits <- batch_fractional_digits(value)
  expected <- if (!nzchar(digits)) {
    0L
  } else {
    as.integer(paste0(digits, strrep("0", precision - nchar(digits))))
  }
  identical(as.integer(actual), expected)
}

parse_batch_timestamp <- function(value, call = rlang::caller_env()) {
  pattern <- paste0(
    "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}",
    "(?::\\d{2}(?:\\.\\d+)?)?",
    "(?:Z|[+-]\\d{2}:?\\d{2})?$"
  )
  if (!grepl(pattern, value, perl = TRUE)) {
    cli::cli_abort(
      "Could not parse {.val {value}} as an ISO-8601 datetime bound.",
      call = call
    )
  }

  # Base R needs an explicit seconds field. EDR metadata commonly uses
  # minute precision (for example, 00:00Z), so add :00 before the zone.
  if (grepl("T\\d{2}:\\d{2}(?:Z|[+-]\\d{2}:?\\d{2})?$", value, perl = TRUE)) {
    value <- sub(
      "^(.*T\\d{2}:\\d{2})(Z|[+-]\\d{2}:?\\d{2})?$",
      "\\1:00\\2",
      value,
      perl = TRUE
    )
  }
  seconds <- sub("^.*T\\d{2}:\\d{2}:(\\d{2}(?:\\.\\d+)?).*$", "\\1", value)
  if (identical(seconds, value) || suppressWarnings(as.numeric(seconds)) >= 60) {
    cli::cli_abort(
      "Could not parse {.val {value}} as an ISO-8601 datetime bound.",
      call = call
    )
  }

  has_zone <- grepl("(?:Z|[+-]\\d{2}:?\\d{2})$", value, perl = TRUE)
  normalized <- sub("Z$", "+0000", value)
  normalized <- sub("([+-]\\d{2}):(\\d{2})$", "\\1\\2", normalized)
  parsed <- suppressWarnings(as.POSIXct(
    normalized,
    format = if (has_zone) "%Y-%m-%dT%H:%M:%OS%z" else "%Y-%m-%dT%H:%M:%OS",
    tz = "UTC"
  ))
  if (is.na(parsed)) {
    cli::cli_abort(
      "Could not parse {.val {value}} as an ISO-8601 datetime bound.",
      call = call
    )
  }
  as.numeric(parsed)
}

batch_chunk_boundary <- function(start, spec, index, type) {
  amount <- as.double(spec$amount) * as.double(index)
  if (spec$unit %in% c("day", "week")) {
    days <- amount * if (identical(spec$unit, "week")) 7 else 1
    if (identical(type, "date")) return(start + days)
    return(start + days * 86400)
  }
  months <- amount * if (identical(spec$unit, "year")) 12 else 1
  add_batch_calendar_months(start, months, type)
}

add_batch_calendar_months <- function(start, months, type) {
  year <- as.integer(format(start, "%Y", tz = "UTC"))
  month <- as.integer(format(start, "%m", tz = "UTC"))
  day <- as.integer(format(start, "%d", tz = "UTC"))
  target <- year * 12 + (month - 1L) + as.integer(months)
  target_year <- target %/% 12
  target_month <- target %% 12 + 1L
  following <- if (target_month == 12L) {
    as.Date(sprintf("%04d-01-01", target_year + 1L))
  } else {
    as.Date(sprintf("%04d-%02d-01", target_year, target_month + 1L))
  }
  target_day <- min(day, as.integer(format(following - 1, "%d")))
  target_date <- as.Date(sprintf(
    "%04d-%02d-%02d", target_year, target_month, target_day
  ))
  if (identical(type, "date")) return(target_date)

  source_midnight <- as.POSIXct(
    format(start, "%Y-%m-%d", tz = "UTC"),
    tz = "UTC"
  )
  time_of_day <- as.numeric(start) - as.numeric(source_midnight)
  midnight <- as.POSIXct(target_date, tz = "UTC")
  midnight + time_of_day
}

format_batch_boundary <- function(value, type, precision = 0L) {
  if (identical(type, "date")) return(format(value, "%Y-%m-%d"))

  # Formatting POSIXct with %OS can expose binary floating-point artifacts
  # (for example, .1 as .099999) or lose a microsecond. Round explicitly at
  # the precision accepted by parse_batch_interval() instead.
  epoch <- as.numeric(value)
  scale <- 10^precision
  whole <- floor(epoch)
  fraction <- round((epoch - whole) * scale)
  if (fraction >= scale) {
    whole <- whole + 1
    fraction <- 0
  }
  out <- format(
    as.POSIXct(whole, origin = "1970-01-01", tz = "UTC"),
    "%Y-%m-%dT%H:%M:%S",
    tz = "UTC"
  )
  if (precision > 0L) {
    out <- paste0(out, ".", sprintf("%0*d", precision, as.integer(fraction)))
  }
  paste0(out, "Z")
}

abort_batch_window_cap <- function(max_windows,
                                   n_locations,
                                   max_requests,
                                   call = rlang::caller_env()) {
  if (!is.null(max_requests)) {
    at_least <- as.double(n_locations) * (as.double(max_windows) + 1)
    cli::cli_abort(c(
      "The expanded batch would issue at least {at_least} requests, exceeding {.arg max_requests} = {max_requests}.",
      i = "Increase {.arg chunk}, reduce {.arg location_id}, or explicitly raise the finite request cap."
    ), call = call)
  }
  cli::cli_abort(
    "Time chunking would create more than {max_windows} windows.",
    call = call
  )
}

deduplicate_batch_window_rows <- function(data) {
  if (nrow(data) == 0L) return(data)
  key_columns <- setdiff(names(data), ".request_id")
  keep <- rep(FALSE, nrow(data))

  groups <- vctrs::vec_group_loc(data[key_columns])
  for (rows in groups$loc) {
    earliest_request <- min(data$.request_id[rows])
    keep[rows[data$.request_id[rows] == earliest_request]] <- TRUE
  }
  data[keep, , drop = FALSE]
}
