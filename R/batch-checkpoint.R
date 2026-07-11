# Internal helpers for durable, sequential location batches.

.batch_checkpoint_magic <- "edr4r_location_batch_checkpoint"
.batch_checkpoint_result_magic <- "edr4r_location_batch_result"
.batch_checkpoint_schema <- 1L

check_batch_checkpoint_args <- function(checkpoint,
                                        resume,
                                        call = rlang::caller_env()) {
  check_batch_flag(resume, "resume", call = call)
  if (is.null(checkpoint)) {
    if (isTRUE(resume)) {
      cli::cli_abort(
        "{.arg resume} requires a {.arg checkpoint} directory.",
        call = call
      )
    }
    return(invisible(NULL))
  }
  if (!is.character(checkpoint) || length(checkpoint) != 1L ||
      is.na(checkpoint) || !nzchar(trimws(checkpoint))) {
    cli::cli_abort(
      "{.arg checkpoint} must be one non-empty directory path or {.code NULL}.",
      call = call
    )
  }
  invisible(checkpoint)
}

batch_checkpoint_plan_urls <- function(client,
                                       collection_id,
                                       plan,
                                       parameter_name,
                                       z,
                                       crs,
                                       format,
                                       dots,
                                       instance_id) {
  # Check before any checkpoint directory is opened. Headers may rotate
  # between runs, but credentials embedded in the endpoint would otherwise be
  # part of the URL identity and risk leaking into diagnostic metadata.
  batch_checkpoint_safe_endpoint(client$base_url)
  vapply(seq_len(nrow(plan)), function(i) {
    batch_location_request_spec(
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
    )$url
  }, character(1), USE.NAMES = FALSE)
}

batch_checkpoint_fingerprint <- function(urls, format) {
  payload <- jsonlite::toJSON(
    list(
      protocol = "edr4r-location-request-v1",
      method = "GET",
      schema_version = .batch_checkpoint_schema,
      format = format,
      accept = accept_header(format),
      urls = unname(urls)
    ),
    auto_unbox = TRUE,
    null = "null",
    digits = NA
  )
  path <- tempfile(pattern = "edr4r-checkpoint-fingerprint-")
  on.exit(unlink(path, force = TRUE), add = TRUE)
  writeBin(charToRaw(payload), path)
  unname(tools::md5sum(path)[[1L]])
}

batch_checkpoint_safe_endpoint <- function(base_url) {
  parts <- tryCatch(
    httr2::url_parse(base_url),
    error = function(e) NULL
  )
  if (is.null(parts) || !parts$scheme %in% c("http", "https") ||
      is.null(parts$hostname) || !nzchar(parts$hostname)) {
    cli::cli_abort(
      "Checkpointing requires an absolute HTTP(S) client base URL with a hostname."
    )
  }
  if (!is.null(parts$username) || !is.null(parts$password)) {
    cli::cli_abort(c(
      "Checkpointing refuses an endpoint URL containing embedded credentials.",
      i = "Supply rotating credentials with {.arg headers} in {.fn edr_client} instead."
    ))
  }
  if (length(parts$query) > 0L || !is.null(parts$fragment)) {
    cli::cli_abort(
      "Checkpointing requires a client base URL without a query string or fragment."
    )
  }
  base_url
}

batch_checkpoint_manifest <- function(fingerprint,
                                      plan,
                                      client,
                                      collection_id,
                                      instance_id,
                                      format) {
  version <- tryCatch(
    as.character(utils::packageVersion("edr4r")),
    error = function(e) "unknown"
  )
  list(
    magic = .batch_checkpoint_magic,
    schema_version = .batch_checkpoint_schema,
    fingerprint = fingerprint,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    package_version = version,
    endpoint = batch_checkpoint_safe_endpoint(client$base_url),
    collection_id = collection_id,
    instance_id = instance_id,
    format = format,
    plan = batch_checkpoint_identity_plan(plan)
  )
}

batch_checkpoint_identity_plan <- function(plan) {
  tibble::as_tibble(plan[c("request_id", "location_id", "datetime")])
}

batch_checkpoint_open <- function(path,
                                  resume,
                                  fingerprint,
                                  plan,
                                  client,
                                  collection_id,
                                  instance_id,
                                  format,
                                  call = rlang::caller_env()) {
  path <- normalizePath(path.expand(path), mustWork = FALSE)
  if (file.exists(path) && !dir.exists(path)) {
    cli::cli_abort(
      "{.arg checkpoint} must be a directory, not an existing file: {.path {path}}.",
      call = call
    )
  }
  if (!dir.exists(path) &&
      !dir.create(path, recursive = TRUE, showWarnings = FALSE)) {
    cli::cli_abort(
      "Could not create checkpoint directory {.path {path}}.",
      call = call
    )
  }

  lock <- file.path(path, ".edr4r-lock")
  if (!dir.create(lock, showWarnings = FALSE)) {
    cli::cli_abort(c(
      "Checkpoint directory is already locked: {.path {path}}.",
      i = "Wait for the active batch to finish, or remove a stale {.file .edr4r-lock} directory after confirming no writer is active."
    ), call = call)
  }
  release_lock <- TRUE
  on.exit({
    if (isTRUE(release_lock)) unlink(lock, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  manifest_path <- file.path(path, "manifest.rds")
  results_path <- file.path(path, "results")
  expected_manifest <- batch_checkpoint_manifest(
    fingerprint = fingerprint,
    plan = plan,
    client = client,
    collection_id = collection_id,
    instance_id = instance_id,
    format = format
  )

  if (file.exists(manifest_path)) {
    if (!isTRUE(resume)) {
      cli::cli_abort(c(
        "Checkpoint already exists at {.path {path}}.",
        i = "Set {.code resume = TRUE} to reuse its completed requests."
      ), call = call)
    }
    manifest <- batch_checkpoint_read_rds(
      manifest_path, "checkpoint manifest", call = call
    )
    batch_checkpoint_validate_manifest(
      manifest,
      expected = expected_manifest,
      path = manifest_path,
      call = call
    )
  } else {
    batch_checkpoint_validate_initial_directory(
      path, results_path, lock, call = call
    )
    if (!dir.exists(results_path) &&
        !dir.create(results_path, showWarnings = FALSE)) {
      cli::cli_abort(
        "Could not create checkpoint results directory {.path {results_path}}.",
        call = call
      )
    }
    batch_checkpoint_atomic_save(
      expected_manifest, manifest_path, "checkpoint manifest", call = call
    )
    manifest <- expected_manifest
  }

  if (file.exists(results_path) && !dir.exists(results_path)) {
    cli::cli_abort(
      "Checkpoint results path is not a directory: {.path {results_path}}.",
      call = call
    )
  }
  if (!dir.exists(results_path) &&
      !dir.create(results_path, showWarnings = FALSE)) {
    cli::cli_abort(
      "Could not create checkpoint results directory {.path {results_path}}.",
      call = call
    )
  }

  state <- list(
    path = path,
    lock = lock,
    results_path = results_path,
    fingerprint = fingerprint,
    manifest = manifest
  )
  release_lock <- FALSE
  state
}

batch_checkpoint_validate_initial_directory <- function(path,
                                                        results_path,
                                                        lock,
                                                        call) {
  entries <- list.files(
    path,
    all.files = TRUE,
    full.names = TRUE,
    no.. = TRUE
  )
  entries <- setdiff(entries, lock)
  temporary <- startsWith(basename(entries), ".edr4r-")
  entries <- entries[!temporary]
  if (results_path %in% entries) {
    if (!dir.exists(results_path)) {
      cli::cli_abort(
        "Checkpoint results path is not a directory: {.path {results_path}}.",
        call = call
      )
    }
    result_entries <- list.files(
      results_path,
      all.files = TRUE,
      full.names = FALSE,
      no.. = TRUE
    )
    result_entries <- result_entries[
      !startsWith(result_entries, ".edr4r-")
    ]
    if (length(result_entries) == 0L) {
      entries <- setdiff(entries, results_path)
    }
  }
  if (length(entries) > 0L) {
    cli::cli_abort(c(
      "Directory is not an edr4r checkpoint: {.path {path}}.",
      x = "Unexpected entr{?y/ies}: {.file {basename(entries)}}"
    ), call = call)
  }
  invisible(NULL)
}

batch_checkpoint_validate_manifest <- function(x,
                                               expected,
                                               path,
                                               call) {
  required <- names(expected)
  valid_structure <- is.list(x) && identical(names(x), required) &&
    identical(x$magic, .batch_checkpoint_magic) &&
    identical(x$schema_version, .batch_checkpoint_schema) &&
    is.character(x$fingerprint) && length(x$fingerprint) == 1L &&
    !is.na(x$fingerprint) && grepl("^[0-9a-f]{32}$", x$fingerprint) &&
    is.character(x$created_at) && length(x$created_at) == 1L &&
    !is.na(x$created_at) &&
    is.character(x$package_version) && length(x$package_version) == 1L &&
    !is.na(x$package_version) &&
    is.character(x$endpoint) && length(x$endpoint) == 1L &&
    !is.na(x$endpoint) &&
    is.character(x$collection_id) && length(x$collection_id) == 1L &&
    !is.na(x$collection_id) &&
    (is.null(x$instance_id) ||
       (is.character(x$instance_id) && length(x$instance_id) == 1L &&
          !is.na(x$instance_id))) &&
    is.character(x$format) && length(x$format) == 1L && !is.na(x$format) &&
    inherits(x$plan, "tbl_df") &&
    identical(names(x$plan), c("request_id", "location_id", "datetime"))
  if (!isTRUE(valid_structure)) {
    abort_batch_checkpoint_corrupt(path, "manifest schema is invalid", call)
  }

  identity_fields <- c(
    "fingerprint", "endpoint", "collection_id", "instance_id", "format", "plan"
  )
  matches <- vapply(identity_fields, function(field) {
    identical(x[[field]], expected[[field]])
  }, logical(1))
  if (!all(matches)) {
    cli::cli_abort(c(
      "Checkpoint does not match the current batch plan: {.path {dirname(path)}}.",
      i = "Use a new checkpoint directory for different endpoints, request arguments, locations, or windows."
    ), call = call)
  }
  invisible(x)
}

batch_checkpoint_restore <- function(state,
                                     plan,
                                     call = rlang::caller_env()) {
  entries <- list.files(
    state$results_path,
    all.files = TRUE,
    full.names = FALSE,
    no.. = TRUE
  )
  entries <- entries[!startsWith(entries, ".edr4r-")]
  valid_names <- grepl("^[0-9]{10}\\.rds$", entries)
  if (any(!valid_names)) {
    path <- file.path(state$results_path, entries[[which(!valid_names)[[1L]]]])
    abort_batch_checkpoint_corrupt(path, "unexpected result filename", call)
  }

  file_ids <- if (length(entries) == 0L) numeric() else {
    as.numeric(sub("\\.rds$", "", entries))
  }
  unknown <- !file_ids %in% plan$request_id
  if (any(unknown)) {
    path <- file.path(state$results_path, entries[[which(unknown)[[1L]]]])
    abort_batch_checkpoint_corrupt(path, "request id is not in the batch plan", call)
  }

  results <- vector("list", nrow(plan))
  for (entry in entries) {
    path <- file.path(state$results_path, entry)
    if (dir.exists(path)) {
      abort_batch_checkpoint_corrupt(path, "result entry is a directory", call)
    }
    request_id <- as.integer(sub("\\.rds$", "", entry))
    result <- batch_checkpoint_read_rds(path, "checkpoint result", call = call)
    batch_checkpoint_validate_result(
      result,
      state = state,
      request_id = request_id,
      path = path,
      call = call
    )
    i <- match(request_id, plan$request_id)
    results[[i]] <- result$data
    plan$status[[i]] <- result$status
    plan$n_rows[[i]] <- result$n_rows
  }
  list(plan = plan, results = results)
}

batch_checkpoint_write_result <- function(state,
                                          request_id,
                                          status,
                                          data,
                                          call = rlang::caller_env()) {
  result <- list(
    magic = .batch_checkpoint_result_magic,
    schema_version = .batch_checkpoint_schema,
    fingerprint = state$fingerprint,
    request_id = as.integer(request_id),
    status = status,
    n_rows = as.integer(nrow(data)),
    data = data
  )
  path <- batch_checkpoint_result_path(state, request_id)
  batch_checkpoint_atomic_save(result, path, "checkpoint result", call = call)
  invisible(path)
}

batch_checkpoint_validate_result <- function(x,
                                             state,
                                             request_id,
                                             path,
                                             call) {
  required <- c(
    "magic", "schema_version", "fingerprint", "request_id", "status",
    "n_rows", "data"
  )
  valid_structure <- is.list(x) && identical(names(x), required) &&
    identical(x$magic, .batch_checkpoint_result_magic) &&
    identical(x$schema_version, .batch_checkpoint_schema) &&
    identical(x$fingerprint, state$fingerprint) &&
    identical(x$request_id, as.integer(request_id)) &&
    is.character(x$status) && length(x$status) == 1L &&
    x$status %in% c("success", "empty") &&
    is.integer(x$n_rows) && length(x$n_rows) == 1L && !is.na(x$n_rows) &&
    x$n_rows >= 0L && inherits(x$data, "tbl_df") &&
    !any(c(".request_id", ".location_id") %in% names(x$data))
  if (!isTRUE(valid_structure)) {
    abort_batch_checkpoint_corrupt(path, "result schema is invalid", call)
  }
  status_matches <- (identical(x$status, "empty") && x$n_rows == 0L) ||
    (identical(x$status, "success") && x$n_rows > 0L)
  if (!status_matches || nrow(x$data) != x$n_rows) {
    abort_batch_checkpoint_corrupt(
      path, "stored status or row count does not match its data", call
    )
  }
  invisible(x)
}

batch_checkpoint_result_path <- function(state, request_id) {
  file.path(state$results_path, sprintf("%010d.rds", as.integer(request_id)))
}

batch_checkpoint_atomic_save <- function(object,
                                         destination,
                                         label,
                                         call = rlang::caller_env()) {
  if (file.exists(destination)) {
    cli::cli_abort(
      "Refusing to overwrite existing {label}: {.path {destination}}.",
      call = call
    )
  }
  temporary <- tempfile(pattern = ".edr4r-", tmpdir = dirname(destination))
  on.exit(unlink(temporary, recursive = TRUE, force = TRUE), add = TRUE)
  tryCatch(
    saveRDS(object, temporary, compress = "gzip", version = 3),
    error = function(e) {
      cli::cli_abort(
        "Could not write {label} in {.path {dirname(destination)}}: {conditionMessage(e)}",
        call = call,
        parent = e
      )
    }
  )
  if (!file.rename(temporary, destination)) {
    cli::cli_abort(
      "Could not atomically install {label} at {.path {destination}}.",
      call = call
    )
  }
  invisible(destination)
}

batch_checkpoint_read_rds <- function(path,
                                      label,
                                      call = rlang::caller_env()) {
  tryCatch(
    readRDS(path),
    error = function(e) {
      abort_batch_checkpoint_corrupt(
        path, paste0("could not read ", label, ": ", conditionMessage(e)), call
      )
    }
  )
}

abort_batch_checkpoint_corrupt <- function(path, reason, call) {
  cli::cli_abort(c(
    "Checkpoint is corrupt at {.path {path}}.",
    x = "{reason}."
  ), call = call)
}

batch_checkpoint_close <- function(state) {
  if (is.null(state)) return(invisible(NULL))
  unlink(state$lock, recursive = TRUE, force = TRUE)
  invisible(NULL)
}
