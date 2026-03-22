#!/bin/bash
# Noosphere Browser Build Script
# Builds binaries for all platforms using GitHub Actions

set -e

REPO="developerfred/noosphere-browser-v1"
TAG="${1:-latest}"

echo "=========================================="
echo "  Noosphere Browser - Build Script"
echo "=========================================="
echo ""

# Check if we're in a release context
if [ -n "$GITHUB_REF" ]; then
    echo "Running in GitHub Actions"
    echo "Ref: $GITHUB_REF"
    echo "Token: ${GITHUB_TOKEN:0:4}..."
fi

# Function to trigger workflow
trigger_build() {
    local platform=$1
    echo "Triggering build for: $platform"
    
    if [ -n "$GITHUB_TOKEN" ]; then
        curl -s -X POST "https://api.github.com/repos/$REPO/actions/workflows/release.yml/dispatches" \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            -d "{\"ref\":\"master\",\"inputs\":{\"platform\":\"$platform\"}}"
        echo "✅ Build triggered for $platform"
    else
        echo "⚠️  GITHUB_TOKEN not set - cannot trigger workflow"
        echo "   Please set GITHUB_TOKEN environment variable"
        echo "   Or run locally with: make build"
    fi
}

# Parse arguments
case "${1:-}" in
    --all)
        echo "Building ALL platforms..."
        trigger_build "all"
        ;;
    --linux-x86)
        trigger_build "linux-x86"
        ;;
    --linux-arm64)
        trigger_build "linux-arm64"
        ;;
    --linux-armv7)
        trigger_build "linux-armv7"
        ;;
    --macos-intel)
        trigger_build "macos-intel"
        ;;
    --macos-apple)
        trigger_build "macos-apple"
        ;;
    --windows)
        trigger_build "windows"
        ;;
    --trigger-only)
        echo "Triggering workflow dispatch..."
        trigger_build "all"
        ;;
    --help|"-h")
        echo "Usage: $0 [platform]"
        echo ""
        echo "Platforms:"
        echo "  --all          Build all platforms (triggers GitHub Actions)"
        echo "  --linux-x86    Linux x86_64"
        echo "  --linux-arm64  Linux ARM64 (Raspberry Pi 4)"
        echo "  --linux-armv7  Linux ARMv7 (Raspberry Pi 3)"
        echo "  --macos-intel  macOS Intel"
        echo "  --macos-apple  macOS Apple Silicon"
        echo "  --windows      Windows x86_64"
        echo "  --help         Show this help"
        echo ""
        echo "Or run locally:"
        echo "  make build           # Current platform"
        echo "  make build-all      # All platforms (requires Zig)"
        echo ""
        echo "Examples:"
        echo "  $0 --all                  # Trigger all builds via GitHub Actions"
        echo "  GITHUB_TOKEN=xxx $0 --linux-arm64  # Trigger specific build"
        ;;
    *)
        echo "Building for current platform..."
        echo "Use 'make build' for local build or '$0 --all' to trigger GitHub Actions"
        ;;
esac

echo ""
echo "=========================================="
echo "  Done!"
echo "=========================================="
