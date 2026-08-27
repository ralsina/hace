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

# Check for uncommitted changes, but ignore certain files
if ! git diff-index --quiet HEAD --; then
    # Get list of modified files
    modified_files=$(git diff-index --name-only HEAD --)

    # Check if any important files are modified
    important_files=false
    for file in $modified_files; do
        case "$file" in
            .claude/settings.local.json|spec/testcases/*/results/*|*.log)
                echo "ℹ️  Ignoring modified file: $file"
                ;;
            *)
                echo "❌ Error: Working directory has uncommitted changes in: $file"
                echo "   Please commit or stash these changes before releasing."
                important_files=true
                ;;
        esac
    done

    if [ "$important_files" = true ]; then
        exit 1
    fi
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
TAG="v$VERSION"

# Retry safety: if the tag already exists, a previous release run committed the
# bump but failed before finishing. Resume from the tag instead of creating a
# duplicate "bump: Release" commit with the same version.
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "Tag $TAG already exists; resuming release from existing bump commit."
else
    echo "Preparing release $TAG for $PKGNAME"

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

    # Commit version bump and changelog.
    # Pre-commit hooks (end-of-file-fixer, trailing-whitespace) may rewrite the
    # freshly-generated CHANGELOG, which makes the first commit fail. Re-add any
    # hook-modified files and retry once so the commit lands cleanly instead of
    # leaving the release half-done and tempting a full re-run.
    echo "Committing version bump and changelog..."
    if ! git commit -a -m "bump: Release v$VERSION"; then
        echo "Initial commit failed (likely hooks modified files); re-staging and retrying..."
        git add -u
        git commit -m "bump: Release v$VERSION"
    fi

    # Create tag and push
    echo "Creating tag and pushing..."
    git tag "$TAG"
    git push
fi

# Build static binaries.
# Run build_static.sh directly instead of `hace static`, which runs `hace
# clean` first and would delete the committed shard.lock. build_static.sh
# honors the committed lockfile (it no longer deletes it), so the lock stays
# intact and pins the dependencies for the release.
echo "Building static binaries..."
./build_static.sh

# Verify static binaries exist
for arch in amd64 arm64; do
    binary="bin/${PKGNAME}-static-linux-${arch}"
    if [ ! -f "$binary" ]; then
        echo "Error: $binary not found after static build"
        exit 1
    fi
done

# Create GitHub release (idempotent: skip if the release already exists,
# which happens when resuming a partially-finished release run)
echo "Creating GitHub release..."
git push --tags
if gh release view "$TAG" >/dev/null 2>&1; then
    echo "Release $TAG already exists on GitHub; skipping creation."
else
    gh release create "$TAG" \
        "bin/$PKGNAME-static-linux-amd64" \
        "bin/$PKGNAME-static-linux-arm64" \
        --title "Release $TAG" \
        --notes "$(git cliff -l -s all)"
fi

# Update AUR package if script exists
if [ -f "./do_aur.sh" ]; then
    echo "Updating AUR package..."
    ./do_aur.sh
else
    echo "Warning: do_aur.sh not found, skipping AUR update"
fi

# build_static.sh moves bin/hace to the static names, so rebuild the plain
# binary for local use and the steps below.
shards build

# Deploy documentation
echo "Deploying documentation..."
$HACE_BIN user-docs-deploy -B

echo "Release v$VERSION completed successfully!"
