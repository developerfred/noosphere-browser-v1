#!/bin/bash
# Noosphere Browser Installer
# Supports: Linux (x86_64, ARM), macOS (Intel, Apple Silicon), Windows

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
        Linux*)     OS="linux" ;;
        Darwin*)    OS="macos" ;;
        CYGWIN*|MINGW*|MSYS*) OS="windows" ;;
        *)          error "Unsupported OS: $(uname -s)" ;;
    esac
    echo "$OS"
}

# Detect architecture
detect_arch() {
    case "$(uname -m)" in
        x86_64)     ARCH="x86_64" ;;
        aarch64|arm64) ARCH="aarch64" ;;
        armv7l)     ARCH="armv7" ;;
        i386|i686)  ARCH="x86" ;;
        *)          error "Unsupported architecture: $(uname -m)" ;;
    esac
    echo "$ARCH"
}

# Map to release filenames
get_filename() {
    local os=$1
    local arch=$2
    
    case "$os" in
        linux)  echo "noosphere-${arch}-linux" ;;
        macos)  echo "noosphere-${arch}-macos" ;;
        windows) echo "noosphere-${arch}-windows.exe" ;;
    esac
}

# Download release
download_release() {
    local filename=$1
    local version=$2
    
    log "Downloading ${filename}..."
    
    # Try GitHub releases first
    local url="https://github.com/${REPO}/releases"
    
    if [ "$version" = "latest" ]; then
        url="${url}/download/${VERSION}"
    else
        url="${url}/download/v${VERSION}"
    fi
    
    # Construct download URL (using GitHub API to get redirect)
    local api_url="https://api.github.com/repos/${REPO}/releases/${VERSION}"
    
    # For now, construct direct URL based on common pattern
    local download_url="https://github.com/${REPO}/releases/download/${VERSION}/${filename}"
    
    # Create temp file
    local tmpfile=$(mktemp)
    
    if command -v curl > /dev/null; then
        curl -L --fail -o "$tmpfile" "$download_url" 2>/dev/null || {
            # Fallback: try without version prefix
            rm -f "$tmpfile"
            tmpfile=$(mktemp)
            curl -L --fail -o "$tmpfile" "https://github.com/${REPO}/releases/latest/download/${filename}" 2>/dev/null || {
                rm -f "$tmpfile"
                return 1
            }
        }
    elif command -v wget > /dev/null; then
        wget -O "$tmpfile" "$download_url" 2>/dev/null || {
            rm -f "$tmpfile"
            tmpfile=$(mktemp)
            wget -O "$tmpfile" "https://github.com/${REPO}/releases/latest/download/${filename}" 2>/dev/null || {
                rm -f "$tmpfile"
                return 1
            }
        }
    else
        error "Neither curl nor wget found. Please install one of them."
    fi
    
    echo "$tmpfile"
}

# Install binary
install_binary() {
    local tmpfile=$1
    local filename=$2
    
    # Create install directory
    mkdir -p "$INSTALL_DIR"
    
    local dest="${INSTALL_DIR}/noosphere"
    [ "$OS" = "windows" ] && dest="${dest}.exe"
    
    # Check if exists and not forcing
    if [ -f "$dest" ] && [ "$FORCE" != "true" ]; then
        warn "Noosphere already installed at $dest"
        read -p "Overwrite? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            rm -f "$tmpfile"
            exit 0
        fi
    fi
    
    # Move to destination
    mv "$tmpfile" "$dest"
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
    
    # Check if already in PATH
    if [ -d "$INSTALL_DIR" ] && [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        echo "export PATH=\"\$PATH:$INSTALL_DIR\"" >> "$shell_rc"
        log "Added $INSTALL_DIR to PATH in $shell_rc"
        log "Restart your shell or run: source $shell_rc"
    fi
}

# Main
main() {
    log "Noosphere Browser Installer"
    echo
    
    OS=$(detect_os)
    ARCH=$(detect_arch)
    
    log "Detected: $OS ($ARCH)"
    
    local filename=$(get_filename "$OS" "$ARCH")
    log "Looking for: $filename"
    echo
    
    # Check if pre-built binary exists
    if [ "$OS" = "windows" ]; then
        warn "Windows builds not yet available - building from source required"
        echo "Run: zig build -freestanding -target ${ARCH}-windows-gnu"
        exit 0
    fi
    
    # Try to download
    local tmpfile
    if tmpfile=$(download_release "$filename" "$VERSION" 2>/dev/null); then
        install_binary "$tmpfile" "$filename"
        add_to_path
    else
        warn "Pre-built binary not available for $OS ($ARCH)"
        echo
        echo "Building from source..."
        echo
        echo "Dependencies:"
        echo "  - Zig 0.13+ (https://ziglang.org)"
        echo
        echo "Build commands:"
        echo "  git clone https://github.com/developerfred/noosphere-browser-v1.git"
        echo "  cd noosphere-browser"
        echo "  zig build -freestanding -target ${ARCH}-linux-gnu"
        echo
    fi
    
    echo
    log "Done! Run 'noosphere --help' to get started."
}

main "$@"
