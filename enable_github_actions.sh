#!/bin/bash
# Enable GitHub Actions CI/CD
# 
# PROBLEM: Current token lacks 'workflow' scope
# SOLUTION: Create new token with workflow scope
#
# STEPS:
# 1. Go to: https://github.com/settings/tokens/new?scopes=workflow,repo
# 2. Add token description: "Noosphere CI/CD"
# 3. Select scopes: repo, workflow
# 4. Generate token
# 5. Run: export GITHUB_TOKEN="ghp_xxxxx"
# 6. Run: ./enable_github_actions.sh

set -e

GITHUB_TOKEN=${GITHUB_TOKEN:-""}
REPO="developerfred/noosphere-browser-v1"

if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ GITHUB_TOKEN not set"
    echo ""
    echo "Please set your GitHub token with workflow scope:"
    echo "  export GITHUB_TOKEN='ghp_xxxxx'"
    echo ""
    echo "To create a new token:"
    echo "  1. Go to https://github.com/settings/tokens/new?scopes=workflow,repo"
    echo "  2. Add description: Noosphere CI/CD"
    echo "  3. Select: repo, workflow"
    echo "  4. Generate and copy the token"
    exit 1
fi

echo "🔑 Token found: ${GITHUB_TOKEN:0:4}..."

# Try to create the workflow file via API
echo "📁 Creating .github/workflows/release.yml via API..."

# Check if file exists
CHECK=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/$REPO/contents/.github/workflows/release.yml")

if [ "$CHECK" = "200" ]; then
    echo "⚠️  File already exists, updating..."
    # Get SHA
    SHA=$(curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/$REPO/contents/.github/workflows/release.yml" | \
        jq -r '.sha')
    
    # Update
    curl -s -X PUT \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"message\": \"ci: Add release workflow via API\",
            \"content\": \"$(base64 -w0 .github/workflows/release.yml)\",
            \"sha\": \"$SHA\"
        }" \
        "https://api.github.com/repos/$REPO/contents/.github/workflows/release.yml"
else
    echo "📄 File doesn't exist, creating..."
    # Create directory first
    curl -s -X PUT \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "message": "ci: Add .github/workflows directory"
        }' \
        "https://api.github.com/repos/$REPO/contents/.github/workflows"
    
    # Create file
    curl -s -X PUT \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"message\": \"ci: Add release workflow\",
            \"content\": \"$(base64 -w0 .github/workflows/release.yml)\"
        }" \
        "https://api.github.com/repos/$REPO/contents/.github/workflows/release.yml"
fi

echo ""
echo "✅ GitHub Actions workflow created!"
echo ""
echo "Next steps:"
echo "1. Go to https://github.com/$REPO/actions"
echo "2. You should see the 'Release Build' workflow"
echo "3. Push a tag to trigger: git tag v1.2.1 && git push origin v1.2.1"
