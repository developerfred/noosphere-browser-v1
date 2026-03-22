#!/bin/bash
# Noosphere Browser - Universal Installer
# Supports: Linux, macOS, Windows, Raspberry Pi

set -e

REPO="developerfred/noosphere-browser-v1"
VERSION="${VERSION:-latest}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
FORCE="${FORCE:-false}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[NOOSPHERE]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Linux*)     echo "linux" ;;
        Darwin*)    echo "macos" ;;
        CYGWIN*|MINGW*|MSYS*) echo="windows" ;;
        *)          error "Unsupported OS: $(uname -s)" ;;
    esac
}

# Detect architecture
detect_arch() {
    case "$(uname -m)" in
        x86_64)     echo "x86_64" ;;
        aarch64|arm64) echo "aarch64" ;;
        armv7l)     echo "armv7" ;;
        i386|i686)  echo "x86" ;;
        *)          error "Unsupported architecture: $(uname -m)" ;;
    esac
}

# Map to release filenames
get_filename() {
    local os=$1
    local arch=$2
    
    case "$os" in
        linux)  
            case "$arch" in
                x86_64) echo "noosphere-x86_64-linux" ;;
                aarch64) echo "noosphere-aarch64-linux" ;;
                armv7) echo "noosphere-armv7-linux" ;;
                *) echo "" ;;
            esac
            ;;
        macos)  
            case "$arch" in
                x86_64) echo "noosphere-x86_64-macos" ;;
                aarch64) echo "noosphere-aarch64-macos" ;;
                *) echo "" ;;
            esac
            ;;
        windows) 
            echo "noosphere-x86_64-windows.exe"
            ;;
        *)     echo "" ;;
    esac
}

# Get download URL
get_download_url() {
    local filename=$1
    local version=$2
    
    if [ "$version" = "latest" ]; then
        echo "https://github.com/${REPO}/releases/latest/download/${filename}"
    else
        echo "https://github.com/${REPO}/releases/download/${VERSION}/${filename}"
    fi
}

# Download file
download() {
    local url=$1
    local dest=$2
    
    log "Downloading from $url..."
    
    if command -v curl > /dev/null 2>&1; then
        curl -L --fail --progress-bar -o "$dest" "$url"
    elif command -v wget > /dev/null 2>&1; then
        wget -O "$dest" "$url"
    else
        error "Neither curl nor wget found"
    fi
}

# Install binary
install_binary() {
    local filename=$1
    local dest="$INSTALL_DIR/noosphere"
    
    [ "$os" = "windows" ] && dest="${dest}.exe"
    
    # Check if exists
    if [ -f "$dest" ] && [ "$FORCE" != "true" ]; then
        warn "Noosphere already installed at $dest"
        read -p "Overwrite? [y/N] " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
    fi
    
    mkdir -p "$INSTALL_DIR"
    mv "$filename" "$dest"
    chmod +x "$dest"
    
    log "Installed to $dest"
}

# Add to PATH
add_to_path() {
    local shell_rc=""
    
    case "$(basename "$SHELL")" in
        bash) shell_rc="$HOME/.bashrc" ;;
        zsh)  shell_rc="$HOME/.zshrc" ;;
        fish) shell_rc="$HOME/.config/fish/config.fish" ;;
        *)   shell_rc="$HOME/.profile" ;;
    esac
    
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        echo "export PATH=\"\$PATH:$INSTALL_DIR\"" >> "$shell_rc"
        log "Added $INSTALL_DIR to PATH in $shell_rc"
        log "Restart shell or run: source $shell_rc"
    fi
}

# Build from source
build_from_source() {
    log "Building from source..."
    
    if command -v zig > /dev/null 2>&1; then
        log "Using Zig..."
        make build
        return $?
    elif command -v gcc > /dev/null 2>&1 || command -v clang > /dev/null 2>&1; then
        log "Using C fallback..."
        if [ "$os" = "windows" ]; then
            gcc -O2 -o noosphere.exe c/main.c
        else
            gcc -O2 -o noosphere c/main.c
        fi
        return $?
    else
        error "No Zig or C compiler found. Please install Zig from https://ziglang.org"
    fi
}

# Main
main() {
    log "Noosphere Browser Installer v1.0"
    echo ""
    
    local os=$(detect_os)
    local arch=$(detect_arch)
    
    log "Detected: $os ($arch)"
    echo ""
    
    local filename=$(get_filename "$os" "$arch")
    
    if [ -z "$filename" ]; then
        warn "No pre-built binary for $os-$arch"
        echo "Will try to build from source..."
        build_from_source
        exit $?
    fi
    
    local download_url=$(get_download_url "$filename" "$VERSION")
    local tmpfile=$(mktemp)
    
    log "Installing $filename..."
    
    # Try download
    if download "$download_url" "$tmpfile"; then
        install_binary "$tmpfile"
        add_to_path
    else
        warn "Download failed"
        echo ""
        echo "Options:"
        echo "1. Build from source (requires Zig or gcc):"
        echo "   git clone https://github.com/${REPO}.git"
        echo "   cd noosphere-browser-v1"
        echo "   make build"
        echo ""
        echo "2. Download manually:"
        echo "   https://github.com/${REPO}/releases"
        echo ""
        rm -f "$tmpfile"
        exit 1
    fi
    
    echo ""
    log "Done! Run 'noosphere --help' to get started."
}

main "$@"
