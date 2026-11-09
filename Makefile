.PHONY: help build test install clean docs dev-setup check lint format vendor all readme

# Default target
help:
	@echo "geodensity - Development Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  make vendor      - Regenerate vendored Rust dependencies (src/rust/vendor.tar.xz)"
	@echo "  make build       - Build the package (cargo + R compilation)"
	@echo "  make test        - Run all tests (tinytest suite)"
	@echo "  make install     - Install package to library"
	@echo "  make load        - Load package in development mode"
	@echo "  make docs        - Generate roxygen2 documentation"
	@echo "  make readme      - Render README.Rmd to README.md and README.html"
	@echo "  make check       - Run R CMD check (full validation)"
	@echo "  make lint        - Check for code issues"
	@echo "  make format      - Auto-format code"
	@echo "  make clean       - Clean build artifacts"
	@echo "  make distclean   - Deep clean (removes compiled objects)"
	@echo "  make dev-setup   - Install development dependencies"
	@echo "  make all         - Build, document, and test"
	@echo ""

# Regenerate vendor.tar.xz from Cargo.lock (kept out of git but needed for distribution)
vendor:
	@echo "Regenerating vendored Rust dependencies..."
	@output=$$(mktemp); \
	if Rscript -e "if (!requireNamespace('rextendr', quietly=TRUE) || utils::packageVersion('rextendr') < '0.5.0') stop('make vendor requires rextendr >= 0.5.0'); rextendr::vendor_crates(path='src/rust')" >$$output 2>&1; then \
		grep -v "^Crate collection" $$output || true; \
		rm -f $$output; \
	else \
		status=$$?; grep -v "^Crate collection" $$output || true; \
		rm -f $$output; exit $$status; \
	fi
	@if [ -f "src/rust/vendor.tar.xz" ]; then \
		echo "[OK] vendor.tar.xz created successfully"; \
	else \
		echo "[FAIL] Failed to create vendor.tar.xz"; \
		exit 1; \
	fi

# Build the package (compile Rust, prepare R)
build: vendor
	@echo "Building geodensity package..."
	@echo "  - Compiling Rust backend..."
	@cd src/rust && cargo build --release
	@echo "  - Preparing R package..."
	@Rscript -e "devtools::load_all(quiet=TRUE); cat('Build successful!\n')"

# Run tests (exits nonzero on any failed expectation or zero expectations)
TEST_FILE ?= inst/tinytest/test_geodensity.R
test:
	@echo "Running test suite..."
	@Rscript -e "devtools::load_all(quiet=TRUE); r <- tinytest::run_test_file('$(TEST_FILE)'); d <- as.data.frame(r); n <- nrow(d); f <- sum(!d[['result']]); cat(sprintf('%d expectations, %d failed\n', n, f)); if (n == 0L || f > 0L) quit(status = 1L)"

# Install to library
install: docs
	@echo "Installing geodensity to library..."
	@Rscript -e "devtools::install()"
	@echo "Installation complete!"

# Load package in development mode
load:
	@echo "Loading package in development mode..."
	@Rscript -e "devtools::load_all(); cat('Package loaded!\n')"

# Generate roxygen2 documentation
docs:
	@echo "Generating roxygen2 documentation..."
	@Rscript -e "roxygen2::roxygenise()"
	@echo "Documentation generated!"

# Render README.Rmd to README.md and README.html
readme:
	@echo "Rendering README.Rmd..."
	@Rscript -e "rmarkdown::render('README.Rmd', output_format='all', quiet=TRUE); cat('README rendered to README.md and README.html\n')"

# Full R CMD check
check: vendor docs
	@echo "Running R CMD check..."
	@Rscript -e "devtools::check()"

# Lint code for issues
lint:
	@echo "Checking for code issues..."
	@Rscript -e "lintr::lint_dir('R/')" || true
	@echo "Lint check complete!"

# Auto-format code
format:
	@echo "Formatting code..."
	@Rscript -e "styler::style_dir('R/')"
	@Rscript -e "styler::style_dir('inst/tinytest/')"
	@echo "Formatting complete!"

# Setup development environment
dev-setup:
	@echo "Installing development dependencies..."
	@Rscript -e "pkgs <- c('devtools', 'roxygen2', 'lintr', 'styler', 'terra', 'tinytest'); missing <- setdiff(pkgs, rownames(installed.packages())); if(length(missing)) install.packages(missing, quiet=TRUE); cat(length(missing), 'packages installed\n')"
	@echo "Development environment ready!"

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf src/rust/target/debug/
	@rm -f src/*.o src/*.so src/*.dylib
	@rm -rf man/*.md
	@find . -name "*.Rhistory" -delete
	@echo "Clean complete!"

# Deep clean (removes release builds)
distclean: clean
	@echo "Deep cleaning..."
	@rm -rf src/rust/target/release/
	@rm -f src/rust/Cargo.lock
	@Rscript -e "devtools::clean_dll()" || true
	@echo "Distclean complete!"

# Build everything: compile, document, test
all: build docs test
	@echo ""
	@echo "=========================================="
	@echo "Build, documentation, and tests complete!"
	@echo "=========================================="
