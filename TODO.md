# TODO

## Goal
Have CI vendor Rust dependencies before R CMD check so the check compiles offline without a crate-download warning.

## Tasks

### 1. Generate the vendor bundle in CI
- [x] Update the Makefile `vendor` target to call non-deprecated `rextendr::vendor_crates()`.
- [x] Add `rextendr` to the R dependencies installed by `.github/workflows/R-CMD-check.yml`.
- [x] Add a CI step that runs `make vendor` after dependencies are installed and before package check.
- [x] Keep `src/rust/vendor.tar.xz` ignored and do not commit the archive or extracted vendor tree.

### 2. Verify clean-checkout CI behavior
- [x] From a clean Git archive, run `make vendor`; it creates the ignored archive.
- [x] Build the source tarball; it includes `src/rust/vendor.tar.xz` but not `src/rust/vendor/`.
- [x] Run `R CMD check --as-cran`; Rust compilation is OK, no `Downloads Rust crates` warning, tests pass.
- [x] Check the final diff contains only the Makefile, CI workflow, and this TODO.

## Notes
- Exact failure reproduced: without the bundle, clean-checkout `R CMD check --as-cran` reports
  `checking Rust compilation ... WARNING / Downloads Rust crates`; with the existing bundle,
  it reports `checking Rust compilation ... OK`.
- The prior Makefile call used deprecated `rextendr::vendor_pkgs()`; the CI vendoring
  step now uses `vendor_crates()` to avoid that deprecation warning.
- Clean-checkout validation on R 4.6.2: `R CMD check --as-cran` completed with 0 warnings
  and 3 NOTES (`R_NamespaceRegistry`, incoming-check note, unavailable HTML tidy).
- `make vendor` reports the existing DESCRIPTION incomplete-final-line warning; the check
  itself reports `checking Rust compilation ... OK` and does not flag crate downloads.
- Source tarball check: `src/rust/vendor.tar.xz` is included; extracted `src/rust/vendor/`
  remains excluded by `.Rbuildignore`.
