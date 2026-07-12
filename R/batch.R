#' Fetch data for multiple EDR locations
#'
#' Runs one or more [edr_location()] requests for each explicitly supplied
#' location id. When `chunk` is supplied, a bounded datetime interval is split
#' into contiguous closed windows and the complete station-by-window plan is
#' validated before any network activity. Requests remain sequential and in
#' input order, and `max_requests` guards the expanded plan against accidental
#' fan-out.
#'
#' `format = "covjson"` responses are converted with
#' [covjson_to_tibble()]. CSV responses are already parsed as tibbles by
#' [edr_location()]. Successful rows are combined with `.request_id` and
#' `.location_id` provenance columns.
#'
#' @param client An [edr_client()].
#' @param collection_id Collection identifier.
#' @param location_id A non-empty character vector of unique location ids.
#' @param datetime Optional ISO-8601 instant or interval. With `chunk = NULL`,
#'   it is shared by every request; otherwise the bounded interval is split
#'   into per-request windows. Timestamp bounds are normalized to UTC before
#'   calendar arithmetic; up to six fractional-second digits are accepted
#'   when R can preserve them without loss.
#' @param parameter_name Optional character vector of parameter names shared
#'   by every request.
#' @param z Optional vertical level filter.
#' @param crs Optional CRS URI for the response.
#' @param format Either `"covjson"` (default) or `"csv"`.
#' @param ... Additional query parameters forwarded to every
#'   [edr_location()] request, such as `limit`.
#' @param chunk Optional positive-integer calendar interval such as `"1 day"`,
#'   `"2 weeks"`, `"1 month"`, or `"1 year"`. Requires a bounded `datetime`
#'   interval. Month/year boundaries use anchored calendar arithmetic, so a
#'   January 31 start advances to February 28/29 and then March 31.
#' @param deduplicate If `TRUE` (default), exact rows repeated by different
#'   time windows for the same location are retained only from the earliest
#'   request. Duplicates within one response, differing observations, and
#'   rows from different locations are preserved. Ignored when `chunk` is
#'   `NULL`.
#' @param checkpoint Optional directory used to persist each terminal
#'   successful or empty response. A new or empty directory is initialized
#'   after the complete request plan has passed validation. Checkpoints store
#'   parsed response data, but not client headers, query URLs, or errors.
#' @param resume If `TRUE`, reuse terminal responses in an existing compatible
#'   `checkpoint` and request only unresolved rows. If the directory does not
#'   yet exist, it is initialized, which supports rerunnable scripts. An
#'   existing checkpoint requires `resume = TRUE`. Defaults to `FALSE`.
#' @param include_parameters If `TRUE`, fetch the collection's full parameter
#'   catalog with [edr_parameters()] and attach it once as `parameters` on the
#'   result. This is an explicit, cacheable discovery request in addition to
#'   the planned data requests. For an instance-scoped batch, metadata comes
#'   from that instance. Defaults to `FALSE`, which performs no metadata
#'   request and stores `NULL` in `parameters`.
#' @param max_requests Finite positive integer limiting the number of logical
#'   [edr_location()] calls in the complete plan. Transport-level retries do
#'   not increase this count. Defaults to 100.
#' @param on_error Either `"stop"` (default), which re-signals the original
#'   condition immediately, or `"collect"`, which records failures and
#'   continues through the bounded request plan.
#' @param progress If `TRUE`, display a cli progress bar for multi-request
#'   batches. Defaults to [interactive()].
#' @param instance_id Optional collection instance identifier. Every request
#'   remains beneath that instance path.
#' @param f Optional server-advertised output-format token sent as the EDR
#'   `f` query parameter. This is separate from `format`, which controls
#'   client-side parsing.
#'
#' @return An object of class `edr_location_batch` and `edr_batch`. It contains
#'   `requests`, a typed request-status tibble whose `n_rows` values describe
#'   raw responses before cross-window deduplication; `data`, a combined data
#'   tibble; `errors`, a typed tibble of collected conditions; and `parameters`,
#'   either the nonduplicated collection/instance parameter catalog or `NULL`
#'   when it was not requested. The object also records `collection_id`,
#'   `instance_id`, and `format`.
#'
#' @details
#' Checkpoint requests remain sequential. Result files are written atomically
#' after parsing and before a request is marked complete in memory. Errors are
#' deliberately not terminal: a later call with `resume = TRUE` retries them
#' under the client's normal retry policy. A checkpoint may contain the
#' endpoint's returned observations, so protect it like any other local data
#' extract and resume it under the same logical authorization context.
#' Checkpointed clients must use an absolute HTTP(S) base URL without an
#' embedded query, fragment, username, or password; rotating credentials
#' belong in `client` headers and are not written to the checkpoint.
#'
#' `max_requests` counts data requests only. When `include_parameters = TRUE`,
#' the additional discovery request is made after an existing checkpoint has
#' been validated and restored. The catalog is not stored in the checkpoint,
#' so a resumed call obtains current metadata (subject to the client's cache)
#' even when every data response is restored. Parameter-discovery failures are
#' not collected by `on_error`; they abort the call because the requested
#' result metadata would be incomplete.
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
                               chunk = NULL,
                               deduplicate = TRUE,
                               checkpoint = NULL,
                               resume = FALSE,
                               include_parameters = FALSE,
                               max_requests = 100L,
                               on_error = c("stop", "collect"),
                               progress = interactive(),
                               instance_id = NULL,
                               f = NULL) {
  check_client(client)
  format <- match.arg(format)
  on_error <- match.arg(on_error)
  check_batch_progress(progress)
  check_batch_flag(deduplicate, "deduplicate")
  check_batch_max_requests(max_requests)
  check_batch_datetime_missing(datetime)
  check_batch_checkpoint_args(checkpoint, resume)
  check_batch_flag(include_parameters, "include_parameters")

  location_id <- check_batch_location_ids(location_id)
  n_locations <- length(location_id)
  if (n_locations > max_requests) {
    cli::cli_abort(c(
      "The batch would issue {n_locations} requests, exceeding {.arg max_requests} = {max_requests}.",
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
  if (!is.null(f)) dots$f <- f
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

  windows <- batch_datetime_windows(
    query$datetime,
    chunk = chunk,
    max_windows = floor(max_requests / n_locations),
    n_locations = n_locations,
    max_requests = max_requests
  )
  n_windows <- length(windows)
  n_requests <- n_locations * n_windows

  plan <- tibble::tibble(
    request_id = seq_len(n_requests),
    location_id = rep(location_id, each = n_windows),
    datetime = rep(windows, times = n_locations),
    status = rep("pending", n_requests),
    n_rows = rep(NA_integer_, n_requests)
  )

  checkpoint_state <- NULL
  initial_results <- NULL
  if (!is.null(checkpoint)) {
    urls <- batch_checkpoint_plan_urls(
      client = client,
      collection_id = collection_id,
      plan = plan,
      parameter_name = parameter_name,
      z = z,
      crs = crs,
      format = format,
      dots = dots,
      instance_id = instance_id
    )
    fingerprint <- batch_checkpoint_fingerprint(urls, format)
    checkpoint_state <- batch_checkpoint_open(
      path = checkpoint,
      resume = resume,
      fingerprint = fingerprint,
      plan = plan,
      client = client,
      collection_id = collection_id,
      instance_id = instance_id,
      format = format
    )
    on.exit(batch_checkpoint_close(checkpoint_state), add = TRUE)
    restored <- batch_checkpoint_restore(checkpoint_state, plan)
    plan <- restored$plan
    initial_results <- restored$results
  }

  # Validate and restore an existing checkpoint before the optional metadata
  # request so incompatible or corrupt checkpoints still abort without HTTP.
  parameter_catalog <- if (isTRUE(include_parameters)) {
    edr_parameters(
      client,
      collection_id = collection_id,
      instance_id = instance_id
    )
  } else {
    NULL
  }

  executed <- run_location_batch_plan(
    client = client,
    collection_id = collection_id,
    plan = plan,
    parameter_name = parameter_name,
    z = z,
    crs = crs,
    format = format,
    dots = dots,
    on_error = on_error,
    progress = progress,
    instance_id = instance_id,
    initial_results = initial_results,
    checkpoint = checkpoint_state
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
        format = format,
        deduplicate = !is.null(chunk) && isTRUE(deduplicate)
      ),
      errors = executed$errors,
      # Append-only to preserve positional access to the original six fields.
      parameters = parameter_catalog
    ),
    class = c("edr_location_batch", "edr_batch", "list")
  )
}

run_location_batch_plan <- function(client,
                                    collection_id,
                                    plan,
                                    parameter_name,
                                    z,
                                    crs,
                                    format,
                                    dots,
                                    on_error,
                                    progress,
                                    instance_id,
                                    initial_results = NULL,
                                    checkpoint = NULL) {
  n_requests <- nrow(plan)
  results <- if (is.null(initial_results)) {
    vector("list", n_requests)
  } else {
    initial_results
  }
  error_rows <- vector("list", n_requests)
  todo <- which(plan$status == "pending")

  progress_env <- environment()
  show_progress <- isTRUE(progress) && length(todo) > 1L
  if (show_progress) {
    cli::cli_progress_bar(
      "Fetching location data",
      total = length(todo),
      .envir = progress_env
    )
    on.exit(cli::cli_progress_done(.envir = progress_env), add = TRUE)
  }

  for (i in todo) {
    spec <- batch_location_request_spec(
      client = client,
      collection_id = collection_id,
      location_id = plan$location_id[[i]],
      datetime = plan$datetime[[i]],
      parameter_name = parameter_name,
      z = z,
      crs = crs,
      format = format,
      dots = dots,
      instance_id = instance_id
    )

    outcome <- tryCatch(
      {
        response <- parse_response(
          perform_edr_request(spec$request, verbose = client$verbose),
          format = format
        )
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

    status <- if (nrow(outcome) == 0L) "empty" else "success"
    if (!is.null(checkpoint)) {
      batch_checkpoint_write_result(
        checkpoint,
        request_id = plan$request_id[[i]],
        status = status,
        data = outcome
      )
    }
    results[[i]] <- outcome
    plan$n_rows[[i]] <- nrow(outcome)
    plan$status[[i]] <- status
  }

  errors <- error_rows[!vapply(error_rows, is.null, logical(1))]
  if (length(errors) == 0L) {
    errors <- empty_batch_errors()
  } else {
    errors <- vctrs::vec_rbind(!!!errors)
  }

  list(requests = plan, results = results, errors = errors)
}

batch_location_request_spec <- function(client,
                                        collection_id,
                                        location_id,
                                        datetime,
                                        parameter_name,
                                        z,
                                        crs,
                                        format,
                                        dots,
                                        instance_id) {
  if (length(datetime) == 0L || is.na(datetime)) datetime <- NULL
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
  path <- paste0(
    collection_query_path(collection_id, "locations", instance_id),
    "/",
    check_path_id(location_id, "location_id")
  )
  request <- build_edr_http_request(client, path, query, format)
  list(
    path = path,
    query = query,
    request = request,
    url = request$url,
    format = format,
    accept = accept_header(format)
  )
}

bind_location_batch_data <- function(results, requests, format,
                                     deduplicate = FALSE) {
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
  bound <- if (length(pieces) == 1L) {
    pieces[[1L]]
  } else {
    candidate <- tryCatch(
      vctrs::vec_rbind(!!!pieces),
      error = function(e) e
    )
    if (!inherits(candidate, "error")) {
      candidate
    } else {
      conflicts <- batch_conflicting_columns(pieces)
      if (length(conflicts) == 0L ||
          !all(vapply(
            conflicts, batch_column_is_castable, logical(1), pieces = pieces
          ))) {
        rlang::cnd_signal(candidate)
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
  }
  if (isTRUE(deduplicate)) deduplicate_batch_window_rows(bound) else bound
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
  check_batch_flag(x, "progress", call = call)
}

check_batch_datetime_missing <- function(x, call = rlang::caller_env()) {
  if (!is.null(x) && anyNA(x)) {
    cli::cli_abort(
      "{.arg datetime} must not contain missing values.",
      call = call
    )
  }
  invisible(x)
}

check_batch_flag <- function(x, arg, call = rlang::caller_env()) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) {
    cli::cli_abort(
      "{.arg {arg}} must be {.code TRUE} or {.code FALSE}.",
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
  parameters <- if (is.null(x$parameters)) {
    NULL
  } else {
    cli::format_inline("  parameters: {nrow(x$parameters)} definition{?s}")
  }
  c(
    cli::format_inline("<edr_location_batch>"),
    cli::format_inline("  collection: {.val {x$collection_id}}"),
    instance,
    cli::format_inline("  format:     {x$format}"),
    parameters,
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
