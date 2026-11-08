# REVIEW 1: Standards axis (b7f07b8..HEAD)

Read-only review of branch `adaptive-GKDE-1` against R, Rust, and `make check` standards.
Not run: `make check`, `devtools::check()`, `make docs`, `make vendor`. Line numbers are from the working tree at HEAD `c220499`.

## Summary

- 12 findings: 3 Medium, 9 Low.
- 3 findings are Conditional (3, 6, 7). The rest are Confirmed.
- Checks with no finding: NAMESPACE vs `@export`, S3 registration, `extendr_module!` coverage, roxygen completeness for exported functions, man page presence, tinytest style.

## Findings

### 1. Documented adaptive scaling formula does not match the code
- Severity: Medium
- Anchors: `R/geodensity.R:151-152`; `src/rust/src/lib.rs:154`; `src/rust/src/lib.rs:185`; also `man/kde_adaptive.Rd:41` (generated from R roxygen, so fix the source).
- Observed gap: The docs say the bandwidth is `pilot_bandwidth / sqrt(pilot_density)` clamped to `[min, pilot]`. The code (`lib.rs:189-201`) uses `min + (pilot - min) * 1 / (1 + (d / ref)^0.5)`, where `d / ref` is density normalized by the max. The Rust comment at `lib.rs:185` drops the `min +` term. Neither matches the code.
- Proposed fix: Rewrite the R roxygen (`R/geodensity.R:151-152`) and the Rust comments (`lib.rs:154`, `lib.rs:185`) to the formula in code. Regenerate the Rd via `make docs` in a later wave, not here.
- Verdict: Confirmed. Evidence: `lib.rs:189-201` is the code path; the three doc sites quote different formulas.
- Routing: in-branch (R roxygen and Rust comments were added by this branch) -> Wave 5.

### 2. Docs say LOOCV is parallel; the Rust function is serial
- Severity: Medium
- Anchors: `R/geodensity.R:356-357`; `man/bandwidth_optimize.Rd:66`; `src/rust/src/lib.rs:328-360`.
- Observed gap: The docs say "The computation is parallelized ... in the Rust backend via Rayon." `bandwidth_loocv_evaluate` uses `bandwidths.iter().map(...)` and a nested `for` loop. No `par_iter` appears in that function (the only `par_iter` calls are at `lib.rs:107`, `:108`, `:259-261`).
- Proposed fix: Either remove the parallel claim from the R roxygen and the Rd, or parallelize the outer `bandwidths` map with Rayon and keep the claim. Choose one in Wave 5. The first is the standards-only fix.
- Verdict: Confirmed. Evidence: `grep -n par_iter src/rust/src/lib.rs` shows no match in lines 308-363.
- Routing: in-branch -> Wave 5.

### 3. `planning/` is not excluded from the build
- Severity: Medium
- Anchors: `.Rbuildignore:1-12`; `git ls-files planning` (tracked: `planning/EXECUTION_PLAN_1.md`, `planning/PROMPT_TEMPLATE_1.md`, `planning/STATE_1.md`).
- Observed gap: `.Rbuildignore` covers `.github/` (`:11-12`), `src/rust/vendor` (`:1`), and `src/rust/target` (`:2`), but has no `planning` entry. The planning files are tracked and would be part of a source tarball built by `R CMD build`.
- Proposed fix: Add `^planning$` to `.Rbuildignore`.
- Verdict: Conditional. The finding depends on `R CMD build` copying non-ignored top-level directories into the tarball, which I cannot run here. The `.Rbuildignore` contents themselves are confirmed.
- Routing: in-branch (`.Rbuildignore` changed by this branch) -> Wave 5.

### 4. LOOCV kernel comment says "Vincenty" but the code is linear
- Severity: Low
- Anchors: `src/rust/src/lib.rs:37`; code at `lib.rs:44-56`.
- Observed gap: The comment says "Vincenty approximation of degree-to-km conversion." The code uses `111.32 * cos(lat)` (linear). Lines 47-54 of the same file describe it as linear.
- Proposed fix: Change the comment to "linear approximation of degree-to-km conversion."
- Verdict: Confirmed. Evidence: `lib.rs:37` vs `lib.rs:47-56`.
- Routing: in-branch -> Wave 5.

### 5. Kernel normalization comment names the wrong source
- Severity: Low
- Anchors: `src/rust/src/lib.rs:335-337`.
- Observed gap: The comment attributes `1 / (2 * pi * bw^2)` to "Silverman's normalization." Silverman's rule is a bandwidth-selection heuristic (`R/geodensity.R:362`), not a kernel normalization.
- Proposed fix: Replace with "2D Gaussian normalization (planar approximation)" or drop the attribution.
- Verdict: Confirmed. Evidence: `lib.rs:336` vs `R/geodensity.R:362`.
- Routing: in-branch -> Wave 5.

### 6. LOOCV normalization is not used by the KDE it scores
- Severity: Low
- Anchors: `src/rust/src/lib.rs:337` (`kernel_norm`), `lib.rs:349-350`; `src/rust/src/lib.rs:127-134` (KDE kernel has no normalization).
- Observed gap: LOOCV multiplies each kernel value by `kernel_norm`. The KDE in `geodesic_kde_rust` sums `exp(-0.5 (d/bw)^2)` with no normalization. The scores LOOCV ranks are therefore on a different scale from the density `kde_geodesic` returns. This is a correctness/spec question, not a formatting standard.
- Proposed fix: Decide with the Spec-axis reviewer whether the two should share a kernel. Do not change it in standards review.
- Verdict: Conditional. Evidence is the code difference above; whether it is a defect depends on the intended spec.
- Routing: in-branch, but spec decision -> user proposal.

### 7. Adaptive backend divides by zero on empty input
- Severity: Low
- Anchors: `src/rust/src/lib.rs:212` (no guard); compare `lib.rs:38-42` (guarded in `geodesic_kde_rust`); `R/geodensity.R:283-285` (R-side guard).
- Observed gap: `geodesic_kde_adaptive_rust` computes `sum / len` with no empty check, giving NaN for empty input. The R wrapper blocks this via `nrow(pts) == 0` at `R/geodensity.R:283`, so it is unreachable from `kde_adaptive()`, but reachable through `geodensity:::geodesic_kde_adaptive_rust(numeric(0), ...)`.
- Proposed fix: Either add the same guard as `lib.rs:38-42`, or document that the internal function requires non-empty input. The guard is the consistent option.
- Verdict: Conditional. Reachability through the internal function is confirmed by reading; the impact depends on whether the internal function counts as a supported surface.
- Routing: in-branch -> Wave 5 (optional).

### 8. Trailing whitespace in changed code
- Severity: Low
- Anchors: `src/rust/src/lib.rs` (18 lines, e.g. `:36`, `:43`, `:46`, `:49`, `:57`, `:60`, `:64`, `:67`, `:74`, `:77`, `:79`, `:83`, `:86`, `:121`, `:188`, `:191`, `:317`); `DESCRIPTION:6`, `:8`, `:9` (in branch); `DESCRIPTION:21`, `:23`, `:25` (pre-existing, outside branch).
- Observed gap: Trailing spaces in lines the branch added.
- Proposed fix: Strip trailing whitespace in those lines.
- Verdict: Confirmed. Evidence: `grep -n " $"` output above.
- Routing: `lib.rs` and `DESCRIPTION:6,8,9` in-branch -> Wave 5. `DESCRIPTION:21,23,25` -> user proposal.

### 9. Lines over 100 characters in new R code
- Severity: Low
- Anchors: `R/geodensity.R:289` (114 chars), `R/geodensity.R:452` (104 chars).
- Observed gap: Both lines were added by this branch and exceed 100 columns. The Makefile `lint` target runs lintr (`Makefile`, `lint:` target), so this is part of the lint standard.
- Proposed fix: Wrap the `sprintf` arguments across lines.
- Verdict: Confirmed. Evidence: `awk 'length > 100'` on `R/geodensity.R`.
- Routing: in-branch -> Wave 5.

### 10. Duplicate `.github` entries in `.Rbuildignore`
- Severity: Low
- Anchors: `.Rbuildignore:11` (`.github/`) and `.Rbuildignore:12` (`^\.github$`).
- Observed gap: Both lines match the same directory. The duplicate is harmless but noisy.
- Proposed fix: Keep `^\.github$` and drop `.github/`, or keep both and note why.
- Verdict: Confirmed. Evidence: both lines are in the branch diff (`git diff b7f07b8..HEAD -- .Rbuildignore`).
- Routing: in-branch -> Wave 5.

### 11. Stray word at the end of the DESCRIPTION Description field
- Severity: Low
- Anchors: `DESCRIPTION:14` ("...large geospatial datasets without.").
- Observed gap: The sentence ends with a dangling "without." The branch did not touch this line (it is unchanged context in the diff), so it is not in branch-changed code.
- Proposed fix: Remove "without" or finish the sentence.
- Verdict: Confirmed. Evidence: `grep -n "without\.$" DESCRIPTION`.
- Routing: outside branch code -> user proposal.

### 12. Rust `///` docs repeat R roxygen tags that nothing processes
- Severity: Low
- Anchors: `src/rust/src/lib.rs:12-18`, `:158-165`, `:303-306` (`@param`, `@return`, `@keywords internal` inside `///` comments); R docs in `R/extendr-wrappers.R:13-52` (generated, read only).
- Observed gap: Rust `///` blocks carry `@param`/`@return` tags that roxygen does not read. They duplicate the R docs and already drifted (see finding 1).
- Proposed fix: Keep a one-line description in the Rust `///` block and drop the roxygen tags.
- Verdict: Confirmed. Evidence: `R/extendr-wrappers.R` is the generated wrapper and carries its own `@param` text.
- Routing: in-branch -> Wave 5.

## No findings (checked)

- NAMESPACE vs `@export`: `R/geodensity.R` has four `@export` tags (`:69`, `:230`, `:400`, `:487`). `NAMESPACE:3-6` lists `S3method(print,bandwidth_cv)`, `export(bandwidth_optimize)`, `export(kde_adaptive)`, `export(kde_geodesic)`. Match.
- S3 registration: `S3method(print,bandwidth_cv)` (`NAMESPACE:3`) matches `print.bandwidth_cv` (`R/geodensity.R:488`), and `man/print.bandwidth_cv.Rd` exists.
- Rust registration: three `#[extendr]` functions (`lib.rs:19`, `:166`, `:307`) are all listed in `extendr_module!` (`lib.rs:368-372`). None is dead: `geodesic_kde_rust` is called at `lib.rs:176`; the other two are called from `R/geodensity.R:299` and `:456`.
- Roxygen completeness: every exported function has `@param` for each argument, `@return`, and `@export`. `print.bandwidth_cv` has `@param x`, `@param ...`, and `@export`; it has no `@return`, which is acceptable for a print method.
- Man pages: `man/kde_geodesic.Rd`, `man/kde_adaptive.Rd`, `man/bandwidth_optimize.Rd`, `man/print.bandwidth_cv.Rd` all exist.
- tinytest: the branch changes to `inst/tinytest/test_geodensity.R` are additions only (0 removed lines in `git diff -U0`). New sections use the same banner and `info =` style as the existing tests. Pre-existing oddities (duplicate descriptions for Tests 15 and 16; orphan comment at "Test 18") are in base code, not branch code: user proposal only.
- `R/extendr-wrappers.R`: generated, read only, not flagged for hand edits.
- DESCRIPTION CRAN fields: Title, Version, Authors@R with `cre`, Maintainer, License (CC0), Encoding, Description, URL, BugReports, Depends, Imports, Suggests all present.

## Routing summary

- Wave 5 (in-branch): findings 1, 2, 3, 4, 5, 7, 8 (lib.rs and DESCRIPTION:6,8,9), 9, 10, 12.
- User proposal: 6 (spec decision), 8 (DESCRIPTION:21,23,25), 11 (DESCRIPTION:14), and the pre-existing tinytest oddities above.
