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
    let lon_hw = if cos_lat <= 1e-9 || r >= std::f64::consts::FRAC_PI_2 {
        180.0
    } else {
        let s = r.sin() / cos_lat;
        if s >= 1.0 { 180.0 } else { s.asin().to_degrees() }
    };
    (lon_hw, lat_hw)
}

/// Index cell size in degrees: 1.5x the largest search half-width over the grid latitudes at
/// `cutoff_km`, bounded to [0.1, 45] degrees to prevent pathological cases.
fn index_cell_size(grid_y: &[f64], cutoff_km: f64) -> f64 {
    let max_half_width_deg = grid_y
        .iter()
        .map(|&gy| search_half_widths_deg(cutoff_km, gy).0)
        .filter(|&hw| hw < 90.0)
        .fold(search_half_widths_deg(cutoff_km, 0.0).1, f64::max);
    (max_half_width_deg * 1.5)
        .max(0.1)
        .min(45.0)
}

/// Grid-cell index of the points with dateline-aware keys: each point is stored under its
/// natural key and, if |x| > 90, also under its key wrapped by 360 degrees.
fn build_spatial_index(
    data_points: &[Point<f64>],
    cell_size: f64,
) -> std::collections::HashMap<(i32, i32), Vec<usize>> {
    let mut grid_index: std::collections::HashMap<(i32, i32), Vec<usize>> =
        std::collections::HashMap::new();

    for (idx, point) in data_points.iter().enumerate() {
        let x_key = (point.x() / cell_size).floor() as i32;
        let y_key = (point.y() / cell_size).floor() as i32;

        grid_index.entry((x_key, y_key)).or_insert_with(Vec::new).push(idx);

        // Wrap positive values near +180 to negative equivalent, and vice versa
        if point.x() > 90.0 {
            let wrapped_x = point.x() - 360.0;
            let wrapped_key = (wrapped_x / cell_size).floor() as i32;
            grid_index.entry((wrapped_key, y_key)).or_insert_with(Vec::new).push(idx);
        } else if point.x() < -90.0 {
            let wrapped_x = point.x() + 360.0;
            let wrapped_key = (wrapped_x / cell_size).floor() as i32;
            grid_index.entry((wrapped_key, y_key)).or_insert_with(Vec::new).push(idx);
        }
    }
    grid_index
}

fn visit_candidate_points<F: FnMut(usize)>(
    gx: f64,
    gy: f64,
    cutoff_km: f64,
    data_points: &[Point<f64>],
    grid_index: &std::collections::HashMap<(i32, i32), Vec<usize>>,
    index_cell_size: f64,
    mut visit: F,
) {
    let (hw_lon, hw_lat) = search_half_widths_deg(cutoff_km, gy);
    if hw_lon >= 90.0 {
        for idx in 0..data_points.len() {
            visit(idx);
        }
    } else {
        let gx_wrapped = (gx + 180.0).rem_euclid(360.0) - 180.0;
        let grid_x_key = (gx_wrapped / index_cell_size).floor() as i32;
        let grid_y_key = (gy / index_cell_size).floor() as i32;
        let ox = (hw_lon / index_cell_size).ceil() as i32;
        let oy = (hw_lat / index_cell_size).ceil() as i32;

        for dx in -ox..=ox {
            for dy in -oy..=oy {
                if let Some(point_indices) = grid_index.get(&(grid_x_key + dx, grid_y_key + dy)) {
                    for &idx in point_indices {
                        visit(idx);
                    }
                }
            }
        }
    }
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
    let index_cell_size = index_cell_size(&grid_y, cutoff_km);

    // 3. Build spatial grid index with dynamic cell size
    let grid_index = build_spatial_index(&data_points, index_cell_size);

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

            visit_candidate_points(
                gx,
                gy,
                cutoff_km,
                &data_points,
                &grid_index,
                index_cell_size,
                &mut visit,
            );
            sum
        })
        .collect();

    // Normalize to probability density: divide by 2*pi*bw^2*n (after accumulation)
    let norm = 2.0 * std::f64::consts::PI * bandwidth_km * bandwidth_km * x_coords.len() as f64;
    densities.iter().map(|&d| d / norm).collect()
}

fn compute_adaptive_scales(
    pilot_density: &[f64],
    pilot_bw: f64,
    min_bw: f64,
    scaling: &str,
) -> Vec<f64> {
    let reference_density = pilot_density.iter().copied().fold(0.0, f64::max);
    pilot_density
        .iter()
        .map(|&d| {
            let density_ratio = if reference_density > 0.0 {
                d / reference_density
            } else {
                0.0
            };
            let scale_factor = match scaling {
                "linear_sqrt" => 1.0 - density_ratio.sqrt(),
                _ => 1.0 / (1.0 + density_ratio.sqrt()),
            };
            min_bw + (pilot_bw - min_bw) * scale_factor
        })
        .collect()
}

/// Adaptive geodesic KDE: method is "balloon" or "sample_point"; scaling is
/// "ratio" or "linear_sqrt".
#[extendr]
fn geodesic_kde_adaptive_rust(
    x_coords: Vec<f64>,
    y_coords: Vec<f64>,
    grid_x: Vec<f64>,
    grid_y: Vec<f64>,
    pilot_bandwidth_km: f64,
    min_bandwidth_km: f64,
    method: &str,
    scaling: &str,
) -> Vec<f64> {
    let sample_point = method == "sample_point";
    let (pilot_x, pilot_y) = if sample_point {
        (x_coords.clone(), y_coords.clone())
    } else {
        (grid_x.clone(), grid_y.clone())
    };
    let pilot_density = geodesic_kde_rust(
        x_coords.clone(),
        y_coords.clone(),
        pilot_x,
        pilot_y,
        pilot_bandwidth_km,
    );
    let scales = compute_adaptive_scales(
        &pilot_density,
        pilot_bandwidth_km,
        min_bandwidth_km,
        scaling,
    );
    let data_points: Vec<_> = x_coords
        .iter()
        .zip(y_coords.iter())
        .map(|(&x, &y)| geo::Point::new(x, y))
        .collect();

    let cutoff_km = 3.0 * pilot_bandwidth_km;
    let index_cell_size = index_cell_size(&grid_y, cutoff_km);
    let grid_index = build_spatial_index(&data_points, index_cell_size);
    let point_norms: Vec<f64> = scales
        .iter()
        .map(|&bw| 1.0 / (2.0 * std::f64::consts::PI * bw * bw * x_coords.len() as f64))
        .collect();


    let densities: Vec<f64> = grid_x
        .par_iter()
        .zip(grid_y.par_iter())
        .enumerate()
        .map(|(cell_idx, (&gx, &gy))| {
            let grid_point = geo::Point::new(gx, gy);
            let mut sum = 0.0;
            let mut visit = |idx: usize| {
                let point = &data_points[idx];
                let dist_meters = point.haversine_distance(&grid_point);
                let dist_km = dist_meters / 1000.0;
                let scale_idx = if sample_point { idx } else { cell_idx };
                let bandwidth_km = scales[scale_idx];
                if dist_km < 3.0 * bandwidth_km {
                    let kernel = (-0.5 * (dist_km / bandwidth_km).powi(2)).exp();
                    if sample_point {
                        sum += kernel * point_norms[idx];
                    } else {
                        sum += kernel;
                    }
                }
            };

            visit_candidate_points(
                gx,
                gy,
                cutoff_km,
                &data_points,
                &grid_index,
                index_cell_size,
                &mut visit,
            );
            if sample_point {
                sum
            } else {
                sum / (2.0 * std::f64::consts::PI * scales[cell_idx].powi(2)
                    * x_coords.len() as f64)
            }
        })
        .collect();
    densities
}

/// Leave-one-out CV log-likelihood for each bandwidth (serial; O(n * B) memory).
#[extendr]
fn bandwidth_loocv_evaluate(
    x_coords: Vec<f64>,
    y_coords: Vec<f64>,
    bandwidths: Vec<f64>,
) -> Vec<f64> {
    let n_points = x_coords.len();

    let mut densities = vec![vec![0.0f64; n_points]; bandwidths.len()];
    let norms: Vec<f64> = bandwidths
        .iter()
        .map(|&bw| 1.0 / (2.0 * std::f64::consts::PI * bw * bw))
        .collect();

    for i in 0..n_points {
        for j in (i + 1)..n_points {
            let dist_km = geo::Point::new(x_coords[i], y_coords[i])
                .haversine_distance(&geo::Point::new(x_coords[j], y_coords[j]))
                / 1000.0;
            for (b, &bw) in bandwidths.iter().enumerate() {
                let k = norms[b] * (-0.5 * (dist_km / bw).powi(2)).exp();
                densities[b][i] += k;
                densities[b][j] += k;
            }
        }
    }

    densities
        .iter()
        .map(|density| {
            density.iter().map(|&d| d.max(1e-10).ln()).sum::<f64>() / n_points as f64
        })
        .collect()
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
