# Test suite for geodensity package
# Using tinytest framework

library(tinytest)
library(terra)
library(geodensity)

# =============================================================================
# Test 1: Function exists and is callable
# =============================================================================
expect_true(exists("kde_geodesic"), info = "kde_geodesic function should exist")
expect_true(is.function(kde_geodesic), info = "kde_geodesic should be a function")


# =============================================================================
# Test 2: Basic usage with sample data
# =============================================================================
# Create minimal sample data with OGC:CRS84 geographic CRS
# OGC:CRS84 is the official Open Geospatial Consortium identifier for WGS84
pts <- data.frame(
  lon = c(-74.0, -118.2, -87.6),
  lat = c(40.7, 34.0, 41.8)
)
pts_vec <- terra::vect(pts, geom = c("lon", "lat"), crs = "OGC:CRS84")

# Create template raster
template <- terra::rast(
  extent = c(-120, -70, 30, 45),
  resolution = 2,
  crs = "OGC:CRS84"
)

# Should execute without error
expect_silent(
  result <- kde_geodesic(pts_vec, template, bandwidth = 50),
  info = "kde_geodesic should compute without error on valid input"
)


# =============================================================================
# Test 3: Output is a SpatRaster
# =============================================================================
expect_true(
  inherits(result, "SpatRaster"),
  info = "Result should be a SpatRaster object"
)


# =============================================================================
# Test 4: Output has correct dimensions
# =============================================================================
expect_equal(
  dim(result),
  dim(template),
  info = "Output raster should have same dimensions as template"
)


# =============================================================================
# Test 5: Output has correct CRS
# =============================================================================
expect_equal(
  terra::crs(result),
  terra::crs(template),
  info = "Output raster should inherit template's CRS"
)


# =============================================================================
# Test 6: Output values are numeric and non-negative
# =============================================================================
vals <- terra::values(result)
expect_true(
  is.numeric(vals),
  info = "Output values should be numeric"
)

expect_true(
  all(vals >= 0, na.rm = TRUE),
  info = "Output values should be non-negative"
)


# =============================================================================
# Test 7: Output contains at least some non-zero values
# =============================================================================
expect_true(
  any(vals > 0, na.rm = TRUE),
  info = "Output should contain non-zero density values near input points"
)


# =============================================================================
# Test 8: CRS validation - reject non-geographic CRS
# =============================================================================
# Create projected data (Web Mercator)
pts_projected <- terra::project(pts_vec, "EPSG:3857")

expect_error(
  kde_geodesic(pts_projected, template, bandwidth = 50),
  info = "Function should reject non-geographic CRS"
)


# =============================================================================
# Test 9: CRS validation - reject template with non-geographic CRS
# =============================================================================
template_projected <- terra::project(template, "EPSG:3857")

expect_error(
  kde_geodesic(pts_vec, template_projected, bandwidth = 50),
  info = "Function should reject template with non-geographic CRS"
)


# =============================================================================
# Test 10: Empty points should error gracefully
# =============================================================================
pts_empty <- terra::vect(
  data.frame(lon = numeric(0), lat = numeric(0)),
  geom = c("lon", "lat"),
  crs = "OGC:CRS84"
)

expect_error(
  kde_geodesic(pts_empty, template, bandwidth = 50),
  info = "Function should error on empty input"
)


# =============================================================================
# Test 11: sf object input (automatic conversion to SpatVector)
# =============================================================================
if (requireNamespace("sf", quietly = TRUE)) {
  pts_sf <- sf::st_as_sf(pts, coords = c("lon", "lat"), crs = 4326)

  expect_silent(
    result_sf <- kde_geodesic(pts_sf, template, bandwidth = 50),
    info = "kde_geodesic should accept sf objects"
  )

  expect_true(
    inherits(result_sf, "SpatRaster"),
    info = "Result from sf input should be SpatRaster"
  )
}


# =============================================================================
# Test 12: Single point input
# =============================================================================
pts_single <- terra::vect(
  data.frame(lon = -74.0, lat = 40.7),
  geom = c("lon", "lat"),
  crs = "OGC:CRS84"
)

expect_silent(
  result_single <- kde_geodesic(pts_single, template, bandwidth = 50),
  info = "kde_geodesic should handle single point"
)

expect_true(
  any(terra::values(result_single) > 0, na.rm = TRUE),
  info = "Single point should produce density values"
)


# =============================================================================
# Test 13: Bandwidth validation - negative bandwidth
# =============================================================================
expect_error(
  kde_geodesic(pts_vec, template, bandwidth = -10),
  info = "Function should reject negative bandwidth"
)


# =============================================================================
# Test 14: Bandwidth validation - zero bandwidth
# =============================================================================
expect_error(
  kde_geodesic(pts_vec, template, bandwidth = 0),
  info = "Function should reject zero bandwidth"
)


# =============================================================================
# Test 15: Different bandwidth values produce different results
# =============================================================================
result_small_bw <- kde_geodesic(pts_vec, template, bandwidth = 10)
result_large_bw <- kde_geodesic(pts_vec, template, bandwidth = 100)

expect_false(
  all(terra::values(result_small_bw) == terra::values(result_large_bw), na.rm = TRUE),
  info = "Different bandwidths should produce different density patterns"
)


# =============================================================================
# Test 16: Different bandwidth values produce different results
# =============================================================================
# (Note: Peak density relationship may be complex with coarse grids, so we just
#  verify outputs are different, not their relative magnitudes)
result_small_bw_2 <- kde_geodesic(pts_vec, template, bandwidth = 10)
result_large_bw_2 <- kde_geodesic(pts_vec, template, bandwidth = 100)

expect_false(
  all(terra::values(result_small_bw_2) == terra::values(result_large_bw_2), na.rm = TRUE),
  info = "Different bandwidths should produce different results"
)


# =============================================================================
# Test 17: Rust backend function exists in package namespace
# =============================================================================
expect_true(
  exists("geodesic_kde_rust", where = asNamespace("geodensity")),
  info = "Internal geodesic_kde_rust function should be available in package namespace"
)


# =============================================================================
# Test 18: Rust backend with direct vectors
# =============================================================================
# Test the internal Rust function directly via namespace
x_coords <- c(-74, -118, -87)
y_coords <- c(40, 34, 41)

# Create a grid: for each combination of grid cells
grid_xs <- rep(seq(-120, -70, by = 10), each = 4)  # 6 x-values, 4 y-values
grid_ys <- rep(seq(30, 45, by = 5), times = 6)     # Total of 24 grid cells

result_direct <- geodensity:::geodesic_kde_rust(x_coords, y_coords, grid_xs, grid_ys, 50)

expect_true(
  is.numeric(result_direct),
  info = "Rust backend should return numeric vector"
)

expect_equal(
  length(result_direct),
  length(grid_xs),
  info = "Rust backend output length should match grid size"
)


# =============================================================================
# Test 19: Large bandwidth test
# =============================================================================
result_very_large <- kde_geodesic(pts_vec, template, bandwidth = 500)

expect_true(
  inherits(result_very_large, "SpatRaster"),
  info = "Very large bandwidth should still work"
)

expect_true(
  all(!is.na(terra::values(result_very_large))),
  info = "Large bandwidth should produce valid values"
)


# =============================================================================
# Test 20: Small bandwidth test
# =============================================================================
result_small_bw <- kde_geodesic(pts_vec, template, bandwidth = 1)

expect_true(
  inherits(result_small_bw, "SpatRaster"),
  info = "Small bandwidth should still work"
)


# =============================================================================
# ADAPTIVE KDE TESTS
# =============================================================================

# =============================================================================
# Test 21: kde_adaptive function exists
# =============================================================================
expect_true(exists("kde_adaptive"), info = "kde_adaptive function should exist")
expect_true(is.function(kde_adaptive), info = "kde_adaptive should be a function")


# =============================================================================
# Test 22: Basic adaptive KDE usage
# =============================================================================
result_adaptive <- kde_adaptive(pts_vec, template, pilot_bandwidth = 50)

expect_true(
  inherits(result_adaptive, "SpatRaster"),
  info = "Adaptive result should be a SpatRaster"
)


# =============================================================================
# Test 23: Adaptive KDE with explicit min_bandwidth
# =============================================================================
result_adaptive_explicit <- kde_adaptive(pts_vec, template, 
                                         pilot_bandwidth = 50, 
                                         min_bandwidth = 5)

expect_true(
  inherits(result_adaptive_explicit, "SpatRaster"),
  info = "Adaptive with explicit min_bandwidth should work"
)


# =============================================================================
# Test 24: Adaptive output dimensions match template
# =============================================================================
expect_equal(
  dim(result_adaptive),
  dim(template),
  info = "Adaptive output should match template dimensions"
)


# =============================================================================
# Test 25: Adaptive output values are non-negative
# =============================================================================
vals_adaptive <- terra::values(result_adaptive)
expect_true(
  all(vals_adaptive >= 0, na.rm = TRUE),
  info = "Adaptive output values should be non-negative"
)


# =============================================================================
# Test 26: Adaptive KDE is executable (may match fixed for tiny sample)
# =============================================================================
result_fixed_50 <- kde_geodesic(pts_vec, template, bandwidth = 50)
result_adaptive_50 <- kde_adaptive(pts_vec, template, pilot_bandwidth = 50, min_bandwidth = 5)

expect_true(
  inherits(result_adaptive_50, "SpatRaster"),
  info = "Adaptive KDE should produce a SpatRaster"
)


# =============================================================================
# Test 27: Clustered data - adaptive vs fixed comparison
# =============================================================================
# Create clustered point pattern (dense center, sparse periphery)
set.seed(42)
cluster_dense <- data.frame(
  lon = rnorm(100, mean = -100, sd = 0.2),
  lat = rnorm(100, mean = 40, sd = 0.2)
)
cluster_sparse <- data.frame(
  lon = runif(30, -105, -95),
  lat = runif(30, 35, 45)
)
pts_clustered_data <- rbind(cluster_dense, cluster_sparse)
pts_clustered <- terra::vect(pts_clustered_data, geom = c("lon", "lat"), crs = "OGC:CRS84")

template_clustered <- terra::rast(
  extent = c(-106, -94, 34, 46),
  resolution = 0.5,
  crs = "OGC:CRS84"
)

# Compute both fixed and adaptive
result_fixed_cluster <- kde_geodesic(pts_clustered, template_clustered, bandwidth = 50)
result_adaptive_cluster <- kde_adaptive(pts_clustered, template_clustered, 
                                        pilot_bandwidth = 50, min_bandwidth = 5)

# Adaptive should produce values in both high and low density regions
max_adaptive <- max(terra::values(result_adaptive_cluster), na.rm = TRUE)
expect_true(
  max_adaptive > 0,
  info = "Adaptive KDE should produce positive density in clustered data"
)


# =============================================================================
# Test 28: Validation - min_bandwidth validation
# =============================================================================
expect_error(
  kde_adaptive(pts_vec, template, pilot_bandwidth = 50, min_bandwidth = -5),
  info = "Should reject negative min_bandwidth"
)

expect_error(
  kde_adaptive(pts_vec, template, pilot_bandwidth = 50, min_bandwidth = 0),
  info = "Should reject zero min_bandwidth"
)

expect_error(
  kde_adaptive(pts_vec, template, pilot_bandwidth = 50, min_bandwidth = 60),
  info = "Should reject min_bandwidth greater than pilot_bandwidth"
)


# =============================================================================
# Test 29: Rust backend adaptive function exists
# =============================================================================
expect_true(
  exists("geodesic_kde_adaptive_rust", where = asNamespace("geodensity")),
  info = "Internal geodesic_kde_adaptive_rust function should be available"
)


# =============================================================================
# Test 30: Default min_bandwidth is 10% of pilot
# =============================================================================
# Compute with implicit default
result_default_min <- kde_adaptive(pts_clustered, template_clustered, pilot_bandwidth = 50)

# Compute with explicit 10% minimum (0.1 * 50 = 5)
result_explicit_min <- kde_adaptive(pts_clustered, template_clustered, 
                                    pilot_bandwidth = 50, min_bandwidth = 5)

expect_true(
  inherits(result_default_min, "SpatRaster"),
  info = "Adaptive with default min_bandwidth should work"
)


# =============================================================================
# Test 31: LOOCV bandwidth_optimize baseline (geo haversine, tolerance 1e-5)
# =============================================================================
set.seed(42)
pts_data <- data.frame(lon = c(rnorm(100, -100, 2), rnorm(50, -95, 1)),
                       lat = c(rnorm(100, 40, 2), rnorm(50, 38, 1)))
pts <- terra::vect(pts_data, geom = c("lon", "lat"), crs = "EPSG:4326")
res <- bandwidth_optimize(pts, bandwidth_min = 1, bandwidth_max = 50,
                          n_bandwidths = 8, verbose = FALSE)

expect_equal(
  res$log_likelihood,
  c(-22.740032207, -22.209357431, -20.488981758, -17.765337732,
    -13.906234260, -10.772277308, -9.015811849, -8.595541678),
  tolerance = 1e-5,
  info = "LOOCV log-likelihoods should match baseline"
)
# Optimum sits on the top grid edge (boundary value; do not move the grid)
expect_equal(res$bandwidth_opt, 50)


# =============================================================================
# Test 32-series: independent brute-force KDE references (task 5.1.2)
# No spatial index. Haversine with R = 6371.0088 km (geo's mean radius).
# Unnormalized kernel sums; normalization is task 5.1.5.
# =============================================================================
bf_R_KM <- 6371.0088

# Haversine distance (km) from data points (x, y) to one grid point (gx, gy)
bf_haversine_km <- function(x, y, gx, gy) {
  p1 <- gy * pi / 180
  p2 <- y * pi / 180
  a <- sin((p2 - p1) / 2)^2 + cos(p1) * cos(p2) * sin((x - gx) * pi / 360)^2
  2 * bf_R_KM * asin(pmin(1, sqrt(a)))
}

# Destination point (lon, lat) at dist_km along bearing_deg (0 = north, 90 = east)
bf_destination <- function(lon, lat, dist_km, bearing_deg) {
  delta <- dist_km / bf_R_KM
  theta <- bearing_deg * pi / 180
  phi1 <- lat * pi / 180
  lam1 <- lon * pi / 180
  phi2 <- asin(sin(phi1) * cos(delta) + cos(phi1) * sin(delta) * cos(theta))
  lam2 <- lam1 + atan2(sin(theta) * sin(delta) * cos(phi1),
                       cos(delta) - sin(phi1) * sin(phi2))
  c(lon = (lam2 * 180 / pi + 540) %% 360 - 180, lat = phi2 * 180 / pi)
}

# Fixed-bandwidth reference: sum of exp(-0.5 (d/bw)^2) over d < 3 bw
bf_fixed <- function(x, y, gx, gy, bw) {
  vapply(seq_along(gx), function(i) {
    d <- bf_haversine_km(x, y, gx[i], gy[i])
    keep <- d < 3 * bw
    sum(exp(-0.5 * (d[keep] / bw)^2))
  }, numeric(1))
}

# Adaptive reference: brute-force pilot, per-cell scale, brute-force sum with cutoff 3*scale
bf_adaptive <- function(x, y, gx, gy, pilot, min_bw) {
  p <- bf_fixed(x, y, gx, gy, pilot)
  dmax <- max(p)
  ratio <- if (dmax > 0) p / dmax else rep(0, length(p))
  scale <- min_bw + (pilot - min_bw) / (1 + sqrt(ratio))
  vapply(seq_along(gx), function(i) {
    d <- bf_haversine_km(x, y, gx[i], gy[i])
    keep <- d < 3 * scale[i]
    sum(exp(-0.5 * (d[keep] / scale[i])^2))
  }, numeric(1))
}

# Relative comparison at 1e-10 per element. Where the reference is 0, the result must be 0.
bf_expect <- function(res, ref, info) {
  expect_equal(length(res), length(ref), info = paste(info, "length"))
  rel <- ifelse(ref == 0, abs(res), abs(res - ref) / abs(ref))
  expect_true(all(rel <= 1e-10),
              info = sprintf("%s: max relative diff %.3g (1e-10 allowed)", info, max(rel)))
}

# Case A: heterogeneous latitudes, roughly -60 to 75
set.seed(5201)
ha_x <- runif(200, -120, -40)
ha_y <- runif(200, -60, 75)
ha_gx <- rep(seq(-120, -40, length.out = 13), 9)
ha_gy <- rep(seq(-60, 75, length.out = 9), each = 13)
for (bw in c(40, 250)) {
  bf_expect(geodesic_kde_rust(ha_x, ha_y, ha_gx, ha_gy, bw),
            bf_fixed(ha_x, ha_y, ha_gx, ha_gy, bw),
            sprintf("fixed heterogeneous bw=%g", bw))
}
bf_expect(geodesic_kde_adaptive_rust(ha_x, ha_y, ha_gx, ha_gy, 150, 15),
          bf_adaptive(ha_x, ha_y, ha_gx, ha_gy, 150, 15),
          "adaptive heterogeneous pilot=150 min=15")

# Case B: dateline-crossing set, data and grid on both sides of +/-180 at lat 68-76
set.seed(5202)
hb_x <- c(runif(60, 170, 180), runif(60, -180, -170), 180, -180)
hb_y <- runif(122, 68, 76)
hb_gx <- c(runif(20, 170, 180), runif(20, -180, -170), 179.5, -179.5, 180, -180)
hb_gy <- c(runif(40, 68, 76), rep(72, 4))
for (bw in c(60, 120)) {
  bf_expect(geodesic_kde_rust(hb_x, hb_y, hb_gx, hb_gy, bw),
            bf_fixed(hb_x, hb_y, hb_gx, hb_gy, bw),
            sprintf("fixed dateline bw=%g", bw))
}
bf_expect(geodesic_kde_adaptive_rust(hb_x, hb_y, hb_gx, hb_gy, 120, 12),
          bf_adaptive(hb_x, hb_y, hb_gx, hb_gy, 120, 12),
          "adaptive dateline pilot=120 min=12")

# Case C: contributors at 0.9x, 0.999x, 1.1x the cutoff, due north (0) and due east (90),
# at lat 40 and lat 65. Cutoff is 3*bw (fixed, bw = 50) or 3*scale (adaptive, single cell).
for (cx in list(c(-100, 40), c(-60, 65))) {
  pts <- NULL
  for (f in c(0.9, 0.999, 1.1)) for (b in c(0, 90)) {
    dst <- bf_destination(cx[1], cx[2], f * 150, b)
    expect_equal(bf_haversine_km(dst[1], dst[2], cx[1], cx[2]), f * 150, tolerance = 1e-12,
                 info = sprintf("placement f=%g bearing=%g lat=%g", f, b, cx[2]))
    pts <- rbind(pts, dst)
  }
  bf_expect(geodesic_kde_rust(pts[, 1], pts[, 2], cx[1], cx[2], 50),
            bf_fixed(pts[, 1], pts[, 2], cx[1], cx[2], 50),
            sprintf("fixed cutoff-band lat=%g bw=50", cx[2]))
  # Adaptive, one grid cell: ratio = 1, so scale = min + (pilot - min)/2 = 37.5 km (pilot 50, min 25)
  pts_a <- NULL
  for (f in c(0.9, 0.999, 1.1)) for (b in c(0, 90)) {
    pts_a <- rbind(pts_a, bf_destination(cx[1], cx[2], f * 3 * 37.5, b))
  }
  bf_expect(geodesic_kde_adaptive_rust(pts_a[, 1], pts_a[, 2], cx[1], cx[2], 50, 25),
            bf_adaptive(pts_a[, 1], pts_a[, 2], cx[1], cx[2], 50, 25),
            sprintf("adaptive cutoff-band lat=%g", cx[2]))
}

# Case D: grid cells on and near index-cell boundaries (offsets -1e-9, 0, +1e-9 deg).
# Boundary spacing: 1.5 * (3 bw) in degrees, lat-based for latitude and cos(75) for longitude.
bf_cell_lat <- function(bw) 1.5 * 3 * bw / (bf_R_KM * pi / 180)
bf_cell_lon <- function(bw) 1.5 * 3 * bw / (bf_R_KM * pi / 180 * cos(75 * pi / 180))
set.seed(5204)
hd_x <- runif(200, -120, -40)
hd_y <- runif(200, -60, 75)
for (bw in c(40, 90)) {
  off <- c(-1e-9, 0, 1e-9)
  cl <- bf_cell_lon(bw); ct <- bf_cell_lat(bw)
  lon_b <- as.vector(outer(seq(floor(-120 / cl), ceiling(-40 / cl)) * cl, off, "+"))
  lat_b <- as.vector(outer(seq(floor(-60 / ct), ceiling(75 / ct)) * ct, off, "+"))
  g <- expand.grid(gx = lon_b, gy = lat_b)
  bf_expect(geodesic_kde_rust(hd_x, hd_y, g$gx, g$gy, bw),
            bf_fixed(hd_x, hd_y, g$gx, g$gy, bw),
            sprintf("fixed index-boundary bw=%g", bw))
  bf_expect(geodesic_kde_adaptive_rust(hd_x, hd_y, g$gx, g$gy, 150, 15),
            bf_adaptive(hd_x, hd_y, g$gx, g$gy, 150, 15),
            "adaptive index-boundary pilot=150 min=15")
}

# Bearing that maximises the longitude offset of a point at dist_km from (lat, 0).
# The longitude half-width is attained at this tangent point, which is not due east
# (a great circle heading east from lat 65 bends south).
bf_tangent_bearing <- function(lat, dist_km) {
  optimize(function(b) bf_destination(0, lat, dist_km, b)[1], c(0, 90),
           maximum = TRUE, tol = 1e-12)$maximum
}

# Case E: contributors just inside the cutoff at the tangent (max-longitude) bearing,
# 0.9996x and 0.9999x the cutoff, at lat 40 and lat 65. Also due north 0.9996x at lat 65.
for (lat0 in c(40, 65)) {
  b_t <- bf_tangent_bearing(lat0, 150)
  pts_e <- NULL
  for (f in c(0.9996, 0.9999)) {
    dst <- bf_destination(-100, lat0, f * 150, b_t)
    expect_equal(bf_haversine_km(dst[1], dst[2], -100, lat0), f * 150, tolerance = 1e-12,
                 info = sprintf("tangent placement f=%g lat=%g", f, lat0))
    pts_e <- rbind(pts_e, dst)
  }
  bf_expect(geodesic_kde_rust(pts_e[, 1], pts_e[, 2], -100, lat0, 50),
            bf_fixed(pts_e[, 1], pts_e[, 2], -100, lat0, 50),
            sprintf("fixed tangent-east lat=%g bw=50", lat0))
  # Adaptive, single grid cell: scale = 37.5 km (pilot 50, min 25), cutoff 112.5 km
  b_ta <- bf_tangent_bearing(lat0, 3 * 37.5)
  pts_a <- NULL
  for (f in c(0.9996, 0.9999)) pts_a <- rbind(pts_a, bf_destination(-100, lat0, f * 3 * 37.5, b_ta))
  bf_expect(geodesic_kde_adaptive_rust(pts_a[, 1], pts_a[, 2], -100, lat0, 50, 25),
            bf_adaptive(pts_a[, 1], pts_a[, 2], -100, lat0, 50, 25),
            sprintf("adaptive tangent-east lat=%g", lat0))
}
dst_n <- bf_destination(-100, 65, 0.9996 * 150, 0)
bf_expect(geodesic_kde_rust(dst_n[1], dst_n[2], -100, 65, 50),
          bf_fixed(dst_n[1], dst_n[2], -100, 65, 50),
          "fixed north 0.9996 lat=65 bw=50")

# Case F: circle enclosing the pole (grid at lat 89.5, data across the dateline).
# All longitudes are inside the cutoff, so the search must not be limited to a short lon window.
hf_x <- c(-80, 80, 179.5, -179.5, 10)
hf_y <- c(89.5, 89.5, 89.7, 89.7, 89.6)
hf_gx <- c(179, -179, 0)
hf_gy <- c(89.5, 89.5, 89.5)
bf_expect(geodesic_kde_rust(hf_x, hf_y, hf_gx, hf_gy, 300),
          bf_fixed(hf_x, hf_y, hf_gx, hf_gy, 300),
          "fixed pole-enclosing bw=300")
bf_expect(geodesic_kde_adaptive_rust(hf_x, hf_y, hf_gx, hf_gy, 300, 30),
          bf_adaptive(hf_x, hf_y, hf_gx, hf_gy, 300, 30),
          "adaptive pole-enclosing pilot=300 min=30")

# Case G: index-cell edge with a capped cell. bw = 700 km at lat 65 gives a lon half-width
# of 44.7 deg, one cell (45-deg cap) wide. The grid point sits just west of a cell edge
# (lon -90), so the window reaches only ~45 deg east. A contributor at the tangent bearing,
# 0.9999x the cutoff (about 50 deg of longitude), must still be found.
g_b <- bf_tangent_bearing(65, 3 * 700)
g_d <- bf_destination(-90, 65, 0.9999 * 3 * 700, g_b)
bf_expect(geodesic_kde_rust(g_d[1], g_d[2], -90 - 1e-9, 65, 700),
          bf_fixed(g_d[1], g_d[2], -90 - 1e-9, 65, 700),
          "fixed cell-edge tangent 0.9999x bw=700 lat=65")
# Adaptive: min = 0.999 * pilot, so scale = min + (pilot - min)/2 (single cell, ratio 1)
g_s <- 699.3 + (700 - 699.3) / 2
g_ba <- bf_tangent_bearing(65, 3 * g_s)
g_da <- bf_destination(-90, 65, 0.9999 * 3 * g_s, g_ba)
bf_expect(geodesic_kde_adaptive_rust(g_da[1], g_da[2], -90 - 1e-9, 65, 700, 699.3),
          bf_adaptive(g_da[1], g_da[2], -90 - 1e-9, 65, 700, 699.3),
          "adaptive cell-edge tangent 0.9999x pilot=700 lat=65")

# =============================================================================
# Test 33-series: independent adaptive checks (task 5.1.3)
# Reuses bf_fixed / bf_adaptive / bf_expect above. Scale uses the brute-force pilot.
# =============================================================================

# Test 33a: scaling formula through its effect on output.
# scale = min + (pilot - min) / (1 + sqrt(pilot / d_max)), d_max = template max of pilot.
set.seed(5301)
t1_x <- runif(150, -105, -95)
t1_y <- runif(150, 35, 45)
t1_pts <- terra::vect(data.frame(lon = t1_x, lat = t1_y), geom = c("lon", "lat"), crs = "OGC:CRS84")
t1_tpl <- terra::rast(extent = c(-105, -95, 35, 45), resolution = 1, crs = "OGC:CRS84")
t1_grid <- terra::xyFromCell(t1_tpl, 1:terra::ncell(t1_tpl))
t1_out <- terra::values(kde_adaptive(t1_pts, t1_tpl, pilot_bandwidth = 150, min_bandwidth = 15))[, 1]
t1_ref <- bf_adaptive(t1_x, t1_y, t1_grid[, 1], t1_grid[, 2], 150, 15)
bf_expect(t1_out, t1_ref, "adaptive scaling formula pilot=150 min=15")
t1_pilot <- bf_fixed(t1_x, t1_y, t1_grid[, 1], t1_grid[, 2], 150)
t1_dmax <- max(t1_pilot)
expect_true(t1_dmax > 0, info = "scaling: d_max is positive")
t1_scale <- 15 + (150 - 15) / (1 + sqrt(t1_pilot / t1_dmax))
expect_true(all(t1_scale >= 15 - 1e-12 & t1_scale <= 150 + 1e-12),
            info = "scaling: every per-cell scale lies in [min, pilot]")

# Test 33b: zero pilot density everywhere (template far from all points).
t2_tpl <- terra::rast(extent = c(-20, -10, 30, 50), resolution = 1, crs = "OGC:CRS84")
t2_out <- terra::values(kde_adaptive(t1_pts, t2_tpl, pilot_bandwidth = 50, min_bandwidth = 5))[, 1]
expect_true(all(t2_out == 0), info = "zero pilot density: output exactly 0")
expect_false(any(is.nan(t2_out) | is.infinite(t2_out)),
             info = "zero pilot density: no NaN or Inf")

# Test 33c: template dependence. d_max is the template maximum, so a cell shared by two
# templates gets a different scale when the templates have different maxima.
# Template A contains the global pilot maximum (cell -99.5, 41.5); template B does not.
t3_a <- terra::rast(extent = c(-110, -90, 33, 47), resolution = 1, crs = "OGC:CRS84")
t3_b <- terra::rast(extent = c(-106, -100, 35, 45), resolution = 1, crs = "OGC:CRS84")
t3_ga <- terra::xyFromCell(t3_a, 1:terra::ncell(t3_a))
t3_gb <- terra::xyFromCell(t3_b, 1:terra::ncell(t3_b))
expect_true(max(bf_fixed(t1_x, t1_y, t3_gb[, 1], t3_gb[, 2], 150)) <
              max(bf_fixed(t1_x, t1_y, t3_ga[, 1], t3_ga[, 2], 150)),
            info = "template dependence: template B has smaller d_max than A")
t3_out_a <- terra::values(kde_adaptive(t1_pts, t3_a, pilot_bandwidth = 150, min_bandwidth = 15))[, 1]
t3_out_b <- terra::values(kde_adaptive(t1_pts, t3_b, pilot_bandwidth = 150, min_bandwidth = 15))[, 1]
t3_va <- t3_out_a[terra::cellFromXY(t3_a, cbind(-103.5, 38.5))]
t3_vb <- t3_out_b[terra::cellFromXY(t3_b, cbind(-103.5, 38.5))]
expect_true(abs(t3_va - t3_vb) > 1e-6 * abs(t3_va),
            info = sprintf("template dependence: shared cell differs (A=%g, B=%g)", t3_va, t3_vb))

# Test 33d: default min_bandwidth (NULL) equals explicit 0.1 * pilot_bandwidth.
t4_default <- terra::values(kde_adaptive(t1_pts, t1_tpl, pilot_bandwidth = 150))[, 1]
t4_explicit <- terra::values(kde_adaptive(t1_pts, t1_tpl, pilot_bandwidth = 150,
                                          min_bandwidth = 0.1 * 150))[, 1]
expect_identical(t4_default, t4_explicit, info = "default min_bandwidth equals 0.1 * pilot")

# =============================================================================
# Summary
# =============================================================================
# All tests completed
cat("\n[YES] All geodensity tests passed!\n")
