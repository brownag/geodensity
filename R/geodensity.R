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
