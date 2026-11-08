# STATE 1 -- orchestration 1 (geodensity, branch adaptive-GKDE-1)

Plan: `planning/EXECUTION_PLAN_1.md`. Template: `planning/PROMPT_TEMPLATE_1.md`.
Resume from this file. The orchestrator is disposable.

## Baseline (pre-wave-1, to be recorded by orchestrator before any change)

- [ ] `git status --porcelain` clean on `adaptive-GKDE-1` at `488ce24`
- [ ] `make test`: pass/fail counts = ____
- [ ] LOOCV baseline (`set.seed(42)`, roxygen example data, `bandwidth_optimize(pts, bandwidth_min = 1, bandwidth_max = 50, n_bandwidths = 8)`): `bandwidth_opt` = ____; `log_likelihood` (10 sig. digits) = ____
- [ ] `kde_geodesic` fingerprint on fixed template and seed-42 points: sum = ____; checksum = ____
- [ ] `kde_adaptive` fingerprint on the same inputs: sum = ____; checksum = ____

## Wave board

| Wave | Task | Status |
| --- | --- | --- |
| 1 | 1.1.1 remove LOOCV empty guard | pending |
| 2 | 2.1.1 simplify adaptive central_lat | pending |
| 3 | 3.1.1 haversine to geo + LOOCV tolerance test | pending |
| 4 | 4.1.1 spec-axis review (read-only) | pending |
| 4 | 4.1.2 standards-axis review (read-only) | pending |
| 5 | 5.1.x review expansion | empty until Wave 4 findings |
| 6 | 6.1.1 remove pre-existing empty guard in geodesic_kde_rust | pending |
| 7 | 7.1.1 extract shared spatial-index helper | pending |
| 8 | 8.1.1 class(result) = "bandwidth_cv" | pending |
| 9 | 9.1.1 0.2.0 release prep (no tag, no push) | pending |

## Task reports

_Workers append here, under `## {{id}}`, at most 15 lines each._
