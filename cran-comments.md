## Test environments

* Local: macOS Sequoia 15.3.2, R 4.5.2
* win-builder: R-devel, Windows Server 2022 x64, R Under development
  (2026-06-03 r90099 ucrt)

## Resubmission

This resubmission fixes the Debian R-devel incoming pretest failure in
`tests/testthat/test-queries.R`. URL construction now preserves
percent-encoded path identifiers when query parameters are added, so reserved
characters in location/item ids remain inside the intended path segment across
curl/httr2 builds.

## R CMD check results

0 errors | 0 warnings | 2 notes

* This is a new submission.
* HTML manual validation was skipped locally because the system `tidy`
  executable is not recent enough. The PDF manual builds successfully.

## Downstream dependencies

There are no downstream dependencies; this is a new submission.

## win-builder results

0 errors | 0 warnings | 1 note

* New submission.
* Possibly misspelled words in DESCRIPTION are domain acronyms, product names,
  or service names: Datahub, EDR, OGC, USGS, waterdata.
