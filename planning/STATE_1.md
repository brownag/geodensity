# STATE 1 -- orchestration 1 (geodensity, branch adaptive-GKDE-1)

Plan: `planning/EXECUTION_PLAN_1.md`. Template: `planning/PROMPT_TEMPLATE_1.md`.
Resume from this file. The orchestrator is disposable.

## Baseline (pre-wave-1, to be recorded by orchestrator before any change)

- [x] Tree clean apart from `planning/` at `488ce24` (planning committed as `a5c822a`)
- [x] `make test`: `[YES] All geodensity tests passed!` (no failures; pass counts not printed by the suite; 50+ warnings emitted, pre-existing)
- [x] LOOCV baseline (`set.seed(42)`, roxygen example data, `bandwidth_optimize(pts, bandwidth_min = 1, bandwidth_max = 50, n_bandwidths = 8)`): `bandwidth_opt` = 50 (top of grid, boundary optimum); `log_likelihood` (10 sig. digits) = -22.740032207, -22.209357431, -20.488981758, -17.765337732, -13.906234260, -10.772277308, -9.015811849, -8.595541678
- [x] `kde_geodesic` fingerprint (`set.seed(7)`, 60 pts in lon -110..-90 / lat 30..50, template res 0.5, bandwidth 50): sum = 381.40331803098; weighted (`sum(v * seq_along(v))`) = 286319.766842301
- [x] `kde_adaptive` fingerprint on the same inputs (pilot 50, min 5): sum = 185.405389775943; weighted = 139194.395787378
- Baseline script: `/tmp/claude-1000/-home-andrew-workspace-geodensity/7fece4b2-cdc1-43e5-8340-4aa49f08dc01/scratchpad/baseline.R` (scratch, not in repo)

## Wave board

| Wave | Task | Status |
| --- | --- | --- |
| 0 | 0.1.1 Test gate and revalidation | done |
| 1 | 1.1.1 remove LOOCV empty guard | done (ebb4b46) |
| 2 | 2.1.1 simplify adaptive central_lat | done (c0df31e) |
| 3 | 3.1.1 haversine to geo + LOOCV tolerance test | done (c220499) |
| 4 | 4.1.1 spec-axis review (read-only) | done (planning/reviews/REVIEW_1_SPEC.md) |
| 4 | 4.1.2 standards-axis review (read-only) | done (planning/reviews/REVIEW_1_STANDARDS.md) |
| 5 | 5.1.1 Search box uses the larger lon/lat radius | done |
| 5 | 5.1.2 Per-grid-latitude search sizing; independent brute-force KDE tests | done |
| 5 | 5.1.3 Independent adaptive tests: scaling formula, zero pilot, template dependence, default min | done |
| 5 | 5.1.4 Scalar validation; S7 and LOOCV tests | done |
| 5 | 5.1.5 Normalization to probability density; independent tests | done |
| 5 | 5.1.6 R roxygen | done |
| 5 | 5.1.7 Rust comments and whitespace | done |
| 5 | 5.1.8 Build hygiene; verify built tarball | done |
| 5 | 5.1.9 README.Rmd adaptive description | done |
| 5 | 5.1.10 Re-record fingerprint baseline after correctness checks | done |
| 6 | 6.1.1 Remove pre-existing empty-input guard in `geodesic_kde_rust` | done (closed by 5.1.2) |
| 7 | 7.1.1 Extract shared spatial-index helper | done |
| 8 | 8.1.1 Set `class(result)` to `bandwidth_cv` only; tests | done |
| 9 | 9.1.1 0.2.0 release prep | done |

## Task reports

_Workers append here, under `## {{id}}`, at most 15 lines each._

## 1.1.1

- Status: done. Removed the 3-line guard `if n_points == 0 || bandwidths.is_empty() { return vec![]; }` in `bandwidth_loocv_evaluate`.
- Files changed: `src/rust/src/lib.rs` lines 346-348 deleted (3 deletions). No other files touched.
- `make test`: `[YES] All geodensity tests passed!` (no failures; pass counts not printed, 50+ pre-existing warnings).
- Baseline re-check (`baseline.R`): bandwidth_opt = 50; log_likelihood identical to 10 sig. digits; kde_geodesic and kde_adaptive fingerprints identical.
- `git diff --stat -- . ':!planning'`: `src/rust/src/lib.rs | 3 ---`, 1 file changed.
- Deviations: none.
- Gotchas: the empty-bandwidths case now runs the O(n^2) distance pass before returning empty (approved). `planning/tasks/` is untracked and not committed.

## 2.1.1
- Status: DONE (uncommitted).
- Files changed: `src/rust/src/lib.rs` lines 239-244 (if/else replaced by one expression at line 240); 1 insertion, 5 deletions.
- `make test`: `[YES] All geodensity tests passed!`. No failures. Per-test pass counts not printed; 50+ pre-existing warnings.
- `git diff --stat -- . ':!planning'`: only `src/rust/src/lib.rs` listed.
- Deviations: none. `geodesic_kde_rust` (~line 66) untouched.
- Gotchas: with empty `y_coords` the function now yields NaN for `central_lat` instead of 0.0. Unreachable from `kde_adaptive` (R guard at `R/geodensity.R` line 283). `planning/tasks/` remains untracked and uncommitted.

## 3.1.1
- Status: DONE (not committed). `make test` prints `[YES] All geodensity tests passed!`.
- Files: `src/rust/src/lib.rs` (removed `haversine_distance_km`, old lines 6-33; LOOCV call now `geo::Point ... .haversine_distance(...) / 1000.0`, ~line 320). `inst/tinytest/test_geodensity.R` (new Test 31 before Summary, ~lines 420-440).
- Diff stat (excl. planning): 2 files, +23 / -32.
- LOOCV observed vs baseline (rel. diff): 1.7e-8, 1.8e-7, 2.4e-7, 6.1e-7, 9.1e-7, 8.6e-7, 5.5e-7, 3.6e-7. Max 9.1e-7 < 1e-5 tolerance.
- bandwidth_opt = 50 (boundary, as expected).
- Deviations: none.
- Gotchas: `make test` prints 50+ warnings (not inspected; likely pre-existing, not checked against baseline). zsh glob broke `grep --include`; use `--exclude-dir=vendor` instead.

## 5.1.1
- Status: DONE. The orchestrator amended the acceptance rule, and the change is kept (not reverted).
- Files changed: `src/rust/src/lib.rs` lines 65-66 (fixed-kernel search radius, `.min` to `.max`, comment updated) and line 223 (adaptive, `.min` to `.max`). `git diff --stat -- . ':!planning'`: 1 file, 4 insertions, 3 deletions. Nothing committed.
- Tests: `make test` prints `[YES] All geodensity tests passed!` on the current tree. Summary output only, so no per-test counts. No stored fingerprint baselines exist.
- Fixed kernel: increases only, each changed cell has a point within 3*bw that the old box excluded. Lat 40: no change. Lat 65: 5/29 cells (bw 50), 11/29 (bw 200).
- Adaptive, lat 65, bw 50: changed cells 21 22 23 25 26 (5). All trace to changed pilot densities. Two decreases of 5 total.
- Adaptive, lat 65, bw 200: 28/29 cells changed. Cells 8-12, 23-28 match changed pilot cells. The other 22 (1-7, 13-22, 29) trace to the reference max moving from 6.0756 to 6.1096, which rescales every per-cell scale.
- Adaptive high-latitude changes are pilot propagation, not a defect in this task.

## 0.1.1
- Status: DONE. Test gate now fails on failed or zero expectations. Revalidation of waves 0-5 passes.
- Files changed: `Makefile` (new `TEST_FILE ?= inst/tinytest/test_geodensity.R` above `test:`; `test` recipe rewritten). `planning/STATE_1.md` (this section). `planning/tasks/0.1.1.todo.md` (new). Nothing committed; no git add, index, or tree changes beyond these.
- Gate command (as written in Makefile):
  `Rscript -e "devtools::load_all(quiet=TRUE); r <- tinytest::run_test_file('$(TEST_FILE)'); d <- as.data.frame(r); n <- nrow(d); f <- sum(!d[['result']]); cat(sprintf('%d expectations, %d failed\n', n, f)); if (n == 0L || f > 0L) quit(status = 1L)"`
- Step 1 check: `as.data.frame()` on the `run_test_file` result gives one row per expectation with a logical `result` column (class `tinytests`). Passed, no fallback needed.
- Fail-file gate: `make test TEST_FILE=<scratchpad>/gate/test_fail.R`, exit `2` (make's code for a failed recipe; Rscript exits 1). Output saved to `<scratchpad>/gate/fail_run.txt`. Final line `2 expectations, 1 failed`.
- Real suite: `make test`, exit `0`. Final line `41 expectations, 0 failed`. Output saved to `<scratchpad>/gate/real_run.txt`.
- Revalidation (scratch copies via `git archive` plus `src/rust/vendor`, same Rscript gate line):

| Commit | Expectations | Failed | Exit |
|---|---|---|---|
| ebb4b46 | 39 | 0 | 0 |
| c0df31e | 39 | 0 | 0 |
| c220499 | 41 | 0 | 0 |
| a0feeda | 41 | 0 | 0 |

- Deviations: fail-file exit code is 2 (make), not 1 as the plan assumed. Dry run (`make -n test`) shows `TEST_FILE` default expanded correctly.
- Gotchas: `make test` still prints the "50 or more warnings" line (pre-existing, not inspected). Expectation counts differ between commits (39 vs 41) because tests were added in later waves.

## 5.1.2
- Status: DONE (uncommitted). Also closes 6.1.1: `central_lat` no longer appears in `geodesic_kde_rust` or `geodesic_kde_adaptive_rust` (`grep -n central_lat src/rust/src/lib.rs` returns nothing). 6.1.1 needs no separate edit.
- Files changed: `src/rust/src/lib.rs` (shared helper `search_half_widths_deg`; both KDE functions use per-grid-point half-widths and offsets `ox`/`oy`; the 45-deg cell cap is kept), `inst/tinytest/test_geodensity.R` (brute-force references `bf_haversine_km`, `bf_destination`, `bf_fixed`, `bf_adaptive`, `bf_expect`, `bf_tangent_bearing`; new cases A-G before Summary), `planning/tasks/5.1.2.todo.md`, `planning/STATE_1.md` (this section).
- Lat half-width: `cutoff_km / (R*pi/180)`, R = 6371.0088 km. Lon half-width: `asin(sin r / cos lat)` with `r = cutoff_km / R`. When `sin r / cos lat >= 1` (circle encloses a pole) the half-width is 180 deg. Cos guard: `|cos lat| <= 1e-9` gives 180 deg, so it can only widen the bound.
- Pole-enclosing points (half-width >= 90 deg) scan all data points once. A wide index window reaches the same point under its natural and wrapped keys, which double counts (pre-fix: 6.86 vs reference 4.86).
- make test: exit 0, `103 expectations, 0 failed`.
- Pre-fix (linear lon bound, before this section's fix) vs post-fix max relative diff against brute force:

| Case | Pre-fix | Post-fix |
|---|---|---|
| fixed tangent-east lat=40 bw=50 | 0 | 0 |
| fixed tangent-east lat=65 bw=50 | 1.2e-15 (pass) | 1.2e-15 |
| adaptive tangent-east lat=40 / 65 | 3.1e-16 / 1.2e-15 | same |
| fixed north 0.9996 lat=65 | 2.2e-14 | 2.2e-14 |
| fixed cell-edge tangent 0.9999x bw=700 lat=65 | 1.0 (FAIL) | 1.7e-15 |
| adaptive cell-edge tangent 0.9999x pilot=700 lat=65 | 1.0 (FAIL) | 0 |
| fixed pole-enclosing bw=300 | 0.41 (FAIL) | 3.7e-16 |
| adaptive pole-enclosing pilot=300 min=30 | 0.43 (FAIL) | 1.6e-15 |

- The east-tangent cases at lat 40 and 65 did not fail on the linear bound. The linear error is about 2e-4 relative at lat 65, and the index window is wider than the box (`ox * cell >= 1.5 * hw`), so the sliver is covered by cell slack. A failing case needs a capped cell with the window ending exactly at the cell edge, which is case G.
- c220499 (pre-5.1.1), same test file, scratch copy: 14 of 103 fail. Fixed heterogeneous bw=250, adaptive heterogeneous, fixed dateline (bw 60 and 120), adaptive dateline, fixed and adaptive index-boundary (bw 40/90), fixed tangent-east lat=65 (1.0), fixed pole-enclosing and adaptive pole-enclosing, and fixed and adaptive cell-edge. Passing: fixed heterogeneous bw=40, cutoff-band lat 40/65, tangent-east lat 40, adaptive tangent-east lat 65, north 0.9996.
- Low-latitude diffs: all HEAD diffs are 1e-15 to 1e-13, from summation order.
- Deviations: (1) pole case uses full scan for half-width >= 90 deg, not `ox`/`oy`. This is needed for correctness (see above). Non-pole points keep `ox`/`oy`. (2) Spec's "due east" is the tangent (max-longitude) bearing, found numerically, because the due-east geodesic from lat 65 bends south. (3) Adaptive east cases use the single-cell construction, so they do not test the exact box edge; the fixed cell-edge case does.
- Gotchas: `make test` still prints the "50 or more warnings" line (from DESCRIPTION, pre-existing). The pole full scan is O(n) per pole-enclosing grid point, which is slow for large bandwidths at high latitude. Two blank lines remain where `search_radius_cells` was removed (cosmetic, 5.1.7).

## 5.1.3
- Status: DONE (uncommitted). Test-only; no source changes.
- Files changed: `inst/tinytest/test_geodensity.R` (new Test 33 block before Summary, reuses `bf_fixed`, `bf_adaptive`, `bf_expect`), `planning/tasks/5.1.3.todo.md`, `planning/STATE_1.md` (this section).
- make test: baseline exit 0 at `103 expectations, 0 failed`; after edits exit 0 at `112 expectations, 0 failed` (9 new expectations).
- Tests:
  - 33a scaling formula: `kde_adaptive` vs `bf_adaptive` (pilot 150, min 15, 10x10 cells, 150 seeded points) at `bf_expect` 1e-10; plus `d_max > 0` and every brute-force scale in `[min, pilot]`. Fails if the scale formula, the pilot, or the per-cell cutoff changes.
  - 33b zero pilot density: template lon -20..-10, lat 30..50, pilot 50. Asserts all values `== 0` and no NaN/Inf. Fails if the zero-density path divides by zero or returns non-zero values.
  - 33c template dependence: template A (lon -110..-90, lat 33..47) and B (lon -106..-100, lat 35..45). B excludes the global pilot max (cell -99.5, 41.5), so `d_max` B < `d_max` A (asserted). Shared cell (-103.5, 38.5) differs: A = 8.1786, B = 8.1605. `d_max` is the template maximum, so the scale depends on the template. Fails if `d_max` is taken from a fixed or global value.
  - 33d default min: `kde_adaptive(..., min_bandwidth = NULL)` vs `0.1 * 150`, compared with `expect_identical` on `terra::values()`. Fails if the default fraction changes.
- Demonstration (scratch only, no repo test added): scratchpad `demo.R`, same inputs as 33a.
  - Sqrt formula (the code): max relative diff 4.312e-15 vs brute force.
  - No-sqrt formula `min + (pilot-min)*(1/(1+d/d_max))`: max relative diff 3.129e-01; 99 of 100 cells exceed 1e-6.
- Deviations: test 33d compares `terra::values()` instead of the SpatRaster objects, since SpatRaster identity is pointer-based (approved by coordinator). Test 33c adds an explicit `d_max` ordering assertion to make the template dependence visible.
- Gotchas: the first template-B choice (lon -106..-99) included the global max cell, so `d_max` was unchanged and the shared cell did not differ. Moved B's east edge to -100. The 1-degree grid cell at (-99.5, 41.5) has ratio 1 and is the only cell where sqrt and no-sqrt agree. The "50 or more warnings" line from `make test` is pre-existing.

## 5.1.4
- Status: DONE (uncommitted). Validation change in `R/geodensity.R`; tests in `inst/tinytest/test_geodensity.R` (new Test 34 block before Summary); `planning/tasks/5.1.4.todo.md`.
- make test: baseline exit 0 at `112 expectations, 0 failed`. After 34a-34e (before validation): exit 0 at `120 expectations, 0 failed`. 34f added, red: exit 2 at `122 expectations, 2 failed` (both length-2 tests). After S10 validation: exit 0 at `122 expectations, 0 failed`.
- Tests:
  - 34a LOOCV floor: `bandwidth_loocv_evaluate(c(-100,-20), c(40,0), 1)` equals `log(1e-10)` at tolerance 1e-12. Fails if the floor value or the mean normalization changes.
  - 34b LOOCV score scale: 12 seeded points, bw = 50 km (`bandwidths[1]`), brute force with `1/(2*pi*bw^2)`, no cutoff, floor 1e-10, mean over n. Tolerance 1e-10. Guard: all brute-force densities > 1e-10. Comment marks this as intensity normalization (D10), not probability density.
  - 34c print.bandwidth_cv: header and "Optimal bandwidth" lines present (`capture.output`).
  - 34d verbose = TRUE: output contains "OPTIMAL".
  - 34e validation: `bandwidth_max <= bandwidth_min` errors; `n_bandwidths = 1.5` errors.
  - 34f S10: length-2 `bandwidth_min` and `bandwidth_max` error with "must be a single number". Red before the change (old R coercion error does not name the argument), green after.
- 34b values (scratch run): bw = 50.0000000000 km. Code = -11.412125545848591. Brute force = -11.412125545848594. Relative diff 3.1e-16. Minimum brute-force density 2.0e-07 (no floor hit).
- Source change: `R/geodensity.R`, two length checks inserted before the `<= 0` checks in `bandwidth_optimize`. Messages: "bandwidth_min must be a single number", "bandwidth_max must be a single number".
- Not changed: LOOCV code, `src/rust/`, Test 31 values, roxygen.
- Gotchas: the "50 or more warnings" line from `make test` is pre-existing. The 34b scratch script is in the scratchpad (`val34b.R`).

## 5.1.5
- Status: DONE (uncommitted). Normalization to probability density (Q1 = B, D10): each KDE output divided by `2*pi*bw^2*n` (fixed) or `2*pi*scale_i^2*n` (adaptive, per cell).
- Files changed: `src/rust/src/lib.rs`, `inst/tinytest/test_geodensity.R`, `planning/tasks/5.1.5.todo.md` (plan), this report.
- Division sites (`src/rust/src/lib.rs`):
  - `geodesic_kde_rust`: lines 148-150, after `.collect()`, `norm = 2*pi*bandwidth_km^2*x_coords.len()`, `densities.iter().map(|&d| d / norm).collect()`.
  - `geodesic_kde_adaptive_rust`: lines 304-311, after Pass 3 `.collect()`, `densities.iter().zip(scales.iter()).map(|(&d, &s)| d / (2*pi*s*s*n)).collect()`, `n = x_coords.len()`.
  - Accumulation (`sum`), the kernel exponent, the `3*bw` cutoff, search boxes, and LOOCV are unchanged.
- Pilot invariance: the adaptive pilot calls `geodesic_kde_rust`, so it is normalized too. `reference_density` and `density_ratio = d / max(d)` are scale-invariant, so scales are unchanged. Tests at 33a-33d and 5.1.2 stay green.
- Test helpers: new `bf_fixed_norm` (`bf_fixed / (2*pi*bw^2*n)`) and `bf_adaptive_norm` (returns `list(density, scale)`). `bf_fixed` and `bf_adaptive` are unchanged; the 33-series pilot checks use them. The 5.1.2 case blocks (Cases A-G, 15 call sites) compare against the normalized references. Inputs, seeds, grids, and bandwidths are unchanged.
- Deviation: the Test 33a comparison (test file line ~670, `t1_ref`) compared the normalized `kde_adaptive` output against the unnormalized `bf_adaptive`. It failed (`122 expectations, 1 failed`). Its reference was switched to `bf_adaptive_norm(...)$density`. Comparison and tolerance are unchanged. Not a stop-rule case: the mismatch is the reference missing the factor, not a brute-force difference above 1e-10.
- make test: exit 0 at `122 expectations, 0 failed` (expectation count unchanged from 5.1.4; no new expectations added). Test 31 and 5.1.4 LOOCV tests pass with no edits. `git diff` has no hunks in those regions.
- Integral sanity check (scratch only, not asserted): fixed bw = 50 km, 400 seeded points uniform on lon -104..-96, lat 36..44, grid 0.05 deg over lon -112..-88, lat 28..52. Integral of output times cell area (spherical-planar cell area in km^2) = 0.988874. Deviation about 1.1% from the planar approximation, the 3*bw truncation, and the spherical metric.
- n = 0: outside the supported-input contract (D15). The R layer rejects it. No guard added.
- Gotchas:
  - `make test` on failure exits with status 2 (make wraps the R `quit(status = 1)`). Read the exit code, not the R status.
  - The "50 or more warnings" line from `make test` is pre-existing.
  - Scratch scripts: `integral_515.R` and the two `make_test_515*.txt` outputs in the scratchpad.

## 5.1.6
- Status: DONE (uncommitted). R roxygen documentation updated in `R/geodensity.R`.
- Files changed: `R/geodensity.R` (roxygen blocks; two code lines wrapped per coordinator approval), `planning/tasks/5.1.6.todo.md` (plan), this report.
- Roxygen changes:
  - `kde_geodesic`: Rayon claim removed from description; `@return` states probability density per km² (kernel sum / `2*pi*bw^2*n`), planar approximation, integrates to approximately 1.
  - `kde_adaptive`: algorithm step 2 now states `bw_i = min + (pilot - min) / (1 + sqrt(d_i / d_max))` (matches `geodesic_kde_adaptive_rust`, `powf(0.5)`, `scale_factor`); old `pilot / sqrt(density)` wording removed. `@return` states per-km² normalization with per-cell `bw_i`. New `## Grid Dependence` details subsection.
  - `bandwidth_optimize`: LOOCV serial (Rayon claim removed); density floor 1e-10 documented; n x n distance matrix memory cost documented; `1/(2*pi*bw^2)` normalization and constant `log(n)` offset documented; `log_likelihood` `@return` item updated.
- Code wraps (approved): `message(sprintf(...))` string in `kde_adaptive` split with `paste0` (was 114 chars); `cat(sprintf(...))` in `bandwidth_optimize` split across lines (was 104 chars).
- Verification:
  - Rendered-string comparison (scratch `render.R`, before vs after): `kde_adaptive` message and `print.bandwidth_cv` output identical.
  - `grep -n -i rayon R/geodensity.R`: no output. `grep -n "sqrt(density)"`: no output. `awk 'length > 100'`: no output.
  - Non-comment diff lines are only the two approved wraps.
  - `make test`: exit 0, `122 expectations, 0 failed`.
- Not done: `man/` and `NAMESPACE` not regenerated (`make docs` in 9.1.1), so the man pages are stale until then.
- Out of scope, reported only: `src/rust/src/lib.rs` still says `pilot_bw / sqrt(pilot_density)` in the `geodesic_kde_adaptive_rust` doc comment (around line 161), and it mentions Rayon at lines 4 and 33. Code comments at `R/geodensity.R` lines 126 and 298 still say "Rust backend handles parallelization", which is accurate.

## 5.1.7
- Status: DONE (uncommitted). Comment and whitespace only in `src/rust/src/lib.rs`.
- Files changed: `src/rust/src/lib.rs`, `planning/tasks/5.1.7.todo.md` (plan), `planning/STATE_1.md` (this report).
- Changes:
  - Item 1 (Vincenty): no edit needed. Already gone from HEAD.
  - Item 2: LOOCV kernel normalization comment now reads "2D Gaussian normalization (planar approximation)", with the no-1/n (D10) fact stated.
  - Item 3: doc blocks for the adaptive and grid KDE functions use `bw_i = min + (pilot - min) / (1 + sqrt(d_i / d_max))`. The inline Pass 2 comment uses the same formula. LOOCV doc says serial.
  - Item 4: `@param`, `@return`, `@keywords internal` dropped from the three `#[extendr]` doc blocks. One-line descriptions kept. `R/extendr-wrappers.R` not touched.
  - Item 5 (F8): trailing whitespace stripped on the 4 branch-added lines (adaptive 166, 169; LOOCV 295, 312 in new numbering). Pre-existing lines 61, 64, 66, 70, 73 untouched.
  - Item 6: one of the two blank lines before "// 5. Parallel iteration" removed.
- Verification:
  - `make test`: exit 0, `122 expectations, 0 failed`.
  - Baseline `baseline.R` before/after: byte-identical (`cmp`).
  - Comment-only diff check: empty output.
  - `grep " $"`: only pre-existing lines 61, 64, 66, 70, 73.
  - `grep -i "vincenty|silverman|sqrt(density)|sqrt(pilot_density)"`: no hits.

## 5.1.8
- Status: DONE with one deviation (see below). Uncommitted.
- Files changed: `.Rbuildignore`, `DESCRIPTION`, `planning/tasks/5.1.8.todo.md` (plan), `planning/STATE_1.md` (this report).
- Changes:
  - F3: `^planning$` added to `.Rbuildignore` (line 12).
  - F10: duplicate `.github/` line removed. `^\.github$` kept. `.github/development/` kept.
  - F8: trailing whitespace stripped on DESCRIPTION lines 6, 8, 9. Lines 21, 23, 25 (pre-existing) and line 14 untouched.
- Verification:
  - `make test`: exit 0, `122 expectations, 0 failed`.
  - `grep -c '^\^planning\$' .Rbuildignore`: 1 (single quotes; the double-quoted form in the spec returns 0 because the shell turns `\$` into a regex anchor).
  - `grep -c '^\.github/$' .Rbuildignore`: 0.
  - `grep -n " $" DESCRIPTION`: lines 21, 23, 25 only.
  - `R CMD build --no-build-vignettes` from scratchpad: exit 0. Tarball `/tmp/claude-1000/-home-andrew-workspace-geodensity/7fece4b2-cdc1-43e5-8340-4aa49f08dc01/scratchpad/geodensity_0.1.1.tar.gz`, 2946482 bytes, 37 entries.
  - Tarball counts: `geodensity/planning/` 0; `geodensity/.github/` 0; `geodensity/src/rust/vendor/` (directory) 0.
  - Build warning: `Warning in person1(...): It is recommended to use 'given' instead of 'middle'.` (from the Authors@R `middle =` field; not fixed, out of scope).
- Deviation: the spec's vendor check `^geodensity/src/rust/vendor` (no trailing slash) matches 2 sibling files, `geodensity/src/rust/vendor-config.toml` and `geodensity/src/rust/vendor.tar.xz`. Neither is in the vendor directory. Excluding them would need new `.Rbuildignore` patterns, which are outside the listed items, so they were not added.

## 5.1.9
- Status: DONE. Uncommitted.
- Files changed: `README.Rmd` (2 paragraphs, 2 lines changed), `planning/tasks/5.1.9.todo.md` (plan), `planning/STATE_1.md` (this report).
- Changes:
  - Adaptive section intro: "scales the bandwidth inversely with local density" replaced with "shrinks the bandwidth where local density is high, bounded between `min_bandwidth` and `pilot_bandwidth`".
  - Two-pass paragraph step (2): replaced "inversely with the pilot density" with the roxygen formula `bw_i = min + (pilot - min) / (1 + sqrt(d_i / d_max))`, definitions of `d_i` and `d_max`, the `[min_bandwidth, pilot_bandwidth]` bound, and a template-dependence sentence.
  - Not touched: `{r adaptive}` chunk, LOOCV section, `README.md`, `README.html`.
- Verification:
  - `grep -n "sqrt(pilot_density)\|pilot_bandwidth / sqrt\|pilot / sqrt" README.Rmd`: no output.
  - `grep -n -i "rayon\|parallel" README.Rmd`: lines 26 and 118, both CPU-parallel claims for the kernel computation, correct. No LOOCV parallel claim exists.
  - `grep -n "sqrt" README.Rmd`: line 157 only, with the roxygen formula.
  - `make test`: exit 0, `122 expectations, 0 failed`. Log at `/tmp/claude-1000/-home-andrew-workspace-geodensity/7fece4b2-cdc1-43e5-8340-4aa49f08dc01/scratchpad/make_test_519.log`.
  - `git diff --stat -- . ':!planning'`: `README.Rmd | 4 ++--` (1 file).
- Density scale: no change needed. README.Rmd states no normalization.
- Deviations: none from the approved plan. The LOOCV parallel-claim step was skipped as approved.
- Gotchas: `README.md` and `README.html` are stale until 9.1.1 runs `make readme`. The `{r adaptive}` chunk still shows the pre-fix prose context; its code is unchanged and was not run.

## 5.1.10 -- Post-correction baseline (supersedes the pre-wave-1 fingerprints)

Recorded at HEAD `d005a6f`, after all correctness checks in Wave 5 passed (D11, D14). Scratch script: `scratchpad/baseline.R`.

- LOOCV (`set.seed(42)`, roxygen example data, bandwidth_min 1, bandwidth_max 50, n 8): bandwidth_opt = 50; log_likelihood = -22.740032588, -22.209361462, -20.488986643, -17.765348655, -13.906246941, -10.772286545, -9.015816765, -8.595544798. Unchanged in substance from the pre-wave-1 values by a relative 1e-6 at most (Test 31 pins them); LOOCV keeps intensity normalization (D10).
- `kde_geodesic` fingerprint (`set.seed(7)`, 60 points, template res 0.5, bandwidth 50): sum = 0.000404681489175205; weighted = 0.303794707985808.
- `kde_adaptive` fingerprint (same inputs, pilot 50, min 5): sum = 0.00045957830060645; weighted = 0.346911919218158.

Superseded pre-wave-1 fingerprints (unnormalized, pre-search-fix), kept for reference: kde_geodesic sum 381.40331803098, weighted 286319.766842301; kde_adaptive sum 185.405389775943, weighted 139194.395787378.

Check on the change: 381.40331803098 / (2*pi*50^2*60) = 4.0468e-4, matching the new fixed sum. The adaptive sum moved by more than a constant factor, as expected from pilot propagation of the search fix and per-cell normalization (see `## 5.1.1`).

## 7.1.1 -- Extract shared spatial-index helper

- Status: done. No behavior change.
- Change (`src/rust/src/lib.rs`): added private `index_cell_size(grid_y: &[f64], cutoff_km: f64) -> f64` and `build_spatial_index(data_points: &[Point<f64>], cell_size: f64) -> HashMap<(i32, i32), Vec<usize>>`. `geodesic_kde_rust` and `geodesic_kde_adaptive_rust` now call them for the cell size and index build. Cutoffs stay `3 * bandwidth_km` (fixed) and `3 * pilot_bandwidth_km` (adaptive). Kernel loops, normalization, `search_half_widths_deg`, and the pilot call are unchanged. Per-grid-point offset math stays inline.
- Gate: `make test` exit 0, `122 expectations, 0 failed`.
- Baseline: `scratchpad/baseline.R` output before and after the edit is byte-identical (`cmp` exit 0). Fingerprints match 5.1.10: fixed sum 0.000404681489175205, weighted 0.303794707985808; adaptive sum 0.00045957830060645, weighted 0.346911919218158; LOOCV log-likelihoods unchanged.

## 8.1.1

- Status: done. User-visible change: `bandwidth_optimize()` now returns class `"bandwidth_cv"` only (was `c("bandwidth_cv", "list")`). Recorded in NEWS.md in 9.1.1.
- Change (`R/geodensity.R`, line 520): `class(result) <- "bandwidth_cv"`. Roxygen `@return` unchanged (already says "A list with class `bandwidth_cv`").
- Test (`inst/tinytest/test_geodensity.R`, Test 34c2): `expect_equal(class(b34_res), "bandwidth_cv")` and `expect_true(is.list(b34_res))`.
- Red: with the test added and the class unchanged, `make test` gave `124 expectations, 1 failed` (the class assertion, test 118).
- Green: after the change, `make test` exit 0, `124 expectations, 0 failed`.
- Baseline before the task: `122 expectations, 0 failed` (exit 0).
- Print: `print(res)` output still contains "Bandwidth Cross-Validation Results" and "Optimal bandwidth". `NAMESPACE:3` `S3method(print,bandwidth_cv)` unchanged; not regenerated.

## 9.1.1 -- 0.2.0 release prep (verified on the final tree)

- Commits: `2ce0b76` (test: internal kde calls qualified through the namespace; fixes an installed-package check ERROR), `cb52ceb` (chore: version 0.2.0, NEWS.md, regenerated man/, README, NAMESPACE unchanged). Maintainer name corrected to "Andrew Gene Brown". No tag, no push.
- `devtools::check()` (run directly, not `make check`): Status 0 errors, 0 warnings, 1 NOTE.
  - NOTE, checking compiled code: `Found non-API call to R: 'R_NamespaceRegistry'` in `libs/geodensity.so`. Comes from the extendr-generated bindings, not from this branch's code. Open item for CRAN.
- `make test`: exit 0, `124 expectations, 0 failed`.
- Tarball `geodensity_0.2.0.tar.gz` (R CMD build, scratchpad): 0 `planning/`, 0 `.github/`, 0 `src/rust/vendor/` entries. `src/rust/vendor-config.toml` and `src/rust/vendor.tar.xz` are included by design (offline compilation).
- R CMD build warning: `person1(... middle = ...)` recommends `given` instead of `middle`. Pending a decision on how the name is written.
