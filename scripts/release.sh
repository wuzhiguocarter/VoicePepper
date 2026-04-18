#!/bin/bash
# release.sh — 创建版本 tag 并推送，触发 CI 自动构建和发布
#
# Usage:
#   ./scripts/release.sh 1.0.0          # 发布 v1.0.0
#   ./scripts/release.sh 1.0.0 --dry-run # 预览，不实际执行
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
VERSION=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help)
            echo "Usage: $0 <version> [--dry-run]"
            echo ""
            echo "Examples:"
            echo "  $0 1.0.0        # Release v1.0.0"
            echo "  $0 1.2.0-beta.1 # Pre-release"
            echo "  $0 1.0.0 --dry-run"
            exit 0
            ;;
        *)
            if [[ -z "$VERSION" ]]; then
                VERSION="$1"
            else
                echo "ERROR: Unexpected argument: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$VERSION" ]]; then
    echo "ERROR: Version number required." >&2
    echo "Usage: $0 <version> [--dry-run]" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
TAG="v${VERSION}"

# Semver format check (loose: major.minor.patch with optional pre-release)
if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$'; then
    echo "ERROR: Invalid version format: $VERSION" >&2
    echo "       Expected: major.minor.patch (e.g., 1.0.0, 2.1.0-beta.1)" >&2
    exit 1
fi

# Check tag doesn't already exist
if git tag -l "$TAG" | grep -q "$TAG"; then
    echo "ERROR: Tag $TAG already exists." >&2
    echo "       Existing tags:" >&2
    git tag --sort=-creatordate | head -5 | sed 's/^/         /' >&2
    exit 1
fi

# Check working tree is clean
if [[ -n "$(git status --porcelain)" ]]; then
    echo "ERROR: Working tree is not clean. Commit or stash changes first." >&2
    git status --short >&2
    exit 1
fi

# Check we're on main branch
BRANCH="$(git branch --show-current)"
if [[ "$BRANCH" != "main" ]]; then
    echo "WARNING: You're on branch '$BRANCH', not 'main'." >&2
    read -rp "Continue anyway? [y/N] " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Aborted." >&2
        exit 1
    fi
fi

# Check remote is up to date
git fetch origin --quiet
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/"$BRANCH" 2>/dev/null || echo "")
if [[ -n "$REMOTE" && "$LOCAL" != "$REMOTE" ]]; then
    echo "ERROR: Local branch is not in sync with origin/$BRANCH." >&2
    echo "       Run 'git pull' or 'git push' first." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Preview
# ---------------------------------------------------------------------------
echo ""
echo "Release Preview"
echo "==============="
echo "  Version:  $VERSION"
echo "  Tag:      $TAG"
echo "  Branch:   $BRANCH"
echo "  Commit:   $(git log --oneline -1)"
echo ""

# Show changes since last tag
PREV_TAG=$(git tag --sort=-creatordate | head -1 || echo "")
if [[ -n "$PREV_TAG" ]]; then
    echo "Changes since $PREV_TAG:"
    git log --oneline "$PREV_TAG..HEAD" --no-decorate | sed 's/^/  /'
else
    echo "Changes (last 10 commits):"
    git log --oneline -10 --no-decorate | sed 's/^/  /'
fi
echo ""

if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY RUN] Would create and push tag $TAG"
    exit 0
fi

# ---------------------------------------------------------------------------
# Confirm and execute
# ---------------------------------------------------------------------------
read -rp "Create and push tag $TAG? [y/N] " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Aborted."
    exit 0
fi

git tag -a "$TAG" -m "Release $VERSION"
git push origin "$TAG"

echo ""
echo "Tag $TAG pushed. CI will build and publish the release."
echo "Track progress: https://github.com/$(git remote get-url origin | sed 's|.*github.com[:/]||;s|\.git$||')/actions"
