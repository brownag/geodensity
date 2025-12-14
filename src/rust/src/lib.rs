use extendr_api::prelude::*;
use geo::prelude::*;
use geo::Point;
use rayon::prelude::*;

/// Calculate geodesic distance in kilometers using Haversine formula
///
/// Computes great-circle distance between two points on Earth using the
/// Haversine formula. Suitable for all geographic coordinate pairs.
///
/// Algorithm: d = 2 * R * asin(sqrt(sin^2((lat2-lat1)/2) + cos(lat1)*cos(lat2)*sin^2((lon2-lon1)/2)))
/// where R = 6371 km (Earth's mean radius)
///
/// @param lon1 Longitude of first point in degrees
/// @param lat1 Latitude of first point in degrees
/// @param lon2 Longitude of second point in degrees
/// @param lat2 Latitude of second point in degrees
/// @return Distance in kilometers
fn haversine_distance_km(lon1: f64, lat1: f64, lon2: f64, lat2: f64) -> f64 {
    const EARTH_RADIUS_KM: f64 = 6371.0;
    
    let lat1_rad = lat1.to_radians();
    let lat2_rad = lat2.to_radians();
    let delta_lat = (lat2 - lat1).to_radians();
    let delta_lon = (lon2 - lon1).to_radians();
    
    let a = (delta_lat / 2.0).sin().powi(2) +
            lat1_rad.cos() * lat2_rad.cos() * (delta_lon / 2.0).sin().powi(2);
    let c = 2.0 * a.sqrt().atan2((1.0 - a).sqrt());
    
    EARTH_RADIUS_KM * c
}

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

/// Compute Adaptive Geodesic Kernel Density Estimate
///
/// This function implements a two-pass adaptive bandwidth algorithm where the bandwidth
/// at each grid cell is scaled inversely with the pilot density. High-density regions
/// use smaller bandwidths (detailed), while sparse regions use larger bandwidths (smoother).
///
/// Algorithm:
/// 1. Pass 1: Compute pilot density with fixed pilot_bandwidth_km
/// 2. Pass 2: Scale bandwidth per grid cell: bandwidth_scaled = pilot_bw / sqrt(pilot_density)
///           (clamped to [min_bandwidth_km, pilot_bandwidth_km])
/// 3. Pass 3: Compute final density using scaled bandwidths
///
/// @param x_coords Vector of X (longitude) coordinates of data points
/// @param y_coords Vector of Y (latitude) coordinates of data points
/// @param grid_x Vector of X coordinates for the output grid cells
/// @param grid_y Vector of Y coordinates for the output grid cells
/// @param pilot_bandwidth_km Pilot bandwidth in kilometers (used in Pass 1)
/// @param min_bandwidth_km Minimum bandwidth in kilometers (lower bound for scaling)
/// @return A vector of adaptive density values corresponding to the grid points
/// @keywords internal
#[extendr]
fn geodesic_kde_adaptive_rust(
    x_coords: Vec<f64>,
    y_coords: Vec<f64>,
    grid_x: Vec<f64>,
    grid_y: Vec<f64>,
    pilot_bandwidth_km: f64,
    min_bandwidth_km: f64,
) -> Vec<f64> {
    // Pass 1: Compute pilot density with fixed bandwidth
    let pilot_density = geodesic_kde_rust(
        x_coords.clone(),
        y_coords.clone(),
        grid_x.clone(),
        grid_y.clone(),
        pilot_bandwidth_km,
    );

    // Pass 2: Compute scaling factors per grid cell
    // Adaptive scaling: bandwidth_i = pilot_bw / (1 + (density_i / ref_density)^lambda)
    // where lambda controls adaptation strength and ref_density is the pilot density max
    // This gives smooth interpolation between min_bw (at high density) and pilot_bw (at zero density)
    
    let reference_density = pilot_density.iter().copied().fold(0.0, f64::max);
    let lambda = 0.5;  // Control adaptation strength
    
    let scales: Vec<f64> = pilot_density
        .iter()
        .map(|&d| {
            // Smooth scaling: high density -> lower bandwidth, low density -> higher bandwidth
            let density_ratio = if reference_density > 0.0 { d / reference_density } else { 0.0 };
            let scale_factor = 1.0 / (1.0 + density_ratio.powf(lambda));
            let bandwidth_range = pilot_bandwidth_km - min_bandwidth_km;
            min_bandwidth_km + bandwidth_range * scale_factor
        })
        .collect();

    // Pass 3: Compute final density using per-cell scaled bandwidths
    // This is more complex than Pass 1 because we need different bandwidths per grid cell
    let data_points: Vec<_> = x_coords
        .iter()
        .zip(y_coords.iter())
        .map(|(&x, &y)| geo::Point::new(x, y))
        .collect();

    // Central latitude for index sizing (use pilot bandwidth for consistency)
    let central_lat = if !y_coords.is_empty() {
        y_coords.iter().sum::<f64>() / y_coords.len() as f64
    } else {
        0.0
    };

    let lat_rad = central_lat.to_radians();
    let cos_lat = lat_rad.cos();
    let km_per_lon_degree = 111.32 * cos_lat;
    let km_per_lat_degree = 111.32;

    // Build spatial index using pilot bandwidth for consistency
    let search_radius_km = 3.0 * pilot_bandwidth_km;
    let search_radius_lon_deg = search_radius_km / km_per_lon_degree.abs().max(0.1);
    let search_radius_lat_deg = search_radius_km / km_per_lat_degree;
    let search_radius_deg = search_radius_lon_deg.min(search_radius_lat_deg);
    let index_cell_size = (search_radius_deg * 1.5).max(0.1).min(45.0);

    let mut grid_index: std::collections::HashMap<(i32, i32), Vec<usize>> =
        std::collections::HashMap::new();

    for (idx, point) in data_points.iter().enumerate() {
        let x_key = (point.x() / index_cell_size).floor() as i32;
        let y_key = (point.y() / index_cell_size).floor() as i32;

        grid_index
            .entry((x_key, y_key))
            .or_insert_with(Vec::new)
            .push(idx);

        if point.x() > 90.0 {
            let wrapped_x = point.x() - 360.0;
            let wrapped_key = (wrapped_x / index_cell_size).floor() as i32;
            grid_index
                .entry((wrapped_key, y_key))
                .or_insert_with(Vec::new)
                .push(idx);
        } else if point.x() < -90.0 {
            let wrapped_x = point.x() + 360.0;
            let wrapped_key = (wrapped_x / index_cell_size).floor() as i32;
            grid_index
                .entry((wrapped_key, y_key))
                .or_insert_with(Vec::new)
                .push(idx);
        }
    }

    let search_radius_cells = (search_radius_deg / index_cell_size).ceil() as i32;

    // Parallel computation using scaled bandwidths
    let densities: Vec<f64> = grid_x
        .par_iter()
        .zip(grid_y.par_iter())
        .zip(scales.par_iter())
        .map(|((&gx, &gy), &bandwidth_km)| {
            let grid_point = geo::Point::new(gx, gy);
            let mut sum = 0.0;

            let grid_x_key = (gx / index_cell_size).floor() as i32;
            let grid_y_key = (gy / index_cell_size).floor() as i32;

            for dx in -search_radius_cells..=search_radius_cells {
                for dy in -search_radius_cells..=search_radius_cells {
                    let cell_key = (grid_x_key + dx, grid_y_key + dy);

                    if let Some(point_indices) = grid_index.get(&cell_key) {
                        for &idx in point_indices {
                            let point = &data_points[idx];
                            let dist_meters = point.haversine_distance(&grid_point);
                            let dist_km = dist_meters / 1000.0;

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

/// Evaluate leave-one-out cross-validation log-likelihood for multiple bandwidths
///
/// Computes the leave-one-out CV score for each bandwidth by iterating through points,
/// computing density at each point using all OTHER points, and averaging log-likelihoods.
/// This is computationally expensive but provides unbiased bandwidth selection.
///
/// Returns a vector of log-likelihood scores, one per bandwidth.
///
/// @param x_coords Vector of X (longitude) coordinates of data points
/// @param y_coords Vector of Y (latitude) coordinates of data points
/// @param bandwidths Vector of bandwidth values (in km) to evaluate
/// @return Vector of log-likelihood scores (one per bandwidth)
#[extendr]
fn bandwidth_loocv_evaluate(
    x_coords: Vec<f64>,
    y_coords: Vec<f64>,
    bandwidths: Vec<f64>,
) -> Vec<f64> {
    let n_points = x_coords.len();
    if n_points == 0 || bandwidths.is_empty() {
        return vec![];
    }

    // Precompute all pairwise distances (expensive but needed for LOOCV)
    let mut distances = vec![vec![0.0; n_points]; n_points];
    
    for i in 0..n_points {
        for j in (i + 1)..n_points {
            let dist = haversine_distance_km(
                x_coords[i], y_coords[i],
                x_coords[j], y_coords[j]
            );
            distances[i][j] = dist;
            distances[j][i] = dist;
        }
    }

    // Evaluate each bandwidth
    let log_likelihoods: Vec<f64> = bandwidths
        .iter()
        .map(|&bw| {
            // For this bandwidth, compute LOOCV score
            let mut log_lik_sum = 0.0;
            let epsilon = 1e-10;
            
            // Normalization constant for 2D Gaussian kernel on sphere
            // Using Silverman's normalization: 1 / (2 * pi * bw^2) for geographic space
            let kernel_norm = 1.0 / (2.0 * std::f64::consts::PI * bw * bw);

            for test_idx in 0..n_points {
                // Compute density at test_idx using all OTHER points
                let mut density = 0.0;

                for j in 0..n_points {
                    if j == test_idx {
                        continue; // Leave-one-out: exclude self
                    }

                    let dist_km = distances[test_idx][j];
                    let kernel_val = kernel_norm * (-0.5 * (dist_km / bw).powi(2)).exp();
                    density += kernel_val;
                }

                // Add log-likelihood for this point (avoid log(0))
                log_lik_sum += (density.max(epsilon)).ln();
            }

            // Return average log-likelihood for this bandwidth
            log_lik_sum / n_points as f64
        })
        .collect();

    log_likelihoods
}

// Macro to generate exports.
// This ensures exported functions are registered with R.
// See corresponding C code in `entrypoint.c`.
extendr_module! {
    mod geodensity;
    fn geodesic_kde_rust;
    fn geodesic_kde_adaptive_rust;
    fn bandwidth_loocv_evaluate;
}
