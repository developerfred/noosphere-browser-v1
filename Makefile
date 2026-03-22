# Noosphere Browser Makefile
# Multi-platform build with Zig

.PHONY: all build test clean install help
.PHONY: build-linux build-macos build-windows build-pi

# Check for Zig
ZIG := $(shell command -v zig 2>/dev/null || echo "")
ZIG_VERSION := $(shell zig version 2>/dev/null || echo "not found")

.PHONY: check-zig
check-zig:
ifndef ZIG
	@echo "⚠️  Zig not found - only pre-built downloads available"
	@echo "   Install from: https://ziglang.org/download/"
	@echo ""
	@echo "   Or download pre-built binaries from:"
	@echo "   https://github.com/developerfred/noosphere-browser-v1/releases"
	@false
endif
	@echo "✓ Zig $(ZIG_VERSION)"

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
	@cp zig-out/bin/noosphere release/noosphere-x86_64-linux 2>/dev/null || cp zig-out/bin/noosphere.exe release/noosphere-x86_64-linux
	@echo "✓ release/noosphere-x86_64-linux"

build-linux-arm64: check-zig
	@echo "Building Noosphere for Linux ARM64 (Raspberry Pi 4)..."
	@zig build -Doptimize=ReleaseFast -target aarch64-linux-gnu
	@mkdir -p release/
	@cp zig-out/bin/noosphere release/noosphere-aarch64-linux 2>/dev/null || cp zig-out/bin/noosphere.exe release/noosphere-aarch64-linux
	@echo "✓ release/noosphere-aarch64-linux"

build-linux-armv7: check-zig
	@echo "Building Noosphere for Linux ARMv7 (Raspberry Pi 3)..."
	@zig build -Doptimize=ReleaseFast -target armv7-linux-gnueabihf
	@mkdir -p release/
	@cp zig-out/bin/noosphere release/noosphere-armv7-linux 2>/dev/null || cp zig-out/bin/noosphere.exe release/noosphere-armv7-linux
	@echo "✓ release/noosphere-armv7-linux"

## macOS builds
build-macos: build-macos-intel build-macos-apple

build-macos-intel: check-zig
	@echo "Building Noosphere for macOS Intel..."
	@zig build -Doptimize=ReleaseFast -target x86_64-macos
	@mkdir -p release/
	@cp zig-out/bin/noosphere release/noosphere-x86_64-macos
	@echo "✓ release/noosphere-x86_64-macos"

build-macos-apple: check-zig
	@echo "Building Noosphere for macOS Apple Silicon..."
	@zig build -Doptimize=ReleaseFast -target aarch64-macos
	@mkdir -p release/
	@cp zig-out/bin/noosphere release/noosphere-aarch64-macos
	@echo "✓ release/noosphere-aarch64-macos"

## Windows builds
build-windows: check-zig
	@echo "Building Noosphere for Windows..."
	@zig build -Doptimize=ReleaseFast -target x86_64-windows-gnu
	@mkdir -p release/
	@cp zig-out/bin/noosphere.exe release/noosphere-x86_64-windows.exe
	@echo "✓ release/noosphere-x86_64-windows.exe"

## All targets
build-all: check-zig build-linux build-macos build-windows
	@echo ""
	@echo "✅ All builds complete!"
	@echo ""
	@ls -la release/ 2>/dev/null || ls -la zig-out/bin/

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
	@echo "✓ Done"

## Install system-wide
install: build
	@echo "Installing Noosphere..."
	@mkdir -p $(DESTDIR)/usr/local/bin
	@cp zig-out/bin/noosphere $(DESTDIR)/usr/local/bin/ 2>/dev/null || \
	 cp zig-out/bin/noosphere.exe $(DESTDIR)/usr/local/bin/noosphere
	@chmod +x $(DESTDIR)/usr/local/bin/noosphere
	@echo "✓ Installed to /usr/local/bin/noosphere"

## Development
dev: check-zig
	@echo "Building in debug mode..."
	@zig build -Doptimize=Debug

## Checksums
checksums:
	@echo "Creating checksums..."
	@mkdir -p release
	@cd release && \
		for f in noosphere-*; do \
			$(shell which sha256sum > /dev/null && echo "sha256sum" || echo "shasum -a 256") $$f > $$f.sha256; \
		done
	@echo "✓ Checksums created"
	@cat release/*.sha256 2>/dev/null || ls -la release/

## Package for release
package: build-all checksums
	@echo "Creating release package..."
	@mkdir -p release/pkg
	@cd release && \
		cp ../README.md . 2>/dev/null || true && \
		cp ../LICENSE . 2>/dev/null || true && \
		cp ../install.sh . 2>/dev/null || true
	@cd release && \
		tar -czf ../noosphere-all-platforms.tar.gz noosphere-* && \
		zip -r ../noosphere-all-platforms.zip noosphere-* 2>/dev/null || true
	@echo "✓ Package created: noosphere-all-platforms.tar.gz"
	@ls -la *.tar.gz *.zip 2>/dev/null || true

## Help
help:
	@echo "Noosphere Browser Build System"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  make build           Build for current platform"
	@echo "  make build-linux     Build for all Linux targets"
	@echo "  make build-macos     Build for all macOS targets"
	@echo "  make build-windows   Build for Windows"
	@echo "  make build-all       Build for ALL platforms (requires Zig)"
	@echo "  make pi              Build for Raspberry Pi (ARM64)"
	@echo "  make test            Run tests"
	@echo "  make clean          Remove build artifacts"
	@echo "  make install        Install system-wide"
	@echo "  make package        Create release package"
	@echo "  make checksums      Create checksums"
	@echo "  make dev            Build in debug mode"
	@echo ""
	@echo "Examples:"
	@echo "  make build-linux-x86    # Just Linux x86_64"
	@echo "  make build-linux-arm64  # Just ARM64 Linux (Pi 4)"
	@echo "  DESTDIR=/tmp make install"
	@echo ""
	@echo "Requirements:"
	@echo "  - Zig 0.13+ (https://ziglang.org)"
	@echo "  - For pre-built: https://github.com/developerfred/noosphere-browser-v1/releases"
