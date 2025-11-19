#!/bin/bash
set -e

# Ensure we have the required tools
command -v git >/dev/null 2>&1 || { echo "git is required but not installed."; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "gh CLI is required but not installed."; exit 1; }
command -v git-cliff >/dev/null 2>&1 || { echo "git-cliff is required but not installed."; exit 1; }

# Verify we're in a git repo with clean working directory
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: Not in a git repository"
    exit 1
fi

if ! git diff-index --quiet HEAD --; then
    echo "Error: Working directory is not clean. Please commit or stash changes."
    exit 1
fi

PKGNAME=$(basename "$PWD")
HACE_BIN="./bin/hace"

# Verify hace binary exists and is executable
if [ ! -f "$HACE_BIN" ]; then
    echo "Error: $HACE_BIN not found. Please run 'hace build' first."
    exit 1
fi

if [ ! -x "$HACE_BIN" ]; then
    echo "Error: $HACE_BIN is not executable."
    exit 1
fi

VERSION=$(git cliff --bumped-version |cut -dv -f2)

echo "Preparing release v$VERSION for $PKGNAME"

# Update version in shard.yml
echo "Updating version in shard.yml..."
sed "s/^version:.*$/version: $VERSION/g" -i shard.yml
git add shard.yml

# Run quality checks
echo "Running linting and tests..."
$HACE_BIN lint test

# Update changelog
echo "Updating changelog..."
git cliff --bump -o

# Commit version bump and changelog
echo "Committing version bump and changelog..."
git commit -a -m "bump: Release v$VERSION"

# Create and push tag
echo "Creating and pushing tag..."
git tag "v$VERSION"
git push --tags

# Build static binaries
echo "Building static binaries..."
$HACE_BIN static

# Verify static binaries exist
for arch in amd64 arm64; do
    binary="bin/${PKGNAME}-static-linux-${arch}"
    if [ ! -f "$binary" ]; then
        echo "Error: $binary not found after static build"
        exit 1
    fi
done

# Create GitHub release
echo "Creating GitHub release..."
gh release create "v$VERSION" \
    "bin/$PKGNAME-static-linux-amd64" \
    "bin/$PKGNAME-static-linux-arm64" \
    --title "Release v$VERSION" \
    --notes "$(git cliff -l -s all)"

# Update AUR package if script exists
if [ -f "./do_aur.sh" ]; then
    echo "Updating AUR package..."
    ./do_aur.sh
else
    echo "Warning: do_aur.sh not found, skipping AUR update"
fi

# Deploy documentation
echo "Deploying documentation..."
$HACE_BIN user-docs-deploy -B

echo "Release v$VERSION completed successfully!"
