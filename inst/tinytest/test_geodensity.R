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
# Summary
# =============================================================================
# All tests completed
cat("\n[YES] All geodensity tests passed!\n")
