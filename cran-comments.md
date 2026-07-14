## Release status

This is the final 0.3.0 source prepared for CRAN submission.

## Submission

This is a planned feature update from CRAN version 0.1.1. The 0.2.0 line was
available only as a GitHub release candidate and was never submitted to CRAN;
version 0.3.0 supersedes that preview.

Major additions include:

* cached capability, collection-instance, and parameter discovery;
* bounded GeoJSON pagination and finite sequential multi-location pulls with
  calendar time windows, checkpoint/resume, and request provenance;
* richer EDR 1.1 parameter, unit, format, geometry, and custom-dimension
  support; and
* CoverageJSON custom-axis/CRS preservation plus interactive coverage and
  station visualization.

No existing exported query verb has been removed.

## Test environments

* Local: macOS Sequoia 15.3.2, R 4.5.2
* GitHub Actions:
  * macOS, R-release
  * Windows, R-release
  * Ubuntu, R-devel
  * Ubuntu, R-release
  * Ubuntu, R-oldrel-1

## R CMD check results

0 errors | 0 warnings | 1 note

The final source tarball was checked locally with `--as-cran`. The same source
also passed the GitHub Actions matrix listed above, including package checks on
R-devel, R-release, and R-oldrel-1.

The single CRAN incoming-feasibility note is:

> Days since last update: 4

Version 0.3.0 is an intentional feature update following the 0.1.1 correctness
release. The 0.2.0 line remained a GitHub-only preview and was not submitted to
CRAN.

## Network access

Package tests and vignette builds do not contact external EDR services. Tests
use frozen fixtures, mocked `httr2` responses, and a local `webfakes` server.
Network-dependent vignette results are precomputed.

Small live interoperability probes against USGS waterdata, the Western Water
Datahub, and the non-operational Met Office Labs demonstrator run separately
in a scheduled/manual GitHub Actions workflow and are not part of CRAN checks.

## Downstream dependencies

There are currently no known downstream CRAN dependencies.
