# Execution Plan 1 -- Subtractive resolutions, two-axis review, numeric corrections, 0.2.0 release prep

Repo: `geodensity` (single repo). Branch: `adaptive-GKDE-1`. Review base: `b7f07b8` (merge-base with `main`).

Revision 2 (this file). Revision 1 was approved and executed through commit `a0feeda`. Revision 2 adds a test gate (Wave 0), replaces the Wave 5 acceptance criteria, and records the normalization decision as open. See D12-D15.

## Goal & Scope

**Goal.** Resolve the findings from the subtractive code review of `adaptive-GKDE-1`. Run a full two-axis code review (Spec, Standards) of the whole branch, `b7f07b8..HEAD`. Correct the numerical defects the review found, with independent tests for each. Then finish the three deferred cleanups and prepare the 0.2.0 release.

**In scope**
- Subtractive finding 1: unreachable empty-input guard in `bandwidth_loocv_evaluate` (Confirmed, Wave 1).
- Subtractive finding 2: unreachable empty-`y_coords` branch in `geodesic_kde_adaptive_rust` (Confirmed, Wave 2).
- Subtractive finding 3: duplicate Haversine helper, replaced by `geo` (Conditional, resolved as consolidate, Wave 3).
- Test gate: `make test` must exit nonzero on a failing expectation (Wave 0). Waves 1-3 are revalidated against it.
- Two-axis code review (Spec + Standards) of `b7f07b8..HEAD`, read-only (Wave 4).
- Review expansion, within branch-changed code only (Wave 5). Numerical corrections in Wave 5 each carry independent tests.
- Pulled-in deferrals: the pre-existing empty guard in `geodesic_kde_rust`, a shared spatial-index helper, and the `class(result)` `"list"` removal (Waves 6-8).
- 0.2.0 release prep: version bump, `NEWS.md`, README re-render, `devtools::check()`, tarball check (Wave 9).

**Out of scope**
- Any git push, tag, PR, or other remote write (user CLAUDE.md: no remote write operations). Tagging is left to the user.
- Changes to `R/extendr-wrappers.R` by hand. It is generated.
- Findings outside branch-changed code. These go to the user as proposals (D5).
- Rewriting the `geo` dependency or the vendoring workflow.
- Broader architecture work. Deferred until after a stable 0.2.0.
- Pre-existing `DESCRIPTION` lines 14, 21, 23, 25 and pre-existing tinytest oddities (duplicate descriptions for Tests 15 and 16; orphan comment at "Test 18"). These are user proposals, not automatic D5 expansion.
- Parallelizing LOOCV. The Rust function is serial. The false parallelism claim is removed from the docs instead.

**Verbatim constraints (from user)**
- "resolutions for results from subtractive code review"
- "add a full code review to the root commit 2 axis as part of the plan"
- "allow for expansion of the plan based on findings"
- "add all as waves at end of plan to prep for 0.2.0 release"
- Revision 2 instruction: "Revise Plan 1 before continuing Wave 5." Its required changes are listed in D12-D15 and Waves 0 and 5.

## Decision log

- **D1 (2026-11-08).** Review base is the branch's fork point, `b7f07b8`, covering all 6 branch commits. Recommended option taken.
- **D2 (2026-11-08).** Haversine finding: consolidate on `geo::Point::haversine_distance` (option A). Requires a LOOCV tolerance test against a pre-change baseline.
- **D3 (2026-11-08, revised by D12).** Acceptance is strict. Each wave adds the tests for its own change. Originally `make test` was the gate; D12 replaces it with an exit-status gate. `devtools::check()` runs in the release wave.
- **D4 (2026-11-08).** Serial execution, one worker per task, no worktrees. Every code task touches `src/rust/src/lib.rs` or `R/geodensity.R`, so no two code tasks share a wave.
- **D5 (2026-11-08).** Review expansion: findings in code this branch added or changed become Wave 5 tasks. Findings outside the branch diff go to the user as proposals.
- **D6 (2026-11-08).** Workers run on `claude-haiku-5-5`. Escalation (after two failed acceptances or an off-spec plan) reruns on `claude-sonnet-5-5`.
- **D7 (2026-11-08, revised).** The three deferrals were originally proposed as deferred. User overrode: all three become waves at the end of the plan, before release prep.
- **Approval (2026-11-08).** User approved revision 1 as written, including D8 and the `devtools::check()` change in 9.1.1.
- **D8 (approved with revision 1).** Release prep bumps `DESCRIPTION` from `0.1.1` to `0.2.0`, adds `NEWS.md`, re-renders `README.md`, and runs `devtools::check()`. It does not tag or push. The vendor step is not run.
- **D9 (user choice, revision 1; Wave 5 scope).** Spec finding S2, the search box uses the smaller of the lon and lat radii, is fixed in Wave 5. Task 5.1.1 changed `min` to `max` (commit `a0feeda`). Revision 2 finds that this does not establish complete coverage, because sizing still uses the mean input latitude. Task 5.1.2 corrects this.
- **D10 (user choice, revision 1; quantity OPEN).** The user chose "Normalize KDE output" in the question dialog. That dialog described the result as "true density per km²", computed by dividing by `2*pi*bw^2`. Provenance is preserved here. The factor gives *point intensity* (kernel sum per km²). A *probability density* also divides by the observation count `n`. The two differ by a factor of `n`. The planar Gaussian factor is an approximation: spherical distance, the `3*bw` truncation, and per-cell bandwidths mean it does not give exact global normalization. **Resolved (2026-11-08, Q1 = B).** The user asked which convention is more standard, and then said "proceed." The recommendation was B, probability density: divide by `2*pi*bw^2*n`. Reasoning: in KDE, "density" means a function that integrates to 1, which is R's `density()` convention. Point intensity (A) is the spatstat `density.ppp` default, but the package's output is named "density" throughout. LOOCV keeps its intensity normalization, unchanged; its log-likelihood therefore differs from the KDE output by a constant `log(n)`, which does not change the bandwidth argmax. The difference is documented in 5.1.6, and Test 31 stays pinned.
- **D11 (revised by D14).** The fingerprint baseline is re-recorded only after the correctness checks pass (Task 5.1.10). The pre-wave-1 fingerprints are superseded at that point.
- **D12 (2026-11-08, revision 2).** Test gate. `make test` runs tinytest through `tinytest::run_test_file()`, counts expectations, and exits nonzero when any fails. The current target sources the file and prints an unconditional success message. A deliberately failing expectation exits 0 under the current target, so that message is not evidence. Task 0.1.1 installs the gate and verifies it. Waves 1-3 and the commit at `a0feeda` are revalidated under the gate.
- **D13 (2026-11-08, revision 2).** Each behavior-changing task carries its own independent numerical tests in the same commit. Tests compare against an independent R brute-force reference, not against the code under test. Changes that alter values never leave the suite red for a later task. The numeric expectations at lines 52, 62, 240, and 312 check dimensions, CRS, and length, not values, so normalization does not break them. No task instructs updating them.
- **D14 (2026-11-08, revision 2).** The fingerprint replacement is recorded only after all correctness checks pass (Task 5.1.10). LOOCV values are unchanged by any task in this plan, unless the open quantity choice (D10) changes LOOCV scores. Test 31 pins them.
- **D15 (2026-11-08, revision 2).** Supported-input contract. Internal Rust functions need not defend unsupported empty input. The R layer enforces the contract. No new defensive guards are added. This retains the approved rationale for Tasks 1.1.1 and 2.1.1, and it is why the proposed guard for `geodesic_kde_adaptive_rust` was dropped.
- **D17 (2026-11-08, from 5.1.2 review).** Search-box degree constant. Task 5.1.2 uses `R*pi/180` km-per-degree for latitude and `R*pi/180*cos(lat)` for longitude, with `R = 6371008.8 m` (the `geo` mean radius), instead of `111.32`. The 111.32 constant gives a box about 0.1% too small for the kernel's own distance metric, which breaks the conservative-box requirement. The 0.999× test case shows the miss is closed. The cell cap at 45° is kept, since offsets are computed per point. Task 6.1.1 is marked done by 5.1.2 and verified by grep. `kde_adaptive` already enforces `min < pilot`, so scale ≤ pilot holds on supported input.
- **D16 (2026-11-08, revision 2).** Release checks reconciled. Release check command: `devtools::check()`, not `make check`. `NEWS.md` covers the search-box correction, the normalization (as decided under D10), the removal of the false LOOCV parallelism claim, the guard removals, and the `bandwidth_cv` class change. The planning exclusion is verified in the built tarball, not only in `.Rbuildignore`.

## Baseline (pre-wave-1, recorded in STATE_1.md)

Recorded before any change. Superseded by Task 5.1.10 for the `kde_*` fingerprints. LOOCV values remain pinned by Test 31.
1. `make test` output: pass/fail counts (superseded by the gate in D12).
2. LOOCV baseline: `set.seed(42)`, roxygen example dataset, `bandwidth_optimize(pts, bandwidth_min = 1, bandwidth_max = 50, n_bandwidths = 8)`. Recorded `log_likelihood` values to 10 significant digits. Pinned by Test 31 at tolerance `1e-5` (Task 3.1.1).
3. `kde_*` fingerprints on the fixed template and point set (`set.seed(7)`, 60 points, template res 0.5). Superseded by Task 5.1.10.

## Wave / dependency table

Every code task touches `src/rust/src/lib.rs` or `R/geodensity.R`, so each code task has its own wave (D4).

| Wave | Task id | Title | Depends on | Files (must edit) |
| --- | --- | --- | --- | --- |
| 0 | 0.1.1 | Test gate: `make test` exits nonzero on failure; revalidate Waves 1-3 and HEAD (D12) | 5.1.1 (done, a0feeda) | `Makefile` |
| 1 | 1.1.1 | Remove unreachable empty-input guard in `bandwidth_loocv_evaluate` (done, ebb4b46) | baseline | `src/rust/src/lib.rs` |
| 2 | 2.1.1 | Simplify adaptive `central_lat` (done, c0df31e) | 1.1.1 | `src/rust/src/lib.rs` |
| 3 | 3.1.1 | Replace `haversine_distance_km` with `geo`; LOOCV tolerance test (done, c220499) | 2.1.1 | `src/rust/src/lib.rs`, `inst/tinytest/test_geodensity.R` |
| 4 | 4.1.1 | Spec-axis review (read-only, done) | 3.1.1 | creates `planning/reviews/REVIEW_1_SPEC.md` |
| 4 | 4.1.2 | Standards-axis review (read-only, done) | 3.1.1 | creates `planning/reviews/REVIEW_1_STANDARDS.md` |
| 5 | 5.1.1 | Search box uses the larger lon/lat radius (done, a0feeda; acceptance superseded by 5.1.2) | 4.1.1 | `src/rust/src/lib.rs` |
| 5 | 5.1.2 | Per-grid-latitude search sizing; independent brute-force KDE tests (fixed and adaptive) | 0.1.1, 5.1.1 | `src/rust/src/lib.rs`, `inst/tinytest/test_geodensity.R` |
| 5 | 5.1.3 | Independent adaptive tests: scaling formula, zero pilot, template dependence, default vs explicit min (test-only) | 5.1.2 | `inst/tinytest/test_geodensity.R` |
| 5 | 5.1.4 | Scalar validation; S7 print, verbose, and validation tests; LOOCV floor and score-scale tests | 5.1.3 | `R/geodensity.R`, `inst/tinytest/test_geodensity.R` |
| 5 | 5.1.5 | Normalization to probability density: divide by `2*pi*bw^2*n` (Q1 = B, D10); independent tests | 5.1.4 | `src/rust/src/lib.rs`, `inst/tinytest/test_geodensity.R` |
| 5 | 5.1.6 | R roxygen: S1, S3 wording, S4, S5, S6, S8, F2 (remove Rayon claim), F9 | 5.1.5 | `R/geodensity.R` |
| 5 | 5.1.7 | Rust comments and whitespace: F4, F5, F8 (lib.rs), F12 (no guard; D15) | 5.1.6 | `src/rust/src/lib.rs` |
| 5 | 5.1.8 | Build hygiene: F3, F10, F8 (DESCRIPTION 6, 8, 9); verify built tarball | 5.1.7 | `.Rbuildignore`, `DESCRIPTION` |
| 5 | 5.1.9 | README.Rmd adaptive description (S11) | 5.1.8 | `README.Rmd` |
| 5 | 5.1.10 | Re-record fingerprint baseline after all correctness checks pass (D14) | 5.1.9 | `planning/STATE_1.md` |
| 6 | 6.1.1 | Remove pre-existing empty-input guard in `geodesic_kde_rust` (D15) | 5.1.10 | `src/rust/src/lib.rs` |
| 7 | 7.1.1 | Extract shared spatial-index helper | 6.1.1 | `src/rust/src/lib.rs` |
| 8 | 8.1.1 | Set `class(result)` to `"bandwidth_cv"` only; tests | 7.1.1 | `R/geodensity.R`, `inst/tinytest/test_geodensity.R` |
| 9 | 9.1.1 | 0.2.0 release prep: version, NEWS, README re-render, `devtools::check()`, tarball check (D16) | 8.1.1 | `DESCRIPTION`, `NEWS.md` (create), `README.md`, `README.html`, `man/`, `NAMESPACE` |

Wave 4 holds two read-only tasks, both done. They wrote to separate report files.

Q1 resolved: B, probability density (D10). Task 5.1.5 is unblocked.

## Hazard notes from recon

- `src/rust/src/lib.rs` is about 370 lines. Enter it by anchor only. Anchors are approximate, so workers must grep first.
- The index setup is duplicated in `geodesic_kde_rust` and `geodesic_kde_adaptive_rust`. Both derive `search_radius_deg` and `index_cell_size` from the mean input latitude, which is wrong for grid points at other latitudes. Task 5.1.2 fixes this in both.
- `src/rust/vendor/` is gitignored and holds the vendored `geo` 0.28.0 source. Read it only to check API behavior. Never edit it.
- `make test` currently sources the test file and prints success unconditionally. D12 replaces it.
- Test expectations at lines 52, 62, 240, and 312 check dimensions, CRS, and length, not values (D13).
- `DESCRIPTION` says `Version: 0.1.1`. `NEWS.md` does not exist.
- `planning/` is not in `.gitignore`. Planning files are left uncommitted; only code tasks produce commits.
- Git push, tag, and PR creation are out of scope. The user's global CLAUDE.md forbids remote writes.
- Independent reference computations must use the same Earth radius as the code under test: `geo`'s mean radius, 6371.0088 km (vendored `geo` 0.28.0, `MEAN_EARTH_RADIUS = 6371008.8` m). Otherwise the comparison measures the radius, not the algorithm.
- Scratch files go in the session scratchpad: `/tmp/claude-1000/-home-andrew-workspace-geodensity/7fece4b2-cdc1-43e5-8340-4aa49f08dc01/scratchpad/`. Do not write scratch scripts into the repo.

---

## Task specs

### Task 0.1.1 -- Test gate and revalidation

- **Repo:** geodensity
- **Files in scope.** Must edit: `Makefile`. Can create: `planning/tasks/1.0.1.todo.md`, a `## 0.1.1` report in `planning/STATE_1.md`, scratch files under the scratchpad only.
- **Depends on:** 5.1.1 (done, `a0feeda`).
- **Spec.**
  1. Change the `test` target to run tinytest through `tinytest::run_test_file()`, count expectations, and exit nonzero when any fails. Use a `TEST_FILE` variable defaulting to `inst/tinytest/test_geodensity.R`, so the gate can be pointed at a scratch file. Shape:
     ```
     TEST_FILE ?= inst/tinytest/test_geodensity.R
     test:
     	@Rscript -e "devtools::load_all(quiet=TRUE); r <- tinytest::run_test_file('$(TEST_FILE)', verbose = 0); d <- as.data.frame(r); cat(sprintf('%d expectations, %d failed\n', nrow(d), sum(!d\$$result))); if (nrow(d) == 0L || !all(d\$$result)) quit(status = 1L)"
     ```
     Adjust escaping only as needed. The gate must fail on zero expectations too.
  2. Verify the gate with a deliberately failing temporary file in the scratchpad: `make test TEST_FILE=<scratchpad>/gate/test_fail.R; echo $?` must print nonzero. The failing file is the one already at `<scratchpad>/gate/test_fail.R` (one failing `expect_equal`, one passing `expect_true`).
  3. Run `make test; echo $?` on the real suite. It must print a count with 0 failed and exit 0.
  4. Revalidate earlier waves under the gate. For each of `ebb4b46` (1.1.1), `c0df31e` (2.1.1), `c220499` (3.1.1), and `a0feeda` (5.1.1): export the commit with `git archive <commit> | tar -x -C <scratchpad>/reval/<commit>`, copy `src/rust/vendor` into that directory, and run the same `tinytest::run_test_file` gate command there. Each must exit 0 with 0 failed. Do not change the repo working tree or index to do this.
  5. Record the gate command, the verification outputs, and the per-commit results in `planning/STATE_1.md`.
- **Anchors.** `Makefile` `test:` target (around line 44-46).
- **Do not touch.** Any other file. Do not run `make check` or `make vendor`.
- **Acceptance.** Items 2-4 as stated. A failing expectation returns nonzero. The real suite returns 0 with 0 failed. Waves 1-3 and `a0feeda` pass under the gate.
- **Escalation.** If any revalidated commit fails under the gate, stop and report. Do not change the gate to make it pass.

### Task 1.1.1, 2.1.1, 3.1.1, 4.1.1, 4.1.2, 5.1.1

Completed. See `planning/STATE_1.md` and the commits listed in the wave table. Their acceptance evidence is superseded where noted: 5.1.1's acceptance is superseded by 5.1.2, and the earlier waves are revalidated by 0.1.1.

### Wave 5 -- Review expansion (from Wave 4, decisions D9-D16)

Each task is one wave, serial (D4). Each behavior-changing task carries its own tests (D13). Each reference is independent R code, not the code under test.

### Task 5.1.2 -- Per-grid-latitude search sizing; independent brute-force KDE tests

- **Repo:** geodensity
- **Files in scope.** Must edit: `src/rust/src/lib.rs`, `inst/tinytest/test_geodensity.R`. Can create: `planning/tasks/1.5.2.todo.md`, a `## 5.1.2` report in `planning/STATE_1.md`.
- **Depends on:** 0.1.1, 5.1.1.
- **Spec.**
  1. Remove the dependence of the search extent on the mean input latitude. Derive the search extent per grid point: longitude half-width in degrees = `(3 * bw) / (111.32 * |cos(lat_grid)|)`, with the floor on `cos` kept, and latitude half-width = `(3 * bw) / 111.32`. For each grid point, compute its cell-offset range from these values. Keep the index cell size derived as now, but ensure it covers the largest needed half-width so that offsets stay bounded. Apply to both `geodesic_kde_rust` (bandwidth `bw`) and `geodesic_kde_adaptive_rust` (pilot bandwidth for the search, and each per-cell bandwidth for the cutoff).
  2. Keep the antimeridian handling: data with `|x| > 90` is inserted under the wrapped key. Verify, by the new tests, that this covers grid points near ±180.
  3. Keep the kernel exponent and the `dist_km < 3 * bw` cutoff unchanged.
  4. Add independent tests to `inst/tinytest/test_geodensity.R`. The reference is an R brute-force loop over all points, using haversine with radius 6371.0088 km and no index. Reference for the fixed path: `sum(exp(-0.5 * (d/bw)^2))` over points with `d < 3*bw`, unnormalized (normalization is 5.1.5). Reference for the adaptive path: brute-force pilot density at pilot bandwidth, then the scale formula `min + (pilot - min) / (1 + sqrt(d / d_max))` per cell, then the brute-force sum with the per-cell cutoff `3 * scale`. Cases:
     - heterogeneous latitudes, roughly -60 to 75;
     - a dateline-crossing set, with points and grid cells on both sides of ±180 at high latitude;
     - contributors placed at 0.9 and 1.1 times the cutoff distance, so the test sees both inside and outside points;
     - grid cells on and near index-cell boundaries.
     Compare at relative tolerance `1e-10`. Summation order differs, so exact equality is not required.
- **Anchors.** Grep `search_radius_deg`, `search_radius_lon_deg`, `search_radius_cells`, `index_cell_size`, `central_lat` in `src/rust/src/lib.rs`. Grep `expect_` in the test file to place new tests at the end, before the summary block.
- **Do not touch.** Normalization (5.1.5). The LOOCV function. R roxygen (5.1.6).
- **Acceptance.** `make test` (the gate, D12) exits 0. The new brute-force tests pass. Demonstrate they fail on the pre-5.1.1 commit: export `c220499` into the scratchpad as in 0.1.1 and run the new test file against it; the high-latitude cases must fail there. Record the result. Any low-latitude difference from the brute-force reference beyond `1e-10` must be explained in the report by indexing or summation order, or the task stops.
- **Escalation.** If a brute-force comparison fails at any latitude beyond `1e-10`, stop and report the case, the expected value, and the observed value.

### Task 5.1.3 -- Independent adaptive tests (test-only)

- **Repo:** geodensity
- **Files in scope.** Must edit: `inst/tinytest/test_geodensity.R`. Can create: `planning/tasks/1.5.3.todo.md`, a `## 5.1.3` report in `planning/STATE_1.md`.
- **Depends on:** 5.1.2.
- **Spec.** Test-only. No source changes. If any test fails, the code is wrong; stop and report.
  1. Scaling formula: for a seeded point set and template, compute pilot density by brute force, compute `d_max` as the maximum pilot value over the template, and check that the per-cell bandwidth from the implementation matches `min + (pilot - min)/(1 + sqrt(d/d_max))`. Expose per-cell bandwidth by comparing `kde_adaptive` against the brute-force adaptive reference from 5.1.2, which includes the scale step; this checks the formula through its effect on output.
  2. Zero pilot density: a template far from all points (for example lon -20 to -10 when points are near -100). Pilot density is 0 everywhere, `d_max` is 0. Expect output to be exactly 0 and no `NaN` or `Inf`.
  3. Template dependence: the same points on two templates with different extents. A cell shared by both templates has a different `d_max`, so its output differs. Assert that the value differs, and document in the test why (`d_max` is the template max).
  4. Default vs explicit minimum: `kde_adaptive(..., min_bandwidth = NULL)` equals `kde_adaptive(..., min_bandwidth = 0.1 * pilot_bandwidth)` exactly (`expect_identical`).
- **Anchors.** Test file, after the 5.1.2 block.
- **Do not touch.** Any source file.
- **Acceptance.** `make test` exits 0. Each new test passes on the current code. The report says what each test checks and how it fails if the formula, the zero-density path, or the template handling breaks.

### Task 5.1.4 -- Scalar validation; S7 and LOOCV tests

- **Repo:** geodensity
- **Files in scope.** Must edit: `R/geodensity.R`, `inst/tinytest/test_geodensity.R`. Can create: `planning/tasks/1.5.4.todo.md`, a `## 5.1.4` report in `planning/STATE_1.md`.
- **Depends on:** 5.1.3.
- **Spec.**
  1. S10: in `bandwidth_optimize`, add `length(bandwidth_min) == 1` and `length(bandwidth_max) == 1` to the existing scalar checks, with an error message naming the argument.
  2. Tests for the scalar checks: a length-2 `bandwidth_min` errors, and a length-2 `bandwidth_max` errors. Both assertions are required.
  3. S7 tests: `print.bandwidth_cv` output contains the header and the "Optimal bandwidth" line (`capture.output`); `bandwidth_max <= bandwidth_min` errors; `n_bandwidths = 1.5` errors; `verbose = TRUE` output contains "OPTIMAL".
  4. LOOCV floor test: for two points far apart with `bandwidth_min = 1` and a single bandwidth, every density is 0 and floored to `1e-10`, so `bandwidth_loocv_evaluate` returns `log(1e-10)` for the bandwidth. Assert `expect_equal(..., log(1e-10), tolerance = 1e-12)`.
  5. LOOCV score-scale test: compute the LOOCV log-likelihood for a small seeded set at one bandwidth by brute force in R, using `kernel_norm = 1/(2*pi*bw^2)`, the `1e-10` floor, and radius 6371.0088 km. Assert agreement at relative tolerance `1e-10`. This pins the absolute scale that S8 documents.
- **Anchors.** `bandwidth_optimize` validation block; `print.bandwidth_cv`; `bandwidth_loocv_evaluate` (Rust, read only).
- **Do not touch.** LOOCV code. The Test 31 values. Roxygen (5.1.6).
- **Acceptance.** `make test` exits 0. Each new test passes. The scalar check is covered by a passing test for each argument.

### Task 5.1.5 -- Normalization to probability density (Q1 = B)

- **Repo:** geodensity
- **Files in scope.** Must edit: `src/rust/src/lib.rs`, `inst/tinytest/test_geodensity.R`. Can create: `planning/tasks/1.5.5.todo.md`, a `## 5.1.5` report in `planning/STATE_1.md`.
- **Depends on:** 5.1.4.
- **Spec.** Divide each output by `2*pi*bw^2*n`, where `bw` is the fixed bandwidth or the per-cell bandwidth, and `n` is the number of input points. The division applies after accumulation, not inside the loop. Do not change the kernel exponent or the cutoff. The integral of the fixed-bandwidth output over the plane is approximately 1; record the measured integral on a dense grid in the report, as a sanity check, not as a test.
  Tests, against the brute-force reference from 5.1.2 divided by the same factor. Tolerance `1e-10`. Both fixed and adaptive paths. LOOCV is not changed by this task.
- **Anchors.** `let mut sum = 0.0` in each KDE function. `kernel_norm` in `bandwidth_loocv_evaluate` (read only).
- **Do not touch.** Search sizing (5.1.2). LOOCV. Roxygen (5.1.6).
- **Acceptance.** `make test` exits 0. Brute-force normalized tests pass. The report states the chosen quantity and the factor used.
- **Escalation.** If the brute-force normalized comparison fails at any latitude beyond `1e-10`, stop and report.

### Task 5.1.6 -- R roxygen

- **Repo:** geodensity
- **Files in scope.** Must edit: `R/geodensity.R`. Can create: `planning/tasks/1.5.6.todo.md`, a `## 5.1.6` report in `planning/STATE_1.md`.
- **Depends on:** 5.1.5.
- **Spec.** Documentation only; no code change.
  1. S1 and F1: the `kde_adaptive` algorithm text states the formula in code: `bw_i = min + (pilot - min) / (1 + sqrt(d_i / d_max))`, where `d_i` is the pilot density at the cell and `d_max` is the maximum pilot density over the template. Remove the `pilot / sqrt(density)` description.
  2. S3 wording: state in `kde_geodesic` and `kde_adaptive` `@return` the quantity chosen under Q1, and the factor. Option B must say it divides by `n`. Option A must say it is intensity, not probability density.
  3. S4: the adaptive per-cell bandwidth depends on the template grid, because the pilot density is evaluated on it.
  4. S5: document the LOOCV density floor `1e-10`.
  5. S6: document the n x n distance matrix memory cost.
  6. S8: document that LOOCV log-likelihood is on an absolute scale. Name the normalization it uses. State that it is not the same as the KDE output's quantity when they differ.
  7. F2: remove the claim that LOOCV is parallelized via Rayon. The Rust function is serial.
  8. F9: wrap the two lines over 100 characters.
- **Anchors.** `kde_adaptive` and `kde_geodesic` roxygen; `bandwidth_optimize` details; `awk 'length > 100' R/geodensity.R`.
- **Do not touch.** Function bodies. `man/*.Rd` (regenerated in 9.1.1). `NAMESPACE`.
- **Acceptance.** `make test` exits 0. `awk 'length > 100' R/geodensity.R` prints nothing. `grep -n -i rayon R/geodensity.R` prints nothing.

### Task 5.1.7 -- Rust comments and whitespace

- **Repo:** geodensity
- **Files in scope.** Must edit: `src/rust/src/lib.rs`. Can create: `planning/tasks/1.5.7.todo.md`, a `## 5.1.7` report in `planning/STATE_1.md`.
- **Depends on:** 5.1.6.
- **Spec.** Comment and whitespace changes only. No behavior change.
  1. F4: the comment near line 37 "Vincenty approximation" becomes "linear approximation of degree-to-km conversion".
  2. F5: the comment on the kernel normalization ("Silverman's normalization") becomes "2D Gaussian normalization (planar approximation)".
  3. F12: in the `///` blocks for the three `#[extendr]` functions, drop the `@param`, `@return`, and `@keywords internal` tags; keep a one-line description.
  4. F8: strip trailing whitespace on lines the branch added. Confirm the list with `grep -n " $" src/rust/src/lib.rs`.
  5. No guard is added (D15). F7 is dropped.
- **Anchors.** Grep `Vincenty`, `Silverman`, `@keywords internal`, `" $"`.
- **Do not touch.** Any code.
- **Acceptance.** `make test` exits 0. Output unchanged: `baseline.R` output in the scratchpad matches the output recorded before this task, byte for byte. `grep -n " $" src/rust/src/lib.rs` shows no trailing whitespace on branch-added lines.

### Task 5.1.8 -- Build hygiene, verified on the built tarball

- **Repo:** geodensity
- **Files in scope.** Must edit: `.Rbuildignore`, `DESCRIPTION`. Can create: `planning/tasks/1.5.8.todo.md`, a `## 5.1.8` report in `planning/STATE_1.md`.
- **Depends on:** 5.1.7.
- **Spec.**
  1. F3: add `^planning$` to `.Rbuildignore`.
  2. F10: remove the duplicate `.github/` line; keep `^\.github$`.
  3. F8 (DESCRIPTION): strip trailing whitespace on branch-changed lines 6, 8, 9 only. Lines 21, 23, 25 are pre-existing and out of scope.
  4. Verify the built archive, not only the ignore file. Run `R CMD build --no-build-vignettes <repo>` from the scratchpad directory, so the tarball lands there. Then `tar -tzf` the tarball and confirm there is no `planning/` entry and no `.github/` entry. Record the tarball path and its listing summary (count of `planning/` entries must be 0).
- **Anchors.** `.Rbuildignore` lines 11-12; `DESCRIPTION` lines 6, 8, 9.
- **Do not touch.** `DESCRIPTION` line 14 and lines 21, 23, 25 (user proposals). Any other field.
- **Acceptance.** `make test` exits 0. `grep -c "^\^planning\$" .Rbuildignore` prints 1. The tarball contains no `planning/` entries. `grep -n " $" DESCRIPTION` shows only lines 21, 23, 25.
- **Escalation.** If `R CMD build` fails for reasons unrelated to this task, stop and report the error. Do not work around it by editing `DESCRIPTION` or `.Rbuildignore` further.

### Task 5.1.9 -- README.Rmd adaptive description (S11)

- **Repo:** geodensity
- **Files in scope.** Must edit: `README.Rmd`. Can create: `planning/tasks/1.5.9.todo.md`, a `## 5.1.9` report in `planning/STATE_1.md`.
- **Depends on:** 5.1.8.
- **Spec.** Fix the adaptive algorithm description in `README.Rmd` to match the formula in 5.1.6. Do not regenerate `README.md` here; `make readme` runs in 9.1.1.
- **Anchors.** Grep `adaptive` and `sqrt` in `README.Rmd`.
- **Do not touch.** `README.md`, `README.html`.
- **Acceptance.** `make test` exits 0. `git diff --stat -- . ':!planning'` lists only `README.Rmd` for this task.

### Task 5.1.10 -- Re-record fingerprint baseline (D11, D14)

- **Repo:** geodensity
- **Files in scope.** Must edit: `planning/STATE_1.md` (new baseline section only). Can create: `planning/tasks/1.5.10.todo.md`, a `## 5.1.10` report.
- **Depends on:** 5.1.9.
- **Spec.** Only after all correctness checks in 5.1.2-5.1.9 pass. Run the scratch `baseline.R` (in the scratchpad) on the current tree, and record the new `kde_geodesic` and `kde_adaptive` fingerprints and the LOOCV values. Mark the pre-wave-1 fingerprints superseded and keep them for reference. Confirm the LOOCV values still match Test 31's pinned values.
- **Anchors.** Scratch script: `<scratchpad>/baseline.R`.
- **Do not touch.** Any repo source or test file.
- **Acceptance.** `make test` exits 0. STATE_1.md has the new baseline, with the commit hash it was taken on.

### Task 6.1.1 -- Remove pre-existing empty-input guard in `geodesic_kde_rust` (D15)

- **Repo:** geodensity
- **Files in scope.** Must edit: `src/rust/src/lib.rs`. Can create: `planning/tasks/1.6.1.todo.md`, a `## 6.1.1` report in `planning/STATE_1.md`.
- **Depends on:** 5.1.10.
- **Spec.** In `geodesic_kde_rust` only, replace the `if !y_coords.is_empty() { ... } else { 0.0 }` block for `central_lat` with the single expression used in 2.1.1. The R layer enforces the supported-input contract (D15).
- **Anchors.** Grep `fn geodesic_kde_rust`, then `let central_lat`.
- **Do not touch.** The adaptive copy (2.1.1). The 5.1.10 baseline.
- **Acceptance.** `make test` exits 0. The `kde_geodesic` fingerprints match the 5.1.10 baseline exactly. Test 10 (empty points error) still passes.

### Task 7.1.1 -- Extract shared spatial-index helper

- **Repo:** geodensity
- **Files in scope.** Must edit: `src/rust/src/lib.rs`. Can create: `planning/tasks/1.7.1.todo.md`, a `## 7.1.1` report.
- **Depends on:** 6.1.1.
- **Spec.** Both KDE functions build the same spatial index. Extract that into one private helper that returns the index and the cell parameters, including the per-grid-point offset logic from 5.1.2. Both call sites keep their existing bandwidth arguments. Evaluation order and float arithmetic must not change.
- **Anchors.** Grep `grid_index`, `index_cell_size`, `search_radius_cells`.
- **Do not touch.** The kernel accumulation loops.
- **Acceptance.** `make test` exits 0. Fingerprints match the 5.1.10 baseline exactly.
- **Escalation.** If exact fingerprints diverge, stop and report the first differing cell. Do not loosen the check.

### Task 8.1.1 -- Set `class(result)` to `"bandwidth_cv"` only

- **Repo:** geodensity
- **Files in scope.** Must edit: `R/geodensity.R`, `inst/tinytest/test_geodensity.R`. Can create: `planning/tasks/1.8.1.todo.md`, a `## 8.1.1` report.
- **Depends on:** 7.1.1.
- **Spec.** In `bandwidth_optimize`, change `class(result) <- c("bandwidth_cv", "list")` to `class(result) <- "bandwidth_cv"`. Add a test asserting `class(bw) == "bandwidth_cv"` and `is.list(bw)` is still `TRUE`. Update the roxygen `@return` to say the object is a list with class `bandwidth_cv`.
- **Anchors.** Grep `c("bandwidth_cv", "list")`.
- **Do not touch.** `print.bandwidth_cv` logic.
- **Acceptance.** `make test` exits 0. The class assertions pass.
- **Note.** A user-visible change. Recorded in NEWS.md in 9.1.1.

### Task 9.1.1 -- 0.2.0 release prep (no tag, no push)

- **Repo:** geodensity
- **Files in scope.** Must edit: `DESCRIPTION`. Can create: `NEWS.md`, `planning/tasks/1.9.1.todo.md`, a `## 9.1.1` report. Regenerated: `README.md`, `README.html`, `man/`, `NAMESPACE` (via `make docs` and `make readme`).
- **Depends on:** 8.1.1.
- **Spec.**
  1. Set `Version: 0.2.0` in `DESCRIPTION`.
  2. Create `NEWS.md` for 0.2.0. Cover, at minimum:
     - adaptive KDE (`kde_adaptive`) and LOOCV bandwidth selection (`bandwidth_optimize`, `print.bandwidth_cv`);
     - the search-box correction: neighbors at high latitude were dropped, and the adaptive path changes through the pilot pass;
     - the normalization, as decided under D10 (quantity and factor), and that existing values change by that factor;
     - the removal of the false LOOCV parallelism claim;
     - the `bandwidth_cv` class change;
     - the Haversine consolidation on `geo`, with the small LOOCV numeric shift.
  3. Run `make docs` and `make readme`.
  4. Run `Rscript -e "devtools::check()"` directly. Do not run `make check`, because its `vendor` target rewrites `src/rust/vendor/` and needs Cargo.
  5. Run the tarball check from 5.1.8 again on the final tree.
- **Anchors.** `DESCRIPTION` line 2; `Makefile` `docs` and `readme` targets.
- **Do not touch.** No tag, branch, or remote. No `git push`, no `git tag`.
- **Acceptance.** `make test` exits 0. `devtools::check()` finishes with 0 errors and 0 warnings. Any NOTEs are recorded in STATE_1.md. The tarball contains no `planning/` entries. `DESCRIPTION` shows `0.2.0`.
- **Reference.** `f86ee9d chore: version bump` for the convention.

---

## Resolved questions

- **Q1 (resolved 2026-11-08): probability density, option B.** Divide by `2*pi*bw^2*n`. LOOCV keeps its intensity normalization; the docs state the difference (D10).
