# geodensity 0.2.0

## New features

* `kde_adaptive()`: adaptive-bandwidth geodesic KDE with `method = c("balloon", "sample_point")` and `scaling = c("ratio", "linear_sqrt")` (defaults: `"balloon"` and `"ratio"`). Balloon estimates are locally normalized per cell without guaranteed unit mass; sample-point estimates normalize each input point's kernel and integrate to approximately 1. For positive `d_max`, ratio scaling spans `[(min + pilot) / 2, pilot]`, while linear-sqrt scaling spans `[min, pilot]`.
* `bandwidth_optimize()`: leave-one-out cross-validation (LOOCV) bandwidth selection, with `print.bandwidth_cv`.

## Bug fixes

* Search-box correction: neighbors were dropped at other latitudes. Fixed-bandwidth and adaptive values change. The adaptive path also changes through the pilot pass.
* The LOOCV parallelism claim was false. The LOOCV loop is serial, and the documentation no longer says otherwise.
* Unreachable empty-input guards in internal Rust functions were removed. No user-visible behavior changed.

## Changes

* KDE output is now probability density per km². It divides by `2*pi*bw^2*n`, so existing values change by that factor. For `kde_adaptive()`, balloon uses the per-cell bandwidth in this factor; sample-point uses each input point's bandwidth to normalize its kernel.
* LOOCV keeps the intensity normalization `1/(2*pi*bw^2)`, omitting `1/n`. This alone would shift identical unfloored log-densities by `log(n)`, but LOOCV also excludes each held-out point, does not apply the `3*bw` KDE cutoff, and floors densities at `1e-10`; its scores therefore do not differ from KDE output by an unconditional constant `log(n)`. The accumulator reduces memory use to `O(n * B)` for `B` bandwidth candidates. Only the ranking across bandwidths is used.
* `bandwidth_cv` objects have class `bandwidth_cv` only, not `c("bandwidth_cv", "list")`. They are still lists.
* `bandwidth_min` and `bandwidth_max` are validated as scalars.
* Haversine distance is consolidated on `geo`. LOOCV scores shift by at most about 1e-6 relative.

## Known limitations

* Grid points that enclose a pole (search half-width at or above 90 degrees) scan all data points. This is O(n) per grid point and slow at high latitude with large bandwidths.
