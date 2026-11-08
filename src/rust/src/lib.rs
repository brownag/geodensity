use extendr_api::prelude::*;
use geo::prelude::*;
use geo::Point;
use rayon::prelude::*;

/// Earth radius in km (geo's mean radius, 6371008.8 m)
const EARTH_RADIUS_KM: f64 = 6371.0088;

/// Search half-widths in degrees for a kernel cutoff of `cutoff_km` at latitude `lat_deg`.
///
/// Returns (longitude half-width, latitude half-width). The latitude half-width is
/// cutoff / (R * pi / 180). The longitude half-width is the exact extent of a circle of
/// angular radius r = cutoff / R around (lat, lon): asin(sin r / cos lat). If sin r / cos lat
/// is at least 1, the circle encloses a pole and every longitude is in range (180 degrees).
/// The cos guard only widens the bound: below the guard, the bound is the full 180 degrees.
fn search_half_widths_deg(cutoff_km: f64, lat_deg: f64) -> (f64, f64) {
    let km_per_lat = EARTH_RADIUS_KM * std::f64::consts::PI / 180.0;
    let lat_hw = cutoff_km / km_per_lat;
    let r = cutoff_km / EARTH_RADIUS_KM;
    let cos_lat = lat_deg.to_radians().cos().abs();
    let lon_hw = if cos_lat <= 1e-9 {
        180.0
    } else {
        let s = r.sin() / cos_lat;
        if s >= 1.0 { 180.0 } else { s.asin().to_degrees() }
    };
    (lon_hw, lat_hw)
}

/// Geodesic kernel density estimate on a grid, with grid-based spatial indexing.
/// The grid points are computed in parallel with Rayon.
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

    // 2. Spatial index sizing. Search half-widths are computed per grid point from that
    // point's own latitude (search_half_widths_deg). The cell size covers the largest
    // half-width over the grid, so per-point cell offsets stay bounded.
    let cutoff_km = 3.0 * bandwidth_km;
    let max_half_width_deg = grid_y
        .iter()
        .map(|&gy| search_half_widths_deg(cutoff_km, gy).0)
        .fold(search_half_widths_deg(cutoff_km, 0.0).1, f64::max);

    // Index cell size: 1.5x the largest half-width
    // Bounded at [0.1 degrees, 45 degrees] to prevent pathological cases
    let index_cell_size = (max_half_width_deg * 1.5)
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

    // 5. Parallel iteration over the output grid (pixels)
    let densities: Vec<f64> = grid_x
        .par_iter()
        .zip(grid_y.par_iter())
        .map(|(&gx, &gy)| {
            let grid_point = Point::new(gx, gy);
            let mut sum = 0.0;
            let mut visit = |idx: usize| {
                let point = &data_points[idx];
                let dist_meters = point.haversine_distance(&grid_point);
                let dist_km = dist_meters / 1000.0;
                // Gaussian kernel with 3-sigma cutoff for efficiency
                if dist_km < (bandwidth_km * 3.0) {
                    let exponent = -0.5 * (dist_km / bandwidth_km).powi(2);
                    sum += exponent.exp();
                }
            };

            let (hw_lon, hw_lat) = search_half_widths_deg(cutoff_km, gy);
            if hw_lon >= 90.0 {
                // Circle encloses a pole: every longitude is in range. Scan all points once.
                // (A wide window would reach one point under both its natural and wrapped keys.)
                for idx in 0..data_points.len() {
                    visit(idx);
                }
            } else {
                let grid_x_key = (gx / index_cell_size).floor() as i32;
                let grid_y_key = (gy / index_cell_size).floor() as i32;
                let ox = (hw_lon / index_cell_size).ceil() as i32;
                let oy = (hw_lat / index_cell_size).ceil() as i32;

                // Search nearby grid cells within the per-point search box
                for dx in -ox..=ox {
                    for dy in -oy..=oy {
                        let cell_key = (grid_x_key + dx, grid_y_key + dy);
                        if let Some(point_indices) = grid_index.get(&cell_key) {
                            for &idx in point_indices {
                                visit(idx);
                            }
                        }
                    }
                }
            }
            sum
        })
        .collect();

    // Normalize to probability density: divide by 2*pi*bw^2*n (after accumulation)
    let norm = 2.0 * std::f64::consts::PI * bandwidth_km * bandwidth_km * x_coords.len() as f64;
    densities.iter().map(|&d| d / norm).collect()
}

/// Adaptive geodesic kernel density estimate. Per-cell bandwidth is
/// bw_i = min + (pilot - min) / (1 + sqrt(d_i / d_max)), where d_i is the pilot density
/// at cell i and d_max is the maximum pilot density over the grid.
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
    // Adaptive scaling: bandwidth_i = min + (pilot - min) / (1 + (density_i / ref_density)^lambda)
    // where lambda = 0.5 (sqrt) controls adaptation strength and ref_density is the pilot density max
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

    // Index and search extent use the pilot bandwidth. Every per-cell cutoff 3*scale is
    // at most 3*pilot, because scale <= pilot_bandwidth_km when min < pilot.
    let cutoff_km = 3.0 * pilot_bandwidth_km;
    let max_half_width_deg = grid_y
        .iter()
        .map(|&gy| search_half_widths_deg(cutoff_km, gy).0)
        .fold(search_half_widths_deg(cutoff_km, 0.0).1, f64::max);
    let index_cell_size = (max_half_width_deg * 1.5).max(0.1).min(45.0);

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


    // Parallel computation using scaled bandwidths
    let densities: Vec<f64> = grid_x
        .par_iter()
        .zip(grid_y.par_iter())
        .zip(scales.par_iter())
        .map(|((&gx, &gy), &bandwidth_km)| {
            let grid_point = geo::Point::new(gx, gy);
            let mut sum = 0.0;
            let mut visit = |idx: usize| {
                let point = &data_points[idx];
                let dist_meters = point.haversine_distance(&grid_point);
                let dist_km = dist_meters / 1000.0;
                if dist_km < (bandwidth_km * 3.0) {
                    let exponent = -0.5 * (dist_km / bandwidth_km).powi(2);
                    sum += exponent.exp();
                }
            };

            let (hw_lon, hw_lat) = search_half_widths_deg(cutoff_km, gy);
            if hw_lon >= 90.0 {
                // Circle encloses a pole: every longitude is in range. Scan all points once.
                // (A wide window would reach one point under both its natural and wrapped keys.)
                for idx in 0..data_points.len() {
                    visit(idx);
                }
            } else {
                let grid_x_key = (gx / index_cell_size).floor() as i32;
                let grid_y_key = (gy / index_cell_size).floor() as i32;
                let ox = (hw_lon / index_cell_size).ceil() as i32;
                let oy = (hw_lat / index_cell_size).ceil() as i32;

                // Search nearby grid cells within the per-point search box
                for dx in -ox..=ox {
                    for dy in -oy..=oy {
                        let cell_key = (grid_x_key + dx, grid_y_key + dy);
                        if let Some(point_indices) = grid_index.get(&cell_key) {
                            for &idx in point_indices {
                                visit(idx);
                            }
                        }
                    }
                }
            }
            sum
        })
        .collect();

    // Normalize to probability density: divide by 2*pi*scale_i^2*n per cell (after accumulation)
    let n = x_coords.len() as f64;
    densities
        .iter()
        .zip(scales.iter())
        .map(|(&d, &s)| d / (2.0 * std::f64::consts::PI * s * s * n))
        .collect()
}

/// Leave-one-out CV log-likelihood for each bandwidth (serial; O(n^2) distance matrix).
#[extendr]
fn bandwidth_loocv_evaluate(
    x_coords: Vec<f64>,
    y_coords: Vec<f64>,
    bandwidths: Vec<f64>,
) -> Vec<f64> {
    let n_points = x_coords.len();

    // Precompute all pairwise distances (expensive but needed for LOOCV)
    let mut distances = vec![vec![0.0; n_points]; n_points];

    for i in 0..n_points {
        for j in (i + 1)..n_points {
            let dist = geo::Point::new(x_coords[i], y_coords[i])
                .haversine_distance(&geo::Point::new(x_coords[j], y_coords[j])) / 1000.0;
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

            // 2D Gaussian normalization (planar approximation): 1 / (2 * pi * bw^2).
            // No 1/n factor: intensity, not probability density (D10).
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
