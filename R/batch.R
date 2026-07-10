#' Fetch data for multiple EDR locations
#'
#' Runs one [edr_location()] request for each explicitly supplied location id.
#' Requests are made sequentially and in input order. The complete request
#' plan is validated before any network activity, and `max_requests` provides
#' a finite guard against accidental fan-out.
#'
#' `format = "covjson"` responses are converted with
#' [covjson_to_tibble()]. CSV responses are already parsed as tibbles by
#' [edr_location()]. Successful rows are combined with `.request_id` and
#' `.location_id` provenance columns.
#'
#' @param client An [edr_client()].
#' @param collection_id Collection identifier.
#' @param location_id A non-empty character vector of unique location ids.
#' @param datetime Optional ISO-8601 instant or interval shared by every
#'   request.
#' @param parameter_name Optional character vector of parameter names shared
#'   by every request.
#' @param z Optional vertical level filter.
#' @param crs Optional CRS URI for the response.
#' @param format Either `"covjson"` (default) or `"csv"`.
#' @param ... Additional query parameters forwarded to every
#'   [edr_location()] request, such as `limit`.
#' @param max_requests Finite positive integer limiting the number of HTTP
#'   requests. Defaults to 100.
#' @param on_error Either `"stop"` (default), which re-signals the original
#'   condition immediately, or `"collect"`, which records failures and
#'   continues through the bounded request plan.
#' @param progress If `TRUE`, display a cli progress bar for multi-request
#'   batches. Defaults to [interactive()].
#' @param instance_id Optional collection instance identifier. Every request
#'   remains beneath that instance path.
#'
#' @return An object of class `edr_location_batch` and `edr_batch`. It contains
#'   `requests`, a typed request-status tibble; `data`, a combined data tibble;
#'   and `errors`, a typed tibble of collected conditions. The object also
#'   records `collection_id`, `instance_id`, and `format`.
#' @export
edr_location_batch <- function(client,
                               collection_id,
                               location_id,
                               datetime = NULL,
                               parameter_name = NULL,
                               z = NULL,
                               crs = NULL,
                               format = c("covjson", "csv"),
                               ...,
                               max_requests = 100L,
                               on_error = c("stop", "collect"),
                               progress = interactive(),
                               instance_id = NULL) {
  check_client(client)
  format <- match.arg(format)
  on_error <- match.arg(on_error)
  check_batch_progress(progress)
  check_batch_max_requests(max_requests)

  location_id <- check_batch_location_ids(location_id)
  n_requests <- length(location_id)
  if (n_requests > max_requests) {
    cli::cli_abort(c(
      "The batch would issue {n_requests} requests, exceeding {.arg max_requests} = {max_requests}.",
      i = "Reduce {.arg location_id} or explicitly raise the finite request cap."
    ))
  }

  collection_id <- check_collection_id(collection_id)
  # Validate collection/instance path segments and every location id before
  # allowing the first request to run. Keep the original ids for provenance.
  collection_query_path(collection_id, "locations", instance_id)
  invisible(vapply(
    location_id,
    check_path_id,
    character(1),
    arg = "location_id",
    USE.NAMES = FALSE
  ))

  dots <- list(...)
  query <- do.call(
    common_query,
    c(
      list(
        datetime = datetime,
        parameter_name = parameter_name,
        z = z,
        crs = crs
      ),
      dots
    )
  )
  # Exercise the same query validation and serialization used by
  # edr_request(), without performing a request.
  invisible(build_query_string(prepare_query(query, format = format)))

  plan <- tibble::tibble(
    request_id = seq_len(n_requests),
    location_id = location_id,
    datetime = rep(batch_datetime_label(query$datetime), n_requests),
    status = rep("pending", n_requests),
    n_rows = rep(NA_integer_, n_requests)
  )

  executed <- run_location_batch_plan(
    client = client,
    collection_id = collection_id,
    plan = plan,
    datetime = datetime,
    parameter_name = parameter_name,
    z = z,
    crs = crs,
    format = format,
    dots = dots,
    on_error = on_error,
    progress = progress,
    instance_id = instance_id
  )

  structure(
    list(
      collection_id = collection_id,
      instance_id = instance_id,
      format = format,
      requests = executed$requests,
      data = bind_location_batch_data(
        executed$results,
        executed$requests,
        format = format
      ),
      errors = executed$errors
    ),
    class = c("edr_location_batch", "edr_batch", "list")
  )
}

run_location_batch_plan <- function(client,
                                    collection_id,
                                    plan,
                                    datetime,
                                    parameter_name,
                                    z,
                                    crs,
                                    format,
                                    dots,
                                    on_error,
                                    progress,
                                    instance_id) {
  n_requests <- nrow(plan)
  results <- vector("list", n_requests)
  error_rows <- vector("list", n_requests)

  progress_env <- environment()
  show_progress <- isTRUE(progress) && n_requests > 1L
  if (show_progress) {
    cli::cli_progress_bar(
      "Fetching location data",
      total = n_requests,
      .envir = progress_env
    )
    on.exit(cli::cli_progress_done(.envir = progress_env), add = TRUE)
  }

  for (i in seq_len(n_requests)) {
    args <- c(
      list(
        client = client,
        collection_id = collection_id,
        location_id = plan$location_id[[i]],
        datetime = datetime,
        parameter_name = parameter_name,
        z = z,
        crs = crs,
        format = format
      ),
      dots,
      list(instance_id = instance_id)
    )

    outcome <- tryCatch(
      {
        response <- do.call(edr_location, args)
        data <- if (identical(format, "covjson")) {
          covjson_to_tibble(response)
        } else {
          response
        }
        if (!is.data.frame(data)) {
          cli::cli_abort(
            "Location {.val {plan$location_id[[i]]}} did not produce tabular data."
          )
        }
        if (any(c(".request_id", ".location_id") %in% names(data))) {
          cli::cli_abort(c(
            "Location {.val {plan$location_id[[i]]}} returned reserved provenance columns.",
            i = "Columns {.field .request_id} and {.field .location_id} are reserved by {.fn edr_location_batch}."
          ))
        }
        tibble::as_tibble(data)
      },
      error = function(e) e
    )

    if (show_progress) {
      cli::cli_progress_update(.envir = progress_env)
    }

    if (inherits(outcome, "error")) {
      if (identical(on_error, "stop")) {
        rlang::cnd_signal(outcome)
      }
      plan$status[[i]] <- "error"
      error_rows[[i]] <- batch_error_row(
        outcome,
        request_id = plan$request_id[[i]],
        location_id = plan$location_id[[i]]
      )
      next
    }

    results[[i]] <- outcome
    plan$n_rows[[i]] <- nrow(outcome)
    plan$status[[i]] <- if (nrow(outcome) == 0L) "empty" else "success"
  }

  errors <- error_rows[!vapply(error_rows, is.null, logical(1))]
  if (length(errors) == 0L) {
    errors <- empty_batch_errors()
  } else {
    errors <- vctrs::vec_rbind(!!!errors)
  }

  list(requests = plan, results = results, errors = errors)
}

bind_location_batch_data <- function(results, requests, format) {
  pieces <- vector("list", length(results))
  for (i in seq_along(results)) {
    data <- results[[i]]
    if (is.null(data)) next
    n <- nrow(data)
    pieces[[i]] <- tibble::add_column(
      data,
      .request_id = rep.int(requests$request_id[[i]], n),
      .location_id = rep(requests$location_id[[i]], n),
      .before = 1L
    )
  }
  pieces <- pieces[!vapply(pieces, is.null, logical(1))]

  if (length(pieces) == 0L) {
    return(empty_location_batch_data(format))
  }
  if (length(pieces) == 1L) return(pieces[[1L]])

  bound <- tryCatch(
    vctrs::vec_rbind(!!!pieces),
    error = function(e) e
  )
  if (!inherits(bound, "error")) return(bound)

  conflicts <- batch_conflicting_columns(pieces)
  if (length(conflicts) == 0L ||
      !all(vapply(conflicts, batch_column_is_castable, logical(1), pieces = pieces))) {
    rlang::cnd_signal(bound)
  }

  for (column in conflicts) {
    pieces <- lapply(pieces, function(piece) {
      if (column %in% names(piece)) {
        piece[[column]] <- as.character(piece[[column]])
      }
      piece
    })
  }
  cli::cli_warn(
    "Demoted batch column{?s} to character: {.field {conflicts}}; response types differed across locations."
  )
  vctrs::vec_rbind(!!!pieces)
}

batch_conflicting_columns <- function(pieces) {
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

batch_column_is_castable <- function(column, pieces) {
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

empty_location_batch_data <- function(format) {
  data <- if (identical(format, "covjson")) {
    empty_covjson_tibble()
  } else {
    tibble::tibble()
  }
  tibble::add_column(
    data,
    .request_id = integer(),
    .location_id = character(),
    .before = 1L
  )
}

batch_error_row <- function(error, request_id, location_id) {
  status <- error$status
  if (is.null(status) && inherits(error$resp, "httr2_response")) {
    status <- httr2::resp_status(error$resp)
  }
  if (!is.numeric(status) || length(status) != 1L || is.na(status)) {
    status <- NA_integer_
  }
  message <- as.character(conditionMessage(error))
  body <- error$body
  if (is.character(body) && length(body) >= 1L && !is.na(body[[1L]]) &&
      nzchar(body[[1L]]) && !grepl(body[[1L]], message, fixed = TRUE)) {
    message <- paste(message, body[[1L]])
  }
  tibble::tibble(
    request_id = as.integer(request_id),
    location_id = as.character(location_id),
    condition_class = class(error)[[1L]],
    http_status = as.integer(status),
    message = message,
    condition = list(error)
  )
}

empty_batch_errors <- function() {
  tibble::tibble(
    request_id = integer(),
    location_id = character(),
    condition_class = character(),
    http_status = integer(),
    message = character(),
    condition = list()
  )
}

batch_datetime_label <- function(datetime) {
  if (is.null(datetime) || length(datetime) == 0L) return(NA_character_)
  paste(as.character(datetime), collapse = ",")
}

check_batch_location_ids <- function(location_id,
                                     call = rlang::caller_env()) {
  if (!is.character(location_id) || length(location_id) == 0L) {
    cli::cli_abort(
      "{.arg location_id} must be a non-empty character vector.",
      call = call
    )
  }
  if (anyNA(location_id)) {
    cli::cli_abort("{.arg location_id} must not contain missing values.", call = call)
  }
  if (any(!nzchar(trimws(location_id)))) {
    cli::cli_abort("{.arg location_id} must not contain blank values.", call = call)
  }
  if (anyDuplicated(location_id)) {
    duplicates <- unique(location_id[duplicated(location_id)])
    cli::cli_abort(c(
      "{.arg location_id} must contain unique values.",
      x = "Duplicated id{?s}: {.val {duplicates}}"
    ), call = call)
  }
  if (any(grepl("/", location_id, fixed = TRUE))) {
    cli::cli_abort(c(
      "{.arg location_id} must not contain {.val /}.",
      i = "Path-segment ids cannot round-trip a literal slash through HTTP."
    ), call = call)
  }
  location_id
}

check_batch_max_requests <- function(x, call = rlang::caller_env()) {
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || !is.finite(x) ||
      x <= 0 || x > .Machine$integer.max || x %% 1 != 0) {
    cli::cli_abort(
      "{.arg max_requests} must be a finite positive integer.",
      call = call
    )
  }
  invisible(x)
}

check_batch_progress <- function(x, call = rlang::caller_env()) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) {
    cli::cli_abort(
      "{.arg progress} must be {.code TRUE} or {.code FALSE}.",
      call = call
    )
  }
  invisible(x)
}

#' @export
format.edr_batch <- function(x, ...) {
  requests <- x$requests
  successes <- sum(requests$status == "success")
  empty <- sum(requests$status == "empty")
  errors <- sum(requests$status == "error")
  instance <- if (is.null(x$instance_id)) {
    NULL
  } else {
    cli::format_inline("  instance:   {.val {x$instance_id}}")
  }
  c(
    cli::format_inline("<edr_location_batch>"),
    cli::format_inline("  collection: {.val {x$collection_id}}"),
    instance,
    cli::format_inline("  format:     {x$format}"),
    cli::format_inline(
      "  requests:   {nrow(requests)} ({successes} success, {empty} empty, {errors} error{?s})"
    ),
    cli::format_inline("  rows:       {nrow(x$data)}")
  )
}

#' @export
print.edr_batch <- function(x, ...) {
  cat(format(x, ...), sep = "\n")
  invisible(x)
}
