#!/bin/bash
# build-app.sh — Build VoicePepper.app for arm64, x86_64, or universal
#
# Usage:
#   ./scripts/build-app.sh --arch arm64
#   ./scripts/build-app.sh --arch x86_64
#   ./scripts/build-app.sh --arch universal
#   ./scripts/build-app.sh --arch arm64 --sign "Developer ID Application: ..."
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Defaults
ARCH="arm64"
SIGN_IDENTITY=""
OUTPUT_DIR="$PROJECT_DIR/build"
ENTITLEMENTS="$PROJECT_DIR/Sources/VoicePepper/Resources/VoicePepper.entitlements"
INFO_PLIST="$PROJECT_DIR/Resources/Info.plist"

# Dylibs to embed (package → versioned dylib filename)
DYLIB_MAP=(
    "whisper-cpp:libwhisper.1.dylib"
    "ggml:libggml.0.dylib"
    "ggml:libggml-base.0.dylib"
    "opus:libopus.0.dylib"
)

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        --arch)      ARCH="$2";          shift 2 ;;
        --sign)      SIGN_IDENTITY="$2"; shift 2 ;;
        --output)    OUTPUT_DIR="$2";    shift 2 ;;
        -h|--help)
            echo "Usage: $0 --arch <arm64|x86_64|universal> [--sign <identity>] [--output <dir>]"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { echo "==> $*" >&2; }

homebrew_prefix_for_arch() {
    case "$1" in
        arm64)  echo "/opt/homebrew" ;;
        x86_64) echo "/usr/local" ;;
        *) echo "Unknown arch: $1" >&2; exit 1 ;;
    esac
}

# Build SPM executable for a single architecture
build_single() {
    local arch="$1"
    local prefix
    prefix="$(homebrew_prefix_for_arch "$arch")"

    log "Building for $arch (HOMEBREW_PREFIX=$prefix)"

    cd "$PROJECT_DIR"
    if [[ "$arch" == "x86_64" ]]; then
        HOMEBREW_PREFIX="$prefix" arch -x86_64 swift build -c release
    else
        HOMEBREW_PREFIX="$prefix" swift build -c release
    fi
}

# Resolve SPM build output path for an architecture
bin_path_for_arch() {
    local arch="$1"
    echo "$PROJECT_DIR/.build/$arch-apple-macosx/release/VoicePepper"
}

# Resolve dylib source path
dylib_source_path() {
    local prefix="$1"   # Homebrew prefix
    local package="$2"  # e.g. whisper-cpp
    local dylib="$3"    # e.g. libwhisper.1.dylib
    echo "$prefix/opt/$package/lib/$dylib"
}

# ---------------------------------------------------------------------------
# Assemble .app bundle
# ---------------------------------------------------------------------------
assemble_app() {
    local arch="$1"           # arm64, x86_64, or universal
    local binary_path="$2"    # path to the (possibly lipo'd) executable
    local dylib_dir="$3"      # directory containing dylibs to embed

    local app_dir="$OUTPUT_DIR/$arch/VoicePepper.app"

    log "Assembling .app bundle: $app_dir"

    rm -rf "$app_dir"
    mkdir -p "$app_dir/Contents/MacOS"
    mkdir -p "$app_dir/Contents/Resources"
    mkdir -p "$app_dir/Contents/Frameworks"

    # Copy executable
    cp "$binary_path" "$app_dir/Contents/MacOS/VoicePepper"

    # Copy Info.plist
    cp "$INFO_PLIST" "$app_dir/Contents/Info.plist"

    # Copy dylibs to Frameworks/
    for dylib in "$dylib_dir"/*.dylib; do
        [[ -f "$dylib" ]] || continue
        cp "$dylib" "$app_dir/Contents/Frameworks/"
    done

    # Fix rpaths
    fix_rpaths "$app_dir"

    echo "$app_dir"
}

# ---------------------------------------------------------------------------
# Fix dynamic library paths
# ---------------------------------------------------------------------------
fix_rpaths() {
    local app_dir="$1"
    local binary="$app_dir/Contents/MacOS/VoicePepper"
    local fw_dir="$app_dir/Contents/Frameworks"

    log "Fixing rpaths in $app_dir"

    # Fix each dylib's install name and internal references
    for dylib in "$fw_dir"/*.dylib; do
        [[ -f "$dylib" ]] || continue
        local name
        name="$(basename "$dylib")"

        # Set install name to @executable_path/../Frameworks/<name>
        install_name_tool -id "@executable_path/../Frameworks/$name" "$dylib"

        # Fix references to other Homebrew dylibs within this dylib
        while IFS= read -r dep; do
            local dep_name
            dep_name="$(basename "$dep")"
            # Only fix if the referenced dylib is one we embed
            if [[ -f "$fw_dir/$dep_name" ]]; then
                install_name_tool -change "$dep" "@executable_path/../Frameworks/$dep_name" "$dylib" 2>/dev/null || true
            fi
        done < <(otool -L "$dylib" | tail -n +2 | awk '{print $1}' | grep -v '@executable_path' | grep -v '/usr/lib/' | grep -v '/System/')

    done

    # Fix the main binary's references to Homebrew dylibs
    while IFS= read -r dep; do
        local dep_name
        dep_name="$(basename "$dep")"
        if [[ -f "$fw_dir/$dep_name" ]]; then
            install_name_tool -change "$dep" "@executable_path/../Frameworks/$dep_name" "$binary"
        fi
    done < <(otool -L "$binary" | tail -n +2 | awk '{print $1}' | grep -v '@executable_path' | grep -v '/usr/lib/' | grep -v '/System/')

    log "Rpaths fixed"
}

# ---------------------------------------------------------------------------
# Code signing
# ---------------------------------------------------------------------------
sign_app() {
    local app_dir="$1"

    if [[ -z "$SIGN_IDENTITY" ]]; then
        log "WARNING: No signing identity provided. Skipping code signing."
        log "         Use --sign <identity> to enable signing."
        return 0
    fi

    log "Signing $app_dir with identity: $SIGN_IDENTITY"

    # Sign each framework dylib first
    for dylib in "$app_dir/Contents/Frameworks"/*.dylib; do
        [[ -f "$dylib" ]] || continue
        codesign --force --sign "$SIGN_IDENTITY" "$dylib"
    done

    # Deep sign the .app bundle with entitlements and hardened runtime
    codesign --deep --force --options runtime \
        --sign "$SIGN_IDENTITY" \
        --entitlements "$ENTITLEMENTS" \
        "$app_dir"

    # Verify
    log "Verifying signature..."
    codesign -v --verbose=4 "$app_dir"
    log "Signature verified"
}

# ---------------------------------------------------------------------------
# Collect dylibs for a single architecture
# ---------------------------------------------------------------------------
collect_dylibs() {
    local arch="$1"
    local staging_dir="$2"
    local prefix
    prefix="$(homebrew_prefix_for_arch "$arch")"

    mkdir -p "$staging_dir"

    for entry in "${DYLIB_MAP[@]}"; do
        local package="${entry%%:*}"
        local dylib="${entry##*:}"
        local src
        src="$(dylib_source_path "$prefix" "$package" "$dylib")"

        if [[ ! -f "$src" ]]; then
            echo "ERROR: Dylib not found: $src" >&2
            echo "       Install with: brew install $package" >&2
            exit 1
        fi

        # Copy the actual file (resolve symlinks)
        cp -L "$src" "$staging_dir/$dylib"
    done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
log "VoicePepper build — arch=$ARCH"
mkdir -p "$OUTPUT_DIR"

if [[ "$ARCH" == "universal" ]]; then
    # -----------------------------------------------------------------------
    # Universal: build both, lipo merge
    # -----------------------------------------------------------------------
    ARM64_STAGING="$OUTPUT_DIR/.staging/arm64"
    X86_64_STAGING="$OUTPUT_DIR/.staging/x86_64"
    UNIVERSAL_STAGING="$OUTPUT_DIR/.staging/universal"
    mkdir -p "$ARM64_STAGING" "$X86_64_STAGING" "$UNIVERSAL_STAGING"

    # Build both architectures
    build_single arm64
    build_single x86_64

    # Merge binary
    log "Creating Universal Binary with lipo"
    lipo -create \
        "$(bin_path_for_arch arm64)" \
        "$(bin_path_for_arch x86_64)" \
        -output "$UNIVERSAL_STAGING/VoicePepper"

    # Verify
    lipo -info "$UNIVERSAL_STAGING/VoicePepper" >&2

    # Collect and merge dylibs
    ARM64_DYLIBS="$OUTPUT_DIR/.staging/arm64-dylibs"
    X86_64_DYLIBS="$OUTPUT_DIR/.staging/x86_64-dylibs"
    UNIVERSAL_DYLIBS="$OUTPUT_DIR/.staging/universal-dylibs"
    mkdir -p "$UNIVERSAL_DYLIBS"

    collect_dylibs arm64  "$ARM64_DYLIBS"
    collect_dylibs x86_64 "$X86_64_DYLIBS"

    for entry in "${DYLIB_MAP[@]}"; do
        dylib="${entry##*:}"
        log "lipo merge: $dylib"
        lipo -create \
            "$ARM64_DYLIBS/$dylib" \
            "$X86_64_DYLIBS/$dylib" \
            -output "$UNIVERSAL_DYLIBS/$dylib"
    done

    # Assemble .app
    APP_DIR="$(assemble_app universal "$UNIVERSAL_STAGING/VoicePepper" "$UNIVERSAL_DYLIBS")"

    # Sign
    sign_app "$APP_DIR"

    # Cleanup staging
    rm -rf "$OUTPUT_DIR/.staging"

else
    # -----------------------------------------------------------------------
    # Single architecture: arm64 or x86_64
    # -----------------------------------------------------------------------
    build_single "$ARCH"

    DYLIB_STAGING="$OUTPUT_DIR/.staging/$ARCH-dylibs"
    collect_dylibs "$ARCH" "$DYLIB_STAGING"

    APP_DIR="$(assemble_app "$ARCH" "$(bin_path_for_arch "$ARCH")" "$DYLIB_STAGING")"

    # Sign
    sign_app "$APP_DIR"

    # Cleanup staging
    rm -rf "$OUTPUT_DIR/.staging"
fi

log "Build complete: $APP_DIR"
echo ""
echo "Output: $APP_DIR"
