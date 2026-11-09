# Title: Urban incident-density workflow
# Description: Selects a bandwidth by cross-validation and compares fixed and adaptive KDE.
#
# Run from an installed geodensity package:
#   Rscript inst/examples/urban_incidents.R
#
# This reproducible example simulates incidents around a dense city center and
# sparse satellite communities, selects a fixed bandwidth by LOOCV, and compares
# that estimate with both adaptive KDE methods introduced in v0.2.0.

if (!requireNamespace("geodensity", quietly = TRUE)) {
  stop("Install geodensity before running this example.")
}
if (!requireNamespace("terra", quietly = TRUE)) {
  stop("Install terra before running this example.")
}

set.seed(2020)

# Simulated events: dense urban core, two smaller clusters, and scattered
# rural incidents. Coordinates are longitude/latitude around a fictional
# region in the western United States.
incidents <- rbind(
  data.frame(
    lon = rnorm(120, mean = -120.00, sd = 0.035),
    lat = rnorm(120, mean = 38.00, sd = 0.035)
  ),
  data.frame(
    lon = rnorm(35, mean = -120.35, sd = 0.045),
    lat = rnorm(35, mean = 38.12, sd = 0.045)
  ),
  data.frame(
    lon = rnorm(25, mean = -119.70, sd = 0.050),
    lat = rnorm(25, mean = 37.82, sd = 0.050)
  ),
  data.frame(
    lon = runif(30, -120.6, -119.5),
    lat = runif(30, 37.6, 38.3)
  )
)
points <- terra::vect(incidents, geom = c("lon", "lat"), crs = "EPSG:4326")

# Keep a modest grid so the whole workflow is practical on a laptop. The
# template includes a margin around the point extent to reduce edge effects.
template <- terra::rast(
  extent = c(-120.75, -119.35, 37.45, 38.45),
  resolution = 0.02,
  crs = "EPSG:4326"
)

# LOOCV is quadratic in point count; use a compact candidate set for this
# example. Bandwidths and the reported optimum are in kilometres.
bandwidth_cv <- geodensity::bandwidth_optimize(
  points,
  bandwidth_min = 1,
  bandwidth_max = 40,
  n_bandwidths = 8
)
print(bandwidth_cv)

# Use the selected bandwidth for a fixed-bandwidth baseline and as the pilot
# bandwidth for adaptive estimates.
fixed <- geodensity::kde_geodesic(
  points,
  template,
  bandwidth = bandwidth_cv$bandwidth_opt
)

# Balloon bandwidths vary by output cell. linear_sqrt spans the full
# min-to-pilot range when pilot density is positive.
adaptive_balloon <- geodensity::kde_adaptive(
  points,
  template,
  pilot_bandwidth = bandwidth_cv$bandwidth_opt,
  min_bandwidth = bandwidth_cv$bandwidth_opt * 0.2,
  method = "balloon",
  scaling = "linear_sqrt"
)

# Sample-point bandwidths vary by observed incident and are normalized per
# point, yielding an estimate whose surface integrates to approximately one.
adaptive_sample_point <- geodensity::kde_adaptive(
  points,
  template,
  pilot_bandwidth = bandwidth_cv$bandwidth_opt,
  min_bandwidth = bandwidth_cv$bandwidth_opt * 0.2,
  method = "sample_point",
  scaling = "ratio"
)

# Compare surfaces and save a figure in the current working directory.
png("urban_incidents.png", width = 1500, height = 500, res = 150)
old_par <- par(mfrow = c(1, 3), mar = c(3, 3, 3, 4))
plot(fixed, main = "Fixed bandwidth")
plot(points, add = TRUE, pch = 16, cex = 0.35, col = grDevices::adjustcolor("white", alpha.f = 0.65))
plot(adaptive_balloon, main = "Adaptive balloon")
plot(points, add = TRUE, pch = 16, cex = 0.35, col = grDevices::adjustcolor("white", alpha.f = 0.65))
plot(adaptive_sample_point, main = "Adaptive sample-point")
plot(points, add = TRUE, pch = 16, cex = 0.35, col = grDevices::adjustcolor("white", alpha.f = 0.65))
par(old_par)
dev.off()

cat("Saved comparison to urban_incidents.png\n")
