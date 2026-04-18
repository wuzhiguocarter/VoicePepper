#!/bin/bash
# create-dmg.sh — Generate DMG installer for VoicePepper
#
# Usage:
#   ./scripts/create-dmg.sh --arch arm64 --version 1.0.0
#   ./scripts/create-dmg.sh --arch universal --version 1.0.0 --sign "Developer ID Application: ..."
#   ./scripts/create-dmg.sh --arch arm64 --version 1.0.0 --notarize
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Defaults
ARCH="arm64"
VERSION=""
BUILD_DIR="$PROJECT_DIR/build"
SIGN_IDENTITY=""
NOTARIZE=false
APPLE_ID=""
APPLE_TEAM_ID=""
APPLE_APP_PASSWORD=""

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        --arch)              ARCH="$2";              shift 2 ;;
        --version)           VERSION="$2";           shift 2 ;;
        --build-dir)         BUILD_DIR="$2";         shift 2 ;;
        --sign)              SIGN_IDENTITY="$2";     shift 2 ;;
        --notarize)          NOTARIZE=true;           shift   ;;
        --apple-id)          APPLE_ID="$2";          shift 2 ;;
        --apple-team-id)     APPLE_TEAM_ID="$2";     shift 2 ;;
        --apple-app-password) APPLE_APP_PASSWORD="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 --arch <arm64|x86_64|universal> --version <ver> [--sign <identity>] [--notarize]"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
log() { echo "==> $*"; }

if [[ -z "$VERSION" ]]; then
    # Try to extract from git tag
    VERSION="$(git -C "$PROJECT_DIR" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
    if [[ -z "$VERSION" ]]; then
        echo "ERROR: --version is required (or set a git tag)" >&2
        exit 1
    fi
fi

APP_DIR="$BUILD_DIR/$ARCH/VoicePepper.app"
if [[ ! -d "$APP_DIR" ]]; then
    echo "ERROR: App bundle not found at $APP_DIR" >&2
    echo "       Run build-app.sh --arch $ARCH first" >&2
    exit 1
fi

DMG_NAME="VoicePepper-${VERSION}-${ARCH}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"

# ---------------------------------------------------------------------------
# Check for create-dmg tool
# ---------------------------------------------------------------------------
if ! command -v create-dmg &>/dev/null; then
    echo "ERROR: create-dmg not found. Install with: brew install create-dmg" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Create DMG
# ---------------------------------------------------------------------------
log "Creating DMG: $DMG_NAME"

# Remove existing DMG if present
rm -f "$DMG_PATH"

# create-dmg returns exit code 2 when it succeeds but cannot set the background
# image (common in CI headless environments), so we accept exit codes 0 and 2
create-dmg \
    --volname "VoicePepper" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 160 \
    --icon "VoicePepper.app" 170 185 \
    --app-drop-link 490 185 \
    --no-internet-enable \
    "$DMG_PATH" \
    "$APP_DIR" \
    || [[ $? -eq 2 ]]

if [[ ! -f "$DMG_PATH" ]]; then
    echo "ERROR: DMG creation failed" >&2
    exit 1
fi

log "DMG created: $DMG_PATH ($(du -h "$DMG_PATH" | awk '{print $1}'))"

# ---------------------------------------------------------------------------
# Sign DMG
# ---------------------------------------------------------------------------
if [[ -n "$SIGN_IDENTITY" ]]; then
    log "Signing DMG..."
    codesign --force --sign "$SIGN_IDENTITY" "$DMG_PATH"
    log "DMG signed"
else
    log "WARNING: DMG not signed (no --sign identity provided)"
fi

# ---------------------------------------------------------------------------
# Notarize DMG
# ---------------------------------------------------------------------------
if [[ "$NOTARIZE" == true ]]; then
    if [[ -z "$APPLE_ID" || -z "$APPLE_TEAM_ID" || -z "$APPLE_APP_PASSWORD" ]]; then
        echo "ERROR: --notarize requires --apple-id, --apple-team-id, and --apple-app-password" >&2
        exit 1
    fi

    log "Submitting for notarization..."
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --wait

    log "Stapling notarization ticket..."
    xcrun stapler staple "$DMG_PATH"

    log "Notarization complete"
else
    log "Skipping notarization (use --notarize to enable)"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "Output: $DMG_PATH"
