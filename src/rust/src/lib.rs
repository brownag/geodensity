use extendr_api::prelude::*;
use geo::prelude::*;
use geo::Point;
use rayon::prelude::*;

/// Compute Geodesic Kernel Density Estimate with spatial indexing
///
/// This function calculates kernel density estimates on a geographic grid using geodesic
/// (great-circle) distances. The computation is parallelized across CPU cores using Rayon,
/// and uses spatial indexing (grid-based) to avoid computing distances to far-away points.
///
/// @param x_coords Vector of X (longitude) coordinates of data points
/// @param y_coords Vector of Y (latitude) coordinates of data points
/// @param grid_x Vector of X coordinates for the output grid cells
/// @param grid_y Vector of Y coordinates for the output grid cells
/// @param bandwidth_km Bandwidth in kilometers (standard deviation of Gaussian kernel)
/// @return A vector of density values corresponding to the grid points
/// @keywords internal
#[extendr]
fn geodesic_kde_rust(
    x_coords: Vec<f64>,
    y_coords: Vec<f64>,
    grid_x: Vec<f64>,
    grid_y: Vec<f64>,
    bandwidth_km: f64,
) -> Vec<f64> {
    // 1. Convert input data to geo::Point for fast distance calculation
    let data_points: Vec<Point<f64>> = x_coords
        .iter()
        .zip(y_coords.iter())
        .map(|(&x, &y)| Point::new(x, y))
        .collect();

    // 2. Compute dynamic spatial index grid size based on bandwidth and latitude
    // This accounts for varying degree-to-km conversion at different latitudes
    
    // Calculate central latitude for Vincenty approximation of degree-to-km conversion
    let central_lat = if !y_coords.is_empty() {
        y_coords.iter().sum::<f64>() / y_coords.len() as f64
    } else {
        0.0
    };
    
    let lat_rad = central_lat.to_radians();
    let cos_lat = lat_rad.cos();
    
    // Haversine approximation: km per degree (varies with latitude)
    // Longitude: 111.32 * cos(lat) km/degree
    // Latitude: 111.32 km/degree (approximately constant)
    let km_per_lon_degree = 111.32 * cos_lat;
    let km_per_lat_degree = 111.32;
    
    // Search radius: 3 * bandwidth (covers 99.7% of Gaussian kernel)
    let search_radius_km = 3.0 * bandwidth_km;
    
    // Convert search radius to degrees (both directions)
    let search_radius_lon_deg = search_radius_km / km_per_lon_degree.abs().max(0.1);
    let search_radius_lat_deg = search_radius_km / km_per_lat_degree;
    
    // Use smaller radius for safety (guarantees we find neighbors)
    let search_radius_deg = search_radius_lon_deg.min(search_radius_lat_deg);
    
    // Index cell size: 1.5x the search radius (ensures 2-3 layers of adjacent cells)
    // This prevents missing neighbors at cell boundaries
    // Bounded at [0.1 degrees, 45 degrees] to prevent pathological cases
    let index_cell_size = (search_radius_deg * 1.5)
        .max(0.1)
        .min(45.0);
    
    // 3. Build spatial grid index with dynamic cell size
    // Use a multi-key approach for dateline-aware indexing
    let mut grid_index: std::collections::HashMap<(i32, i32), Vec<usize>> = 
        std::collections::HashMap::new();
    
    for (idx, point) in data_points.iter().enumerate() {
        let x_key = (point.x() / index_cell_size).floor() as i32;
        let y_key = (point.y() / index_cell_size).floor() as i32;
        
        // Add point to its natural cell
        grid_index.entry((x_key, y_key)).or_insert_with(Vec::new).push(idx);
        
        // For dateline handling: also add to wrapped position if near +/-180
        // This ensures points near -180 can be found when querying near +180
        if point.x() > 90.0 {
            // Wrap positive values near +180 to negative equivalent
            let wrapped_x = point.x() - 360.0;
            let wrapped_key = (wrapped_x / index_cell_size).floor() as i32;
            grid_index.entry((wrapped_key, y_key)).or_insert_with(Vec::new).push(idx);
        } else if point.x() < -90.0 {
            // Wrap negative values near -180 to positive equivalent
            let wrapped_x = point.x() + 360.0;
            let wrapped_key = (wrapped_x / index_cell_size).floor() as i32;
            grid_index.entry((wrapped_key, y_key)).or_insert_with(Vec::new).push(idx);
        }
    }

    // 4. Calculate search radius in grid cells (rounded up for safety)
    let search_radius_cells = (search_radius_deg / index_cell_size).ceil() as i32;

    // 5. Parallel iteration over the output grid (pixels)
    let densities: Vec<f64> = grid_x
        .par_iter()
        .zip(grid_y.par_iter())
        .map(|(&gx, &gy)| {
            let grid_point = Point::new(gx, gy);
            let mut sum = 0.0;

            // Determine which grid cells could have nearby points
            let grid_x_key = (gx / index_cell_size).floor() as i32;
            let grid_y_key = (gy / index_cell_size).floor() as i32;

            // Search nearby grid cells within calculated radius
            for dx in -search_radius_cells..=search_radius_cells {
                for dy in -search_radius_cells..=search_radius_cells {
                    let cell_key = (grid_x_key + dx, grid_y_key + dy);
                    
                    if let Some(point_indices) = grid_index.get(&cell_key) {
                        // Compute distances only to points in nearby cells
                        for &idx in point_indices {
                            let point = &data_points[idx];
                            let dist_meters = point.haversine_distance(&grid_point);
                            let dist_km = dist_meters / 1000.0;

                            // Gaussian kernel with 3-sigma cutoff for efficiency
                            if dist_km < (bandwidth_km * 3.0) {
                                let exponent = -0.5 * (dist_km / bandwidth_km).powi(2);
                                let k = exponent.exp();
                                sum += k;
                            }
                        }
                    }
                }
            }
            sum
        })
        .collect();

    densities
}

// Macro to generate exports.
// This ensures exported functions are registered with R.
// See corresponding C code in `entrypoint.c`.
extendr_module! {
    mod geodensity;
    fn geodesic_kde_rust;
}
