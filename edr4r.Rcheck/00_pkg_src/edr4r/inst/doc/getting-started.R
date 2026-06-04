## ----include-full-station-map, echo=FALSE, results='asis'---------------------
if (Sys.getenv("EDR4R_FULL_VIGNETTES") == "true") {
  station_map <- "getting-started-full/station-map-iframe.html"
  if (!file.exists(station_map)) {
    stop("Full station map output is missing: ", station_map)
  }
  cat(readLines(station_map, warn = FALSE), sep = "\n")
}

