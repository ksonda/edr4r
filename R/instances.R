#' List instances of an EDR collection
#'
#' Retrieves metadata for the versions or runs advertised beneath
#' `GET /collections/{collection_id}/instances`. Discovery responses use the
#' client's in-memory cache; set `refresh = TRUE` to bypass and replace the
#' cached value.
#'
#' @param client An [edr_client()].
#' @param collection_id Collection identifier as advertised by the server.
#' @param refresh If `TRUE`, bypass and replace cached instance metadata.
#'
#' @return `edr_instances()` returns a tibble with one row per instance. It
#'   adds `collection_id` to the normalized metadata columns returned by
#'   [edr_collections()], keeping extent and output CRS semantics aligned.
#' @export
edr_instances <- function(client, collection_id, refresh = FALSE) {
  check_client(client)
  raw_collection_id <- check_collection_id(collection_id)
  collection_id <- collection_path_id(raw_collection_id)
  cached_discovery(
    client,
    paste0("instances:", collection_id),
    refresh,
    function() {
      body <- edr_request(
        client,
        paste0("collections/", collection_id, "/instances"),
        format = "json"
      )
      check_metadata_object(body, "Instances response")
      if (!"instances" %in% names(body) || !is.list(body$instances) ||
          (length(body$instances) > 0L && !is.null(names(body$instances)))) {
        cli::cli_abort(
          "Instances response must contain an {.field instances} array."
        )
      }
      instances <- body$instances
      if (length(instances) == 0L) return(empty_instances_tibble())
      rows <- lapply(
        instances,
        instance_row,
        collection_id = raw_collection_id
      )
      vctrs::vec_rbind(!!!rows)
    }
  )
}

#' Get metadata for one collection instance
#'
#' Retrieves the raw instance document from
#' `GET /collections/{collection_id}/instances/{instance_id}`.
#'
#' @rdname edr_instances
#' @param instance_id Instance identifier as advertised by [edr_instances()].
#'   Reserved characters are percent-encoded. A literal `/` is rejected
#'   because it cannot safely round-trip as one HTTP path segment.
#'
#' @return `edr_instance()` returns the parsed instance metadata as a list.
#' @export
edr_instance <- function(client, collection_id, instance_id, refresh = FALSE) {
  check_client(client)
  collection_id <- collection_path_id(collection_id)
  instance_id <- check_path_id(instance_id, "instance_id")
  cached_discovery(
    client,
    paste0("instance:", collection_id, ":", instance_id),
    refresh,
    function() {
      body <- edr_request(
        client,
        paste0(
          "collections/", collection_id,
          "/instances/", instance_id
        ),
        format = "json"
      )
      check_metadata_object(body, "Instance response")
      body
    }
  )
}

instance_row <- function(instance, collection_id) {
  row <- collection_row(instance)
  row$collection_id <- rep(collection_id, nrow(row))
  row[c("collection_id", setdiff(names(row), "collection_id"))]
}

empty_instances_tibble <- function() {
  out <- empty_collections_tibble()
  out$collection_id <- character()
  out[c("collection_id", setdiff(names(out), "collection_id"))]
}
