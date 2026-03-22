# Noosphere Browser Makefile
# Cross-platform build system

.PHONY: all build clean install test

# Default target
all: build

# Detect OS and architecture
OS := $(shell uname -s | tr '[:upper:]' '[:lower:]')
ARCH := $(shell uname -m)

# Override for cross-compilation
TARGET_OS ?= $(OS)
TARGET_ARCH ?= $(ARCH)

# Compiler options
CFLAGS := -O2 -Wall -Wextra -std=c11
LDFLAGS :=

# Output names
ifeq ($(TARGET_OS),windows)
    OUT := noosphere-$(TARGET_ARCH)-windows.exe
else ifeq ($(TARGET_OS),darwin)
    ifeq ($(TARGET_ARCH),arm64)
        OUT := noosphere-aarch64-macos
    else
        OUT := noosphere-x86_64-macos
    endif
else
    ifeq ($(TARGET_ARCH),aarch64)
        OUT := noosphere-aarch64-linux
    else
        OUT := noosphere-x86_64-linux
    endif
endif

# Build C fallback
build: c/main.c
	@echo "Building $(OUT) for $(TARGET_OS)/$(TARGET_ARCH)..."
	@mkdir -p release
	$(CC) $(CFLAGS) -o $(OUT) c/main.c
	@echo "✅ Built: $(OUT)"
	@ls -lh $(OUT)

# Cross-compile for Linux x86_64
build-linux-x86_64:
	$(MAKE) build TARGET_OS=linux TARGET_ARCH=x86_64 OUT=noosphere-x86_64-linux

# Cross-compile for Linux ARM64
build-linux-aarch64:
	$(MAKE) build TARGET_OS=linux TARGET_ARCH=aarch64 OUT=noosphere-aarch64-linux

# Cross-compile for macOS Intel
build-macos-x86_64:
	$(MAKE) build TARGET_OS=darwin TARGET_ARCH=x86_64 OUT=noosphere-x86_64-macos

# Cross-compile for macOS Apple Silicon
build-macos-aarch64:
	$(MAKE) build TARGET_OS=darwin TARGET_ARCH=arm64 OUT=noosphere-aarch64-macos

# Cross-compile for Windows
build-windows:
	$(MAKE) build TARGET_OS=windows TARGET_ARCH=x86_64 OUT=noosphere-x86_64-windows.exe

# Build all platforms (requires cross-compilers)
build-all: build-linux-x86_64 build-linux-aarch64 build-macos-x86_64 build-macos-aarch64 build-windows
	@echo "✅ All binaries built!"
	@ls -lh noosphere-*

# Install
install:
	@mkdir -p ~/.local/bin
	cp $(OUT) ~/.local/bin/noosphere
	@echo "✅ Installed to ~/.local/bin/noosphere"

# Clean
clean:
	rm -f noosphere-* release/*
	@echo "Cleaned build artifacts"

# Test
test: build
	@echo "Running tests..."
	./$(OUT) --version
	@echo "✅ Tests passed"

# Zig build (if Zig is installed)
build-zig:
	@if command -v zig &> /dev/null; then \
		zig build -Drelease-safe=true -Dstrip=true -p release; \
		echo "✅ Zig build complete"; \
	else \
		echo "⚠️  Zig not found, using C fallback"; \
		$(MAKE) build; \
	fi

# Help
help:
	@echo "Noosphere Browser Build System"
	@echo ""
	@echo "Targets:"
	@echo "  make build           - Build for current platform"
	@echo "  make build-all       - Build for all platforms"
	@echo "  make build-linux-x86_64    - Linux x86_64"
	@echo "  make build-linux-aarch64   - Linux ARM64"
	@echo "  make build-macos-x86_64    - macOS Intel"
	@echo "  make build-macos-aarch64   - macOS Apple Silicon"
	@echo "  make build-windows          - Windows"
	@echo "  make build-zig             - Build with Zig (if available)"
	@echo "  make install        - Install to ~/.local/bin"
	@echo "  make clean          - Remove build artifacts"
	@echo "  make test           - Test the binary"
	@echo ""
	@echo "Cross-compilation requires appropriate toolchains:"
	@echo "  Linux ARM64:  apt install gcc-aarch64-linux-gnu"
	@echo "  Windows:      apt install mingw-w64"
