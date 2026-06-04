pkgname <- "edr4r"
source(file.path(R.home("share"), "R", "examples-header.R"))
options(warn = 1)
base::assign(".ExTimings", "edr4r-Ex.timings", pos = 'CheckExEnv')
base::cat("name\tuser\tsystem\telapsed\n", file=base::get(".ExTimings", pos = 'CheckExEnv'))
base::assign(".format_ptime",
function(x) {
  if(!is.na(x[4L])) x[1L] <- x[1L] + x[4L]
  if(!is.na(x[5L])) x[2L] <- x[2L] + x[5L]
  options(OutDec = '.')
  format(x[1L:3L], digits = 7L)
},
pos = 'CheckExEnv')

### * </HEADER>
library('edr4r')

base::assign(".oldSearch", base::search(), pos = 'CheckExEnv')
base::assign(".old_wd", base::getwd(), pos = 'CheckExEnv')
cleanEx()
nameEx("edr_client")
### * edr_client

flush(stderr()); flush(stdout())

base::assign(".ptime", proc.time(), pos = "CheckExEnv")
### Name: edr_client
### Title: Create an EDR client
### Aliases: edr_client

### ** Examples

usgs <- edr_client("https://api.waterdata.usgs.gov/ogcapi/beta")
usgs



base::assign(".dptime", (proc.time() - get(".ptime", pos = "CheckExEnv")), pos = "CheckExEnv")
base::cat("edr_client", base::get(".format_ptime", pos = 'CheckExEnv')(get(".dptime", pos = "CheckExEnv")), "\n", file=base::get(".ExTimings", pos = 'CheckExEnv'), append=TRUE, sep="\t")
cleanEx()
nameEx("edr_explore")
### * edr_explore

flush(stderr()); flush(stdout())

base::assign(".ptime", proc.time(), pos = "CheckExEnv")
### Name: edr_explore
### Title: One-shot fetch + plot + map for a collection
### Aliases: edr_explore

### ** Examples

## Not run: 
##D cl <- edr_client("https://api.wwdh.internetofwater.app")
##D 
##D # One /cube call across a bbox -- fast.
##D edr_explore(
##D   cl, "rise-edr",
##D   bbox           = c(-116, 35.5, -114, 36.5),
##D   datetime       = "2023-01-01/2023-03-31",
##D   parameter_name = "3",
##D   file           = tempfile(fileext = ".html")
##D )
## End(Not run)



base::assign(".dptime", (proc.time() - get(".ptime", pos = "CheckExEnv")), pos = "CheckExEnv")
base::cat("edr_explore", base::get(".format_ptime", pos = 'CheckExEnv')(get(".dptime", pos = "CheckExEnv")), "\n", file=base::get(".ExTimings", pos = 'CheckExEnv'), append=TRUE, sep="\t")
cleanEx()
nameEx("edr_plot")
### * edr_plot

flush(stderr()); flush(stdout())

base::assign(".ptime", proc.time(), pos = "CheckExEnv")
### Name: edr_plot
### Title: Plot an EDR response as a ggplot
### Aliases: edr_plot

### ** Examples

## Not run: 
##D cl <- edr_client("https://api.wwdh.internetofwater.app")
##D resp <- edr_location(cl, "rise-edr",
##D                      location_id    = 3514,
##D                      datetime       = "2023-01-01/2023-06-30",
##D                      parameter_name = "3")
##D edr_plot(resp)
## End(Not run)



base::assign(".dptime", (proc.time() - get(".ptime", pos = "CheckExEnv")), pos = "CheckExEnv")
base::cat("edr_plot", base::get(".format_ptime", pos = 'CheckExEnv')(get(".dptime", pos = "CheckExEnv")), "\n", file=base::get(".ExTimings", pos = 'CheckExEnv'), append=TRUE, sep="\t")
### * <FOOTER>
###
cleanEx()
options(digits = 7L)
base::cat("Time elapsed: ", proc.time() - base::get("ptime", pos = 'CheckExEnv'),"\n")
grDevices::dev.off()
###
### Local variables: ***
### mode: outline-minor ***
### outline-regexp: "\\(> \\)?### [*]+" ***
### End: ***
quit('no')
