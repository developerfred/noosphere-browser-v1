#!/bin/bash
# Noosphere Browser - Universal Build Script
# Works with or without Zig installed

set -e

REPO="developerfred/noosphere-browser-v1"
VERSION="${VERSION:-latest}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[BUILD]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Detect OS and architecture
detect_os() {
    case "$(uname -s)" in
        Linux*)     echo "linux" ;;
        Darwin*)    echo "macos" ;;
        CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
        *)          error "Unsupported OS: $(uname -s)"; exit 1 ;;
    esac
}

detect_arch() {
    case "$(uname -m)" in
        x86_64)     echo "x86_64" ;;
        aarch64|arm64) echo "aarch64" ;;
        armv7l)     echo "armv7" ;;
        i386|i686)  echo "x86" ;;
        *)          error "Unsupported architecture: $(uname -m)"; exit 1 ;;
    esac
}

# Check if Zig is installed
check_zig() {
    if command -v zig > /dev/null 2>&1; then
        log "Zig found: $(zig version)"
        return 0
    else
        warn "Zig not found"
        return 1
    fi
}

# Build with Zig
build_with_zig() {
    local target=$1
    log "Building for $target with Zig..."
    
    if ! check_zig; then
        error "Zig is required for building"
        return 1
    fi
    
    # Create output directory
    mkdir -p release
    
    # Build for target
    case "$target" in
        linux-x86_64)
            zig build -freestanding -target x86_64-linux-gnu -O ReleaseFast
            cp zig-out/bin/noosphere release/noosphere-x86_64-linux
            ;;
        linux-aarch64)
            zig build -freestanding -target aarch64-linux-gnu -O ReleaseFast
            cp zig-out/bin/noosphere release/noosphere-aarch64-linux
            ;;
        linux-armv7)
            zig build -freestanding -target armv7-linux-gnueabihf -O ReleaseFast
            cp zig-out/bin/noosphere release/noosphere-armv7-linux
            ;;
        macos-x86_64)
            zig build -freestanding -target x86_64-apple-darwin -O ReleaseFast
            cp zig-out/bin/noosphere release/noosphere-x86_64-macos
            ;;
        macos-aarch64)
            zig build -freestanding -target aarch64-apple-darwin -O ReleaseFast
            cp zig-out/bin/noosphere release/noosphere-aarch64-macos
            ;;
        windows-x86_64)
            zig build -freestanding -target x86_64-windows-gnu -O ReleaseFast
            cp zig-out/bin/noosphere.exe release/noosphere-x86_64-windows.exe
            ;;
        *)
            error "Unknown target: $target"
            return 1
            ;;
    esac
    
    log "Built: release/$(ls release/ | grep noosphere | tail -1)"
}

# Download pre-built binary
download_binary() {
    local os=$1
    local arch=$2
    local target_name=$3
    
    local filename=""
    case "$os-$arch" in
        linux-x86_64) filename="noosphere-x86_64-linux" ;;
        linux-aarch64) filename="noosphere-aarch64-linux" ;;
        linux-armv7) filename="noosphere-armv7-linux" ;;
        macos-x86_64) filename="noosphere-x86_64-macos" ;;
        macos-aarch64) filename="noosphere-aarch64-macos" ;;
        windows-x86_64) filename="noosphere-x86_64-windows.exe" ;;
        *) return 1 ;;
    esac
    
    log "Downloading pre-built binary for $os-$arch..."
    
    local url="https://github.com/$REPO/releases/download/$VERSION/$filename"
    
    mkdir -p release
    
    if command -v curl > /dev/null 2>&1; then
        curl -L --fail -o "release/$filename" "$url" 2>/dev/null && return 0
    fi
    
    return 1
}

# Build all platforms
build_all() {
    log "Building all platforms..."
    
    if check_zig; then
        log "Building with Zig..."
        build_with_zig "linux-x86_64" || warn "Linux x86_64 build failed"
        build_with_zig "linux-aarch64" || warn "Linux ARM64 build failed"
        build_with_zig "linux-armv7" || warn "Linux ARMv7 build failed"
        build_with_zig "macos-x86_64" || warn "macOS Intel build failed"
        build_with_zig "macos-aarch64" || warn "macOS Apple Silicon build failed"
        build_with_zig "windows-x86_64" || warn "Windows build failed"
    else
        # Try downloading pre-built
        local os=$(detect_os)
        local arch=$(detect_arch)
        download_binary "$os" "$arch" || warn "No pre-built binary available for $os-$arch"
    fi
}

# Main
main() {
    log "Noosphere Browser Build System"
    echo ""
    
    local os=$(detect_os)
    local arch=$(detect_arch)
    log "Detected: $os ($arch)"
    echo ""
    
    case "${1:-}" in
        --all)
            build_all
            ;;
        --current)
            log "Building for current platform: $os-$arch"
            if check_zig; then
                case "$os" in
                    linux)
                        build_with_zig "linux-x86_64" || build_with_zig "linux-aarch64"
                        ;;
                    macos)
                        if [ "$arch" = "x86_64" ]; then
                            build_with_zig "macos-x86_64"
                        else
                            build_with_zig "macos-aarch64"
                        fi
                        ;;
                    windows)
                        build_with_zig "windows-x86_64"
                        ;;
                esac
            else
                download_binary "$os" "$arch" || error "Cannot build or download"
            fi
            ;;
        --linux-x86_64) build_with_zig "linux-x86_64" ;;
        --linux-aarch64) build_with_zig "linux-aarch64" ;;
        --linux-armv7) build_with_zig "linux-armv7" ;;
        --macos-intel) build_with_zig "macos-x86_64" ;;
        --macos-apple) build_with_zig "macos-aarch64" ;;
        --windows) build_with_zig "windows-x86_64" ;;
        --docker)
            log "Building with Docker..."
            docker build -t noosphere-builder .
            ;;
        -h|--help)
            echo "Usage: $0 [target]"
            echo ""
            echo "Targets:"
            echo "  --all          Build all platforms (requires Zig)"
            echo "  --current      Build for current platform"
            echo "  --linux-x86_64    Linux x86_64"
            echo "  --linux-aarch64   Linux ARM64 (Raspberry Pi 4)"
            echo "  --linux-armv7    Linux ARMv7 (Raspberry Pi 3)"
            echo "  --macos-intel     macOS Intel"
            echo "  --macos-apple     macOS Apple Silicon"
            echo "  --windows         Windows x86_64"
            echo "  --docker          Build with Docker"
            echo "  -h, --help        Show this help"
            ;;
        *)
            error "Unknown target: ${1:-}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
    
    echo ""
    if [ -d release ]; then
        log "Build artifacts:"
        ls -la release/ 2>/dev/null || true
    fi
}

main "$@"
