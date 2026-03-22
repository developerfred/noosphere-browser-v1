#!/bin/bash
# Enable GitHub Actions for Noosphere Browser
# Run this script to enable automatic builds

REPO="developerfred/noosphere-browser-v1"
TOKEN="${GITHUB_TOKEN:-}"

if [ -z "$TOKEN" ]; then
    echo "Error: GITHUB_TOKEN not set"
    echo ""
    echo "Please either:"
    echo "1. Generate a new token with 'workflow' scope at:"
    echo "   https://github.com/settings/tokens/new?scopes=workflow,repo"
    echo ""
    echo "2. Or enable GitHub Actions manually:"
    echo "   - Go to https://github.com/$REPO/actions"
    echo "   - Click 'I understand my workflows, go ahead'"
    echo "   - Then push a tag: git tag v1.0.0 && git push origin v1.0.0"
    exit 1
fi

echo "Enabling GitHub Actions..."

# Try to get repo to verify token has access
curl -s -H "Authorization: token $TOKEN" \
    "https://api.github.com/repos/$REPO" | grep -q "full_name" && \
    echo "✓ Token verified" || \
    echo "✗ Token invalid or no access to repo"

# Check if actions are enabled by trying to list workflows
curl -s -H "Authorization: token $TOKEN" \
    "https://api.github.com/repos/$REPO/actions/workflows" | \
    grep -q "total_count" && \
    echo "✓ GitHub Actions enabled" || \
    echo "✗ GitHub Actions not enabled - please enable manually"

echo ""
echo "To enable manually:"
echo "1. Go to: https://github.com/$REPO/actions"
echo "2. Click 'Enable GitHub Actions'"
echo ""
echo "To trigger a release build:"
echo "  git tag v1.0.0 && git push origin v1.0.0"
