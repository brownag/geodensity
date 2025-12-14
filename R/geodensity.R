#' Calculate Geodesic Kernel Density Estimate
#'
#' Computes kernel density estimates on a geographic grid using geodesic (great-circle)
#' distances. This function is optimized for large datasets and automatically parallelizes
#' the computation across available CPU cores using Rust's Rayon library.
#'
#' The bandwidth parameter controls the smoothing level. It is specified in kilometers
#' and represents the standard deviation of the Gaussian kernel. Larger values produce
#' smoother, more generalized density surfaces.
#'
#' @param x A `SpatVector` or `sf` object containing points in geographic coordinates
#'   (latitude/longitude). Data must be in a geographic CRS (lon/lat). If you have
#'   projected data, reproject to geographic coordinates first with `terra::project()`.
#' @param r A template `SpatRaster` defining the resolution and extent of the output grid.
#'   The output density raster will have the same dimensions, resolution, and CRS as this
#'   template. Use `terra::rast()` to create a template raster if needed.
#' @param bandwidth Bandwidth in kilometers (numeric scalar). This is the standard deviation
#'   of the Gaussian kernel used for smoothing. For point density estimation, typical
#'   values range from 1 km to 100 km depending on data scale and desired smoothing.
#'   The effective range of the kernel extends to approximately 3 * bandwidth.
#'
#' @return A `SpatRaster` containing the kernel density estimates at each grid cell.
#'   Values represent the density of input points, with higher values indicating
#'   concentrated clustering and lower values indicating sparse regions.
#'
#' @import terra
#'
#' @details
#' ## Geodesic Accuracy
#' This function uses geodesic (great-circle) distances calculated via the Haversine
#' formula, which is accurate for Earth-scale distances and automatically accounts for
#' latitude-dependent distortion. This avoids the need for manual reprojection to
#' equal-area coordinate systems and ensures consistent results across the globe.
#'
#' ## Performance
#' The computation is parallelized across all available CPU cores. For typical 1km-resolution
#' rasters with thousands to millions of input points, computation time ranges from seconds
#' to minutes on standard hardware. Memory usage is proportional to the grid size, not
#' the number of input points, making it suitable for processing very large datasets.
#'
#' ## Edge Effects
#' The kernel is applied without modification at raster edges, which may produce
#' artificially low density values near boundaries. For analysis requiring buffer zones,
#' create a template raster extending beyond your area of interest.
#'
#' @examples
#' \dontrun{
#' library(geodensity)
#' library(terra)
#'
#' # Create sample point data
#' pts <- data.frame(lon = c(-74.0, -118.2, -87.6), lat = c(40.7, 34.0, 41.8))
#' pts_spat <- terra::vect(pts, geom = c("lon", "lat"), crs = "EPSG:4326")
#'
#' # Create output template raster (1 km resolution)
#' template <- terra::rast(
#'   extent = c(-75, -117, 33, 42),
#'   resolution = 0.01, # ~1 km at equator
#'   crs = "EPSG:4326"
#' )
#'
#' # Calculate density
#' dens <- kde_geodesic(pts_spat, template, bandwidth = 50)
#'
#' # Visualize
#' plot(dens, main = "Point Density (50 km bandwidth)")
#' }
#'
#' @export
kde_geodesic <- function(x, r, bandwidth) {
  # 1. Validation and Data Extraction
  if (inherits(x, "sf")) {
    x <- terra::vect(x)
  }

  if (!inherits(x, "SpatVector")) {
    stop("x must be a SpatVector or sf object")
  }

  if (!inherits(r, "SpatRaster")) {
    stop("r must be a SpatRaster")
  }

  if (!is.numeric(bandwidth) || length(bandwidth) != 1 || bandwidth <= 0) {
    stop("bandwidth must be a positive numeric scalar (in kilometers)")
  }

  # Check that input is in geographic (lon/lat) coordinates
  # Suppress warnings from is.lonlat when checking projected CRS
  if (!suppressWarnings(terra::is.lonlat(x))) {
    stop(
      "Input points must be in Geographic CRS (latitude/longitude). ",
      "Current CRS: ", terra::crs(x), ". ",
      "Reproject using terra::project() if needed."
    )
  }

  # Check that template raster is also in geographic coordinates
  if (!suppressWarnings(terra::is.lonlat(r))) {
    stop(
      "Template raster must be in Geographic CRS (latitude/longitude). ",
      "Current CRS: ", terra::crs(r), ". ",
      "Reproject using terra::project() if needed."
    )
  }

  # Extract coordinates from the SpatVector
  pts <- terra::crds(x)

  if (nrow(pts) == 0) {
    stop("Input vector contains no points")
  }

  message(
    sprintf(
      "Computing geodesic KDE: %d points, %d grid cells, %.1f km bandwidth",
      nrow(pts), terra::ncell(r), bandwidth
    )
  )

  # 2. Extract Grid Coordinates from Template Raster
  # We need the center of every pixel to calculate distance to it
  grid_coords <- terra::xyFromCell(r, 1:terra::ncell(r))

  # 3. Call the Rust Kernel (this is where the heavy computation happens)
  # The Rust backend handles parallelization automatically
  density_values <- geodesic_kde_rust(
    x_coords = pts[, 1],
    y_coords = pts[, 2],
    grid_x = grid_coords[, 1],
    grid_y = grid_coords[, 2],
    bandwidth_km = bandwidth
  )

  # 4. Reconstruct SpatRaster with the computed densities
  out <- r
  terra::values(out) <- density_values

  return(out)
}

#' Adaptive Geodesic Kernel Density Estimation
#'
#' Computes adaptive kernel density estimates where the bandwidth varies inversely with
#' local point density. High-density regions use smaller bandwidths for fine detail,
#' while sparse regions use larger bandwidths for smoother estimates. This is useful
#' when point density varies dramatically across the study area.
#'
#' The algorithm uses a two-pass approach:
#' 1. Compute pilot density with fixed `pilot_bandwidth`
#' 2. Scale bandwidth per grid cell as: `pilot_bandwidth / sqrt(pilot_density)`,
#'    clamped to `[min_bandwidth, pilot_bandwidth]`
#' 3. Compute final density using the scaled per-cell bandwidths
#'
#' @param x A `SpatVector` or `sf` object containing points in geographic coordinates
#'   (latitude/longitude). Data must be in a geographic CRS (lon/lat). If you have
#'   projected data, reproject to geographic coordinates first with `terra::project()`.
#' @param r A template `SpatRaster` defining the resolution and extent of the output grid.
#'   The output density raster will have the same dimensions, resolution, and CRS as this
#'   template. Use `terra::rast()` to create a template raster if needed.
#' @param pilot_bandwidth Pilot bandwidth in kilometers (numeric scalar). This is used
#'   in the first pass to compute the initial density. Typical values range from 10 km
#'   to 100 km. Smaller values adapt more aggressively; larger values produce smoother
#'   adaptation.
#' @param min_bandwidth Minimum bandwidth in kilometers (numeric scalar). Limits how small
#'   the adaptive bandwidth can become in high-density regions. Default is 10% of pilot
#'   bandwidth. Must be positive and less than `pilot_bandwidth`.
#'
#' @return A `SpatRaster` containing the adaptive kernel density estimates at each grid cell.
#'   Values represent the density of input points computed with locally-scaled kernels.
#'
#' @import terra
#'
#' @details
#' ## When to Use Adaptive KDE
#'
#' Adaptive KDE is particularly useful for datasets with highly variable point density:
#' - **Clustered point patterns:** Geographic hotspots surrounded by sparse regions
#'   (e.g., urban centers vs. rural areas)
#' - **Multi-scale phenomena:** Events occurring at both local clusters and regional scales
#' - **Sparse data in large areas:** Few points spread over vast territories
#'
#' ## Advantages Over Fixed Bandwidth
#'
#' - Better visual detail in dense regions (smaller bandwidth where points cluster)
#' - Less over-smoothing of isolated features (larger bandwidth in sparse regions)
#' - Often better statistical properties for heterogeneous point patterns
#'
#' @examples
#' \dontrun{
#' library(geodensity)
#' library(terra)
#'
#' # Create sample point data with variable density
#' set.seed(42)
#' dense_cluster <- data.frame(
#'   lon = rnorm(500, mean = -100, sd = 0.5),
#'   lat = rnorm(500, mean = 40, sd = 0.5)
#' )
#' sparse_region <- data.frame(
#'   lon = runif(100, -110, -90),
#'   lat = runif(100, 30, 50)
#' )
#' pts_data <- rbind(dense_cluster, sparse_region)
#' pts <- terra::vect(pts_data, geom = c("lon", "lat"), crs = "EPSG:4326")
#'
#' # Create output template raster
#' template <- terra::rast(
#'   extent = c(-110, -90, 30, 50),
#'   resolution = 0.1,
#'   crs = "EPSG:4326"
#' )
#'
#' # Compute adaptive density
#' dens_adaptive <- kde_adaptive(pts, template, pilot_bandwidth = 50, min_bandwidth = 5)
#'
#' # Compare to fixed bandwidth
#' dens_fixed <- kde_geodesic(pts, template, bandwidth = 50)
#'
#' # Visualize
#' par(mfrow = c(1, 2))
#' plot(dens_fixed, main = "Fixed Bandwidth KDE")
#' plot(dens_adaptive, main = "Adaptive Bandwidth KDE")
#' }
#'
#' @export
kde_adaptive <- function(x, r, pilot_bandwidth, min_bandwidth = NULL) {
  # 1. Validation and Data Extraction
  if (inherits(x, "sf")) {
    x <- terra::vect(x)
  }

  if (!inherits(x, "SpatVector")) {
    stop("x must be a SpatVector or sf object")
  }

  if (!inherits(r, "SpatRaster")) {
    stop("r must be a SpatRaster")
  }

  if (!is.numeric(pilot_bandwidth) || length(pilot_bandwidth) != 1 || pilot_bandwidth <= 0) {
    stop("pilot_bandwidth must be a positive numeric scalar (in kilometers)")
  }

  # Set default min_bandwidth to 10% of pilot bandwidth if not specified
  if (is.null(min_bandwidth)) {
    min_bandwidth <- pilot_bandwidth * 0.1
  }

  if (!is.numeric(min_bandwidth) || length(min_bandwidth) != 1 || min_bandwidth <= 0) {
    stop("min_bandwidth must be a positive numeric scalar (in kilometers)")
  }

  if (min_bandwidth >= pilot_bandwidth) {
    stop("min_bandwidth must be less than pilot_bandwidth")
  }

  # Check that input is in geographic (lon/lat) coordinates
  if (!suppressWarnings(terra::is.lonlat(x))) {
    stop(
      "Input points must be in Geographic CRS (latitude/longitude). ",
      "Current CRS: ", terra::crs(x), ". ",
      "Reproject using terra::project() if needed."
    )
  }

  # Check that template raster is also in geographic coordinates
  if (!suppressWarnings(terra::is.lonlat(r))) {
    stop(
      "Template raster must be in Geographic CRS (latitude/longitude). ",
      "Current CRS: ", terra::crs(r), ". ",
      "Reproject using terra::project() if needed."
    )
  }

  # Extract coordinates from the SpatVector
  pts <- terra::crds(x)

  if (nrow(pts) == 0) {
    stop("Input vector contains no points")
  }

  message(
    sprintf(
      "Computing adaptive geodesic KDE: %d points, %d grid cells, %.1f km pilot bandwidth, %.1f km min bandwidth",
      nrow(pts), terra::ncell(r), pilot_bandwidth, min_bandwidth
    )
  )

  # 2. Extract Grid Coordinates from Template Raster
  grid_coords <- terra::xyFromCell(r, 1:terra::ncell(r))

  # 3. Call the Rust Adaptive Kernel (this is where the heavy computation happens)
  # The Rust backend handles the two-pass algorithm and parallelization automatically
  density_values <- geodesic_kde_adaptive_rust(
    x_coords = pts[, 1],
    y_coords = pts[, 2],
    grid_x = grid_coords[, 1],
    grid_y = grid_coords[, 2],
    pilot_bandwidth_km = pilot_bandwidth,
    min_bandwidth_km = min_bandwidth
  )

  # 4. Reconstruct SpatRaster with the computed densities
  out <- r
  terra::values(out) <- density_values

  return(out)
}
