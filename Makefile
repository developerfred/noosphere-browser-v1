# Noosphere Browser Makefile
# Multi-platform build system

.PHONY: all build test clean install help
.PHONY: build-linux build-macos build-windows
.PHONY: build-arm64 build-x86 build-armv7

# Default target
all: build

## Build for current platform
build:
	@echo "Building Noosphere for $$(uname -s) ($$(uname -m))..."
	@zig build -freestanding -target $$(uname -m)-linux-gnu 2>/dev/null || \
	@zig build -freestanding -target $$(uname -m)-apple-darwin 2>/dev/null || \
	@echo "Please specify target explicitly: make build-linux"

## Linux builds
build-linux: build-linux-x86 build-linux-arm64 build-linux-armv7

build-linux-x86:
	@echo "Building Noosphere for Linux x86_64..."
	@zig build -freestanding -target x86_64-linux-gnu -O ReleaseFast
	@mv zig-out/bin/noosphere zig-out/bin/noosphere-x86_64-linux
	@echo "Output: zig-out/bin/noosphere-x86_64-linux"

build-linux-arm64:
	@echo "Building Noosphere for Linux ARM64 (Raspberry Pi 4)..."
	@zig build -freestanding -target aarch64-linux-gnu -O ReleaseFast
	@mv zig-out/bin/noosphere zig-out/bin/noosphere-aarch64-linux
	@echo "Output: zig-out/bin/noosphere-aarch64-linux"

build-linux-armv7:
	@echo "Building Noosphere for Linux ARMv7 (Raspberry Pi 3)..."
	@zig build -freestanding -target armv7-linux-gnueabihf -O ReleaseFast
	@mv zig-out/bin/noosphere zig-out/bin/noosphere-armv7-linux
	@echo "Output: zig-out/bin/noosphere-armv7-linux"

## macOS builds
build-macos: build-macos-intel build-macos-apple

build-macos-intel:
	@echo "Building Noosphere for macOS Intel..."
	@zig build -freestanding -target x86_64-apple-darwin -O ReleaseFast
	@mv zig-out/bin/noosphere zig-out/bin/noosphere-x86_64-macos
	@echo "Output: zig-out/bin/noosphere-x86_64-macos"

build-macos-apple:
	@echo "Building Noosphere for macOS Apple Silicon..."
	@zig build -freestanding -target aarch64-apple-darwin -O ReleaseFast
	@mv zig-out/bin/noosphere zig-out/bin/noosphere-aarch64-macos
	@echo "Output: zig-out/bin/noosphere-aarch64-apple-macos"

## Windows builds
build-windows:
	@echo "Building Noosphere for Windows..."
	@zig build -freestanding -target x86_64-windows-gnu -O ReleaseFast
	@mv zig-out/bin/noosphere.exe zig-out/bin/noosphere-x86_64-windows.exe
	@echo "Output: zig-out/bin/noosphere-x86_64-windows.exe"

## All targets
build-all: build-linux build-macos build-windows
	@echo ""
	@echo "All builds complete. Binaries in zig-out/bin/:"
	@ls -la zig-out/bin/

## Test
test:
	@echo "Running tests..."
	@zig build test

## Clean
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf zig-out/
	@echo "Done."

## Install system-wide
install:
	@echo "Installing Noosphere..."
	@mkdir -p $(DESTDIR)/usr/local/bin
	@cp zig-out/bin/noosphere $(DESTDIR)/usr/local/bin/
	@chmod +x $(DESTDIR)/usr/local/bin/noosphere
	@echo "Installed to /usr/local/bin/noosphere"

## Development
dev:
	@echo "Building in debug mode for current platform..."
	@zig build

## Release bundle
release: build-all
	@echo "Creating release bundle..."
	@mkdir -p release/
	@cp zig-out/bin/* release/
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
	@echo "  make build-linux     Build for all Linux targets"
	@echo "  make build-macos     Build for all macOS targets"
	@echo "  make build-windows   Build for Windows"
	@echo "  make build-all       Build for all platforms"
	@echo "  make test            Run tests"
	@echo "  make clean           Remove build artifacts"
	@echo "  make install         Install system-wide"
	@echo "  make release         Create release bundle"
	@echo "  make dev             Build in debug mode"
	@echo ""
	@echo "Examples:"
	@echo "  make build-linux-x86      # Just x86_64 Linux"
	@echo "  make build-linux-arm64    # Just ARM64 Linux (Pi 4)"
	@echo "  DESTDIR=/tmp make install # Install to /tmp/usr/local/bin"
