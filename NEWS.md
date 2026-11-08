# geodensity 0.2.0

## New features

* `kde_adaptive()`: adaptive-bandwidth geodesic KDE. A pilot pass sets a per-cell bandwidth, bounded by `min_bandwidth` and `pilot_bandwidth`.
* `bandwidth_optimize()`: leave-one-out cross-validation (LOOCV) bandwidth selection, with `print.bandwidth_cv`.

## Bug fixes

* Search-box correction: neighbors were dropped at other latitudes. Fixed-bandwidth and adaptive values change. The adaptive path also changes through the pilot pass.
* The LOOCV parallelism claim was false. The LOOCV loop is serial, and the documentation no longer says otherwise.
* Unreachable empty-input guards in internal Rust functions were removed. No user-visible behavior changed.

## Changes

* KDE output is now probability density per km². It divides by `2*pi*bw^2*n`, so existing values change by that factor. For `kde_adaptive()`, the per-cell bandwidth is used in the factor.
* LOOCV keeps the intensity normalization `1/(2*pi*bw^2)`, with no n. Its log-likelihood therefore differs from KDE output by a constant `log(n)`. Only the ranking across bandwidths is used.
* `bandwidth_cv` objects have class `bandwidth_cv` only, not `c("bandwidth_cv", "list")`. They are still lists.
* `bandwidth_min` and `bandwidth_max` are validated as scalars.
* Haversine distance is consolidated on `geo`. LOOCV scores shift by at most about 1e-6 relative.

## Known limitations

* Grid points that enclose a pole (search half-width at or above 90 degrees) scan all data points. This is O(n) per grid point and slow at high latitude with large bandwidths.
