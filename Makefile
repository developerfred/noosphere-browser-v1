# Noosphere Browser Makefile
# Multi-platform build system using Zig

.PHONY: all build test clean install help
.PHONY: build-linux build-macos build-windows
.PHONY: build-arm64 build-x86 build-armv7

# Check if Zig is installed
ZIG := $(shell command -v zig 2>/dev/null || echo "")
ZIG_VERSION := $(shell zig version 2>/dev/null || echo "not found")

.PHONY: check-zig
check-zig:
ifndef ZIG
	$(error "Zig is not installed. Install from https://ziglang.org")
endif
	@echo "Zig version: $(ZIG_VERSION)"

## Build for current platform
build: check-zig
	@echo "Building Noosphere for $$(uname -s) ($$(uname -m))..."
	@zig build -Doptimize=ReleaseFast

## Linux builds
build-linux: build-linux-x86 build-linux-arm64 build-linux-armv7

build-linux-x86: check-zig
	@echo "Building Noosphere for Linux x86_64..."
	@zig build -Doptimize=ReleaseFast -target x86_64-linux-gnu
	@mkdir -p release/
	@cp zig-out/bin/noosphere release/noosphere-x86_64-linux
	@echo "Output: release/noosphere-x86_64-linux"

build-linux-arm64: check-zig
	@echo "Building Noosphere for Linux ARM64 (Raspberry Pi 4)..."
	@zig build -Doptimize=ReleaseFast -target aarch64-linux-gnu
	@mkdir -p release/
	@cp zig-out/bin/noosphere release/noosphere-aarch64-linux
	@echo "Output: release/noosphere-aarch64-linux"

build-linux-armv7: check-zig
	@echo "Building Noosphere for Linux ARMv7 (Raspberry Pi 3)..."
	@zig build -Doptimize=ReleaseFast -target armv7-linux-gnueabihf
	@mkdir -p release/
	@cp zig-out/bin/noosphere release/noosphere-armv7-linux
	@echo "Output: release/noosphere-armv7-linux"

## macOS builds
build-macos: build-macos-intel build-macos-apple

build-macos-intel: check-zig
	@echo "Building Noosphere for macOS Intel..."
	@zig build -Doptimize=ReleaseFast -target x86_64-macos
	@mkdir -p release/
	@cp zig-out/bin/noosphere release/noosphere-x86_64-macos
	@echo "Output: release/noosphere-x86_64-macos"

build-macos-apple: check-zig
	@echo "Building Noosphere for macOS Apple Silicon..."
	@zig build -Doptimize=ReleaseFast -target aarch64-macos
	@mkdir -p release/
	@cp zig-out/bin/noosphere release/noosphere-aarch64-macos
	@echo "Output: release/noosphere-aarch64-macos"

## Windows builds
build-windows: check-zig
	@echo "Building Noosphere for Windows..."
	@zig build -Doptimize=ReleaseFast -target x86_64-windows-gnu
	@mkdir -p release/
	@cp zig-out/bin/noosphere.exe release/noosphere-x86_64-windows.exe
	@echo "Output: release/noosphere-x86_64-windows.exe"

## All targets
build-all: build-linux build-macos build-windows
	@echo ""
	@echo "All builds complete. Binaries in release/:"
	@ls -la release/

## Quick Raspberry Pi build
pi: build-linux-arm64
	@echo "Done! Binary: release/noosphere-aarch64-linux"

## Test
test: check-zig
	@echo "Running tests..."
	@zig build test

## Clean
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf zig-out/ release/
	@echo "Done."

## Install system-wide
install: build
	@echo "Installing Noosphere..."
	@mkdir -p $(DESTDIR)/usr/local/bin
	@cp zig-out/bin/noosphere $(DESTDIR)/usr/local/bin/
	@chmod +x $(DESTDIR)/usr/local/bin/noosphere
	@echo "Installed to /usr/local/bin/noosphere"

## Development
dev: check-zig
	@echo "Building in debug mode for current platform..."
	@zig build

## Release bundle
release: build-all
	@echo "Creating release bundle..."
	@cd release && shasum -a 256 * > checksums.txt
	@echo ""
	@echo "Release files in release/:"
	@ls -la release/

## Help
help:
	@echo "Noosphere Browser Build System"
	@echo ""
	@echo "Targets:"
	@echo "  make build           Build for current platform (debug)"
	@echo "  make build-linux    Build for all Linux targets"
	@echo "  make build-macos    Build for all macOS targets"
	@echo "  make build-windows  Build for Windows"
	@echo "  make build-all      Build for all platforms"
	@echo "  make pi             Build for Raspberry Pi (ARM64)"
	@echo "  make test           Run tests"
	@echo "  make clean          Remove build artifacts"
	@echo "  make install        Install system-wide"
	@echo "  make release        Create release bundle"
	@echo "  make dev            Build in debug mode"
	@echo ""
	@echo "Examples:"
	@echo "  make build-linux-x86      # Just x86_64 Linux"
	@echo "  make build-linux-arm64    # Just ARM64 Linux (Pi 4)"
	@echo "  DESTDIR=/tmp make install # Install to /tmp/usr/local/bin"
	@echo ""
	@echo "Requirements:"
	@echo "  - Zig 0.13+ (https://ziglang.org)"
