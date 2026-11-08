# REVIEW_1 Spec-axis review (read-only)

Range: `b7f07b8..HEAD` (HEAD `c220499`, 10 commits). Reference: `planning/EXECUTION_PLAN_1.md` Goal & Scope (line 5) and decision log D1-D7.

Routing (report only, not acted on): every finding below is in branch-changed code (`kde_adaptive`, `bandwidth_optimize`, `print.bandwidth_cv`, `kde_geodesic` changed in `6c73901`, or the branch-added README/tests), so all route to Wave 5 per D5 and the coordinator's ruling on `kde_geodesic`.

## Summary

| ID | Severity | Verdict | Finding |
|---|---|---|---|
| S1 | High | Confirmed | kde_adaptive documents a bandwidth formula the code does not implement |
| S2 | High | Confirmed | Spatial search box truncates the 3-sigma kernel at |lat| > ~48 deg (kde_geodesic and kde_adaptive) |
| S3 | Medium | Conditional | kde_* outputs are unnormalized kernel sums, but roxygen calls them density |
| S4 | Medium | Confirmed | kde_adaptive per-cell bandwidth depends on the template grid (undocumented) |
| S5 | Medium | Confirmed | LOOCV density floor at 1e-10 is undocumented |
| S6 | Medium | Confirmed | bandwidth_optimize allocates an n x n distance matrix; memory not documented |
| S7 | Medium | Confirmed | Test gaps: print.bandwidth_cv untested; bandwidth_optimize validation and verbose output untested; adaptive formula and high-latitude coverage unpinned |
| S8 | Low | Conditional | LOOCV log-likelihood uses per-kernel planar normalization with no (n-1) divisor; absolute scale undocumented (ranking unaffected) |
| S9 | Low | Confirmed | `class(result)` carries an extra `"list"` class not described by @return |
| S10 | Low | Conditional | bandwidth_min / bandwidth_max checks do not enforce a scalar |
| S11 | Low | Confirmed | README.Rmd describes the adaptive algorithm as two-pass and "inversely" scaled; code is three passes with a different formula |

Count: High 2 (both Confirmed), Medium 5 (4 Confirmed, 1 Conditional), Low 4 (2 Confirmed, 2 Conditional). Total 11.

No-finding checks (verified, recorded so they are not re-reviewed):
- `kde_geodesic` `set.values` change (`R/geodensity.R:138`, commit `6c73901`): returns a copy of the template via `terra::rast(r)` with values set; matches the `@param r` promise of same dimensions, resolution, and CRS. No gap.
- `@param` and `@return` for `kde_geodesic`, `kde_adaptive`, `bandwidth_optimize`, `print.bandwidth_cv`: every documented argument exists in the signature with matching defaults (`min_bandwidth` default 10% of pilot, `n_bandwidths` 10, `verbose` TRUE, `bandwidth_min` 1, `bandwidth_max` 100). The `bandwidth_optimize` return fields (`bandwidth_opt`, `log_likelihood`, `bandwidths`, `n_points`) match the code at `R/geodensity.R:472-477`.
- `NAMESPACE`: exports `kde_adaptive`, `bandwidth_optimize`, `kde_geodesic`; `S3method(print,bandwidth_cv)` present. Matches `@export` tags.
- `man/print.bandwidth_cv.Rd`, `man/bandwidth_optimize.Rd` (value, arguments, algorithm text), and `man/kde_adaptive.Rd` (usage, arguments, formula text) agree with the roxygen blocks. `man/kde_geodesic.Rd` is unchanged in the range.

## Findings

### S1 -- High -- Confirmed -- kde_adaptive documents a formula the code does not implement
- **Anchors:** `R/geodensity.R:151-152` (roxygen: "Scale bandwidth per grid cell as: `pilot_bandwidth / sqrt(pilot_density)`, clamped to `[min_bandwidth, pilot_bandwidth]`"); `man/kde_adaptive.Rd:41-42` (same text); `src/rust/src/lib.rs:154-155` (Rust doc comment, same formula); `src/rust/src/lib.rs:185-199` (code).
- **Observed gap:** the code computes `scale = 1 / (1 + (d / d_ref)^0.5)` with `d_ref = max(pilot_density)` (`lib.rs:189`), then `bw = min + (pilot - min) * scale` (`lib.rs:198-199`). The documented formula `pilot / sqrt(d)` is not used, and no `sqrt(pilot_density)` appears in the code. The code's `scale` is a bounded interpolation, so it stays in `[min, pilot]` without a clamp.
- **Proposed fix:** rewrite the roxygen and `man/kde_adaptive.Rd` algorithm steps to the implemented formula, normalized by the grid max. Update the Rust doc comment at `lib.rs:154-155` and the comment at `lib.rs:185` to match. Do not change the numerics in this fix; the formula decision is for the user if the documented version was the intent.
- **Evidence:** code at `lib.rs:186-199` read directly; no `sqrt` of density appears in either function.

### S2 -- High -- Confirmed -- Spatial search box truncates the 3-sigma kernel at high latitude
- **Anchors:** `src/rust/src/lib.rs:65-66` (`search_radius_deg = search_radius_lon_deg.min(search_radius_lat_deg)`, comment "Use smaller radius for safety (guarantees we find neighbors)"); `lib.rs:223` (same in `geodesic_kde_adaptive_rust`, pilot-based). Roxygen promises: `R/geodensity.R:20` ("effective range ... approximately 3 * bandwidth"), `R/geodensity.R:31` ("automatically accounts for latitude-dependent distortion"); `man/kde_geodesic.Rd:21, 40`.
- **Observed gap:** one degree of latitude is about 111.32 km everywhere, but one degree of longitude is `111.32 * cos(lat)` km. The lon radius in degrees is therefore always the larger of the two, so `min()` selects the lat radius. The index cell is `1.5 * lat_deg`, and `search_radius_cells = ceil(lat_deg / cell) = 1`, so the search covers only one cell of reach. The minimum east/west reach is one cell width, which is `4.5 * bw * cos(lat)` km. The kernel cutoff is `3 * bw` km. The reach falls below the cutoff when `cos(lat) < 2/3`, i.e. `|lat| > ~48.2 deg`. The bug is independent of bandwidth.
- **Worked example (bw = 50 km, lat = 60):** lon_deg 2.69, lat_deg 1.35, cell 2.02 deg. Minimum east reach 112.5 km; required 150 km. Neighbors 112-150 km east or west of a query at a cell's western edge are dropped, though they are inside the 3-sigma cutoff at `lib.rs:129` (`dist_km < bw*3`). At lat 40, the same calculation gives 172 km and is safe.
- **Scope of impact:** `kde_geodesic` (`lib.rs:66`) and `kde_adaptive` (`lib.rs:223`, pilot-sized index; affected where the per-cell scaled bandwidth exceeds `1.5 * pilot * cos(lat)`). The `bandwidth_optimize` LOOCV path (`lib.rs:316-362`) is all-pairs and not affected.
- **Proposed fix:** use `max` (or compute the lon radius directly from `3 * bw / (111.32 * cos(lat))`, with a floor near the poles). Replace the comment at `lib.rs:65`. Add a tinytest that compares a high-latitude `kde_geodesic` value against a brute-force sum over all points.
- **Evidence:** `lib.rs:60-66` (at `b7f07b8` the same lines are 60-61, so the code predates the branch). Arithmetic above, computed with Python. Routed in-branch because `kde_geodesic` was changed in `6c73901` (coordinator ruling 2).

### S3 -- Medium -- Conditional -- kde_* outputs are unnormalized kernel sums
- **Anchors:** `src/rust/src/lib.rs:111-139` and `lib.rs:264-288` (sum of `exp(-0.5 (d/bw)^2)` with no `1/(2 pi bw^2)` factor). Roxygen: `R/geodensity.R:22-24` ("Values represent the density of input points"), `R/geodensity.R:169-170` (kde_adaptive). Contrast: `lib.rs:337` (`kernel_norm = 1/(2 pi bw^2)` in LOOCV).
- **Observed gap:** the surface values are not probability densities. They scale with `2 pi bw^2` and so change magnitude with bandwidth, while `bandwidth_optimize` uses normalized kernels. The package is internally inconsistent: the same word "density" refers to different scales.
- **Proposed fix:** either document the output as an unnormalized kernel sum, or divide by `2 pi bw^2 * n` (a value-changing behavior change, which needs a user decision). Recommend documenting, since the ranking is unaffected.
- **Evidence:** the kernel loops at `lib.rs:121-137` and `lib.rs:275-283` have no normalization term; the LOOCV path does at `lib.rs:337`. Verdict is Conditional because whether the intent was a normalized density is a user decision.

### S4 -- Medium -- Confirmed -- kde_adaptive per-cell bandwidth depends on the template grid
- **Anchors:** `src/rust/src/lib.rs:189` (`reference_density = max over the output grid`), `lib.rs:190-199` (scale per cell). Roxygen (`R/geodensity.R:146-153`, `169-170`) does not mention it.
- **Observed gap:** the reference density is the maximum over the template grid, not over the points. Two templates over the same points (different extent or resolution) give different bandwidths at the same location. The result is not a function of the point data alone, which the documented "bandwidth varies inversely with local point density" implies.
- **Proposed fix:** document the dependence in roxygen and `man/kde_adaptive.Rd`. Alternatively, take the reference from the data (max pilot density at the input points). The second is a numeric change and needs a user decision.
- **Evidence:** `lib.rs:189` fold over `pilot_density`, which is evaluated on `grid_x`/`grid_y` (`lib.rs:175-180`).

### S5 -- Medium -- Confirmed -- LOOCV density floor is undocumented
- **Anchors:** `src/rust/src/lib.rs:333` (`epsilon = 1e-10`), `lib.rs:354` (`density.max(epsilon).ln()`). Roxygen for `bandwidth_optimize` (`R/geodensity.R:339-344` return; algorithm at `R/geodensity.R:349-353`) does not mention the floor.
- **Observed gap:** a held-out point with zero kernel mass from all others (isolated at small bandwidth) contributes `ln(1e-10) = -23.03` to the average. This can drive the selected bandwidth. Users reading the algorithm would not expect a hard floor.
- **Proposed fix:** document the floor and its effect in the Algorithm section and `man/bandwidth_optimize.Rd`.
- **Evidence:** `lib.rs:333` and `lib.rs:354`; the roxygen algorithm text has no reference to a floor.

### S6 -- Medium -- Confirmed -- bandwidth_optimize allocates an n x n matrix; memory is undocumented
- **Anchors:** `src/rust/src/lib.rs:316` (`vec![vec![0.0; n_points]; n_points]`), `lib.rs:318-327` (fills all pairs). Roxygen: `R/geodensity.R:357-358` ("For datasets with >5000 points, consider using fewer bandwidth candidates") gives time advice only.
- **Observed gap:** memory is `8 * n^2` bytes. n = 5000 needs about 200 MB; n = 20000 needs about 3.2 GB, with no warning. The time advice in the docs does not mention memory, so the failure mode is silent until allocation.
- **Proposed fix:** add a memory note (`8 n^2` bytes) to the Algorithm section, and optionally a size check in the R wrapper. Keep the check out of scope unless the user wants it.
- **Evidence:** `lib.rs:316` allocation is unconditional; `R/geodensity.R:357-358` is the only size guidance.

### S7 -- Medium -- Confirmed -- Test gaps against documented behavior
- **Anchors:** `inst/tinytest/test_geodensity.R:421-438` (Test 31, the only `bandwidth_optimize` test, with `verbose = FALSE`). Grep of the test file finds no `print`, `bandwidth_cv`, or `verbose = TRUE` call.
- **Observed gap:**
  - `print.bandwidth_cv` (`R/geodensity.R:488-500`) has no test.
  - `bandwidth_optimize` validation errors (`R/geodensity.R:435-446`: `bandwidth_min`, `bandwidth_max`, `n_bandwidths`) have no `expect_error` test. Only `kde_adaptive` validation is covered (Tests 28, 30).
  - The `verbose = TRUE` path (`R/geodensity.R:451-466`) has no test.
  - The adaptive scaling formula (S1), reference-density dependence (S4), and high-latitude coverage (S2) are not pinned by any test.
- **Proposed fix:** add tests in Wave 5: a `print.bandwidth_cv` snapshot-style check, validation `expect_error` cases, one `verbose = TRUE` `expect_silent`-style check, a latitude-60 `kde_geodesic` brute-force comparison (S2), and a fixed-template adaptive value check (S1/S4).
- **Evidence:** grep of `inst/tinytest/test_geodensity.R` for `print|bandwidth_cv|verbose|n_bandwidths|bandwidth_min` returns no tests for those branch features except Test 31.

### S8 -- Low -- Conditional -- LOOCV log-likelihood absolute scale is undocumented
- **Anchors:** `src/rust/src/lib.rs:337` (`kernel_norm = 1/(2 pi bw^2)`), `lib.rs:340-349` (sum over the n-1 other points, no `1/(n-1)`), `lib.rs:358` (divide by n). Roxygen: `R/geodensity.R:339-344`.
- **Observed gap:** the reported `log_likelihood` is the mean over test points of `ln(sum of planar kernels)`. This equals `ln(f) + ln(n-1)` per point, so the scale differs from a normalized mixture log-likelihood by a constant. Ranking across bandwidths is unaffected. The docs call it "log-likelihood" without this qualifier.
- **Proposed fix:** document the scale in the return description. Conditional because it only matters if users compare absolute values across datasets.
- **Evidence:** the code comment at `lib.rs:336` says "Silverman's normalization ... for geographic space", which is planar, not spherical.

### S9 -- Low -- Confirmed -- extra `"list"` class on bandwidth_cv
- **Anchors:** `R/geodensity.R:478` (`class(result) <- c("bandwidth_cv", "list")`). Roxygen `R/geodensity.R:339` says "A list with class `bandwidth_cv`".
- **Observed gap:** the return carries an undocumented second class `"list"`. The plan already defers its removal (`EXECUTION_PLAN_1.md` "class(result) 'list' removal").
- **Proposed fix:** set `class(result) <- "bandwidth_cv"` and add a test. Coordinate with the already-planned deferral.
- **Evidence:** line 478 directly.

### S10 -- Low -- Conditional -- bandwidth_min / bandwidth_max not scalar-checked
- **Anchors:** `R/geodensity.R:435` and `R/geodensity.R:438`. Roxygen: "numeric scalar" (`R/geodensity.R:329-331`).
- **Observed gap:** `!is.numeric(x) || x <= 0` with a length > 1 vector errors inside `||` (R >= 4.3), with a message other than the documented one. `kde_adaptive` checks length (`R/geodensity.R:245`, pilot check), so the two functions are inconsistent. Conditional: the stated contract is violated only for vector input.
- **Proposed fix:** add `length(x) != 1` to both checks, matching `kde_adaptive`.
- **Evidence:** lines 435 and 438 have no length check.

### S11 -- Low -- Confirmed -- README.Rmd misdescribes the adaptive algorithm
- **Anchors:** `README.Rmd:124` ("scales the bandwidth inversely with local density"), `README.Rmd:157` ("two-pass approach ... scale bandwidth at each grid cell inversely with the pilot density").
- **Observed gap:** the code has three passes (`lib.rs:153-155`, roxygen `R/geodensity.R:149-153`), and the scaling is `1/(1 + sqrt(d/d_max))`, not a pure inverse of density (S1). The README also does not mention the grid-dependent reference (S4).
- **Proposed fix:** correct the README.Rmd step count and wording after S1 is resolved, and re-render README.md in the release wave (not in this task).
- **Evidence:** `README.Rmd:157` vs `lib.rs:153-199`.

## Verdict legend
- **Confirmed:** observed directly in code or docs at the cited lines, with arithmetic or grep evidence.
- **Conditional:** the gap holds only if the stated intent is as read; the user must decide (S3, S4 fix choice, S8, S10).
