## Release status

This file records the pre-submission state for the `v0.3.0-rc.1` GitHub
release candidate. Check results and the package version will be refreshed
after the candidate soak and before the final CRAN submission.

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

## Current release-candidate check results

The exact results from the final `0.3.0` source tarball will replace this
section before submission.

## Network access

Package tests and vignette builds do not contact external EDR services. Tests
use frozen fixtures, mocked `httr2` responses, and a local `webfakes` server.
Network-dependent vignette results are precomputed.

Small live interoperability probes against USGS waterdata, the Western Water
Datahub, and the non-operational Met Office Labs demonstrator run separately
in a scheduled/manual GitHub Actions workflow and are not part of CRAN checks.

## Downstream dependencies

There are currently no known downstream CRAN dependencies.
