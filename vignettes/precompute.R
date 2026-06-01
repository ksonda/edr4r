# Pre-compute network-dependent vignettes.
#
# Vignettes hit live EDR endpoints (USGS waterdata, WWDH). To keep
# `R CMD build` deterministic and offline, we ship pre-rendered `.Rmd`
# files in `vignettes/` and keep the executable sources as `.Rmd.orig`
# (excluded from the build via `.Rbuildignore`).
#
# Run this script from the package root before each release, or after
# any change to a `.Rmd.orig` that should refresh the baked outputs:
#
#   Rscript vignettes/precompute.R

if (!requireNamespace("devtools", quietly = TRUE)) {
  stop("devtools is required for the precompute step.")
}
if (!requireNamespace("knitr", quietly = TRUE)) {
  stop("knitr is required for the precompute step.")
}

devtools::load_all(".", quiet = TRUE)

vroot <- "vignettes"
old_wd <- setwd(vroot)
on.exit(setwd(old_wd), add = TRUE)

orig_files <- list.files(".", pattern = "\\.Rmd\\.orig$", full.names = FALSE)
if (length(orig_files) == 0L) {
  message("No .Rmd.orig files in vignettes/")
  return(invisible())
}

for (orig in orig_files) {
  out <- sub("\\.orig$", "", orig)
  message("Knitting ", orig, " -> ", out)
  knitr::knit(input = orig, output = out, quiet = TRUE)
}
message("Done. Inspect outputs with devtools::build_vignettes().")
