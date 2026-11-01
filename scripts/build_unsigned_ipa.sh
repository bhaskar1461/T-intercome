#!/usr/bin/env bash
#
# build_unsigned_ipa.sh — Builds SplitBudsPTT as an unsigned .ipa
# suitable for sideloading via AltStore, Sideloadly, or TrollStore.
#
# Usage: ./scripts/build_unsigned_ipa.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_ROOT}"

echo "═══════════════════════════════════════════════════════════"
echo "  SplitBuds PTT — Unsigned IPA Builder"
echo "═══════════════════════════════════════════════════════════"

# ─── Step 1: Generate Xcode project via XcodeGen ────────────────────
echo ""
echo "▸ [1/5] Generating Xcode project..."
if ! command -v xcodegen &>/dev/null; then
    echo "  ✗ xcodegen not found. Installing via Homebrew..."
    brew install xcodegen
fi
xcodegen generate --spec project.yml
echo "  ✓ SplitBudsPTT.xcodeproj generated."

# ─── Step 2: Build for device (unsigned) ────────────────────────────
echo ""
echo "▸ [2/5] Building Release for iphoneos (unsigned)..."
DERIVED_DATA_PATH="${PROJECT_ROOT}/build"

xcodebuild \
    -project SplitBudsPTT.xcodeproj \
    -scheme SplitBudsPTT \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -sdk iphoneos \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    DEVELOPMENT_TEAM="" \
    AD_HOC_CODE_SIGNING_ALLOWED=YES

APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Release-iphoneos/SplitBudsPTT.app"

if [ ! -d "${APP_PATH}" ]; then
    echo "  ✗ Build failed — .app bundle not found at ${APP_PATH}"
    exit 1
fi
echo "  ✓ Build succeeded: ${APP_PATH}"

# ─── Step 3: Create Payload directory structure ─────────────────────
echo ""
echo "▸ [3/5] Creating Payload structure..."
PAYLOAD_DIR="${PROJECT_ROOT}/Payload"
rm -rf "${PAYLOAD_DIR}"
mkdir -p "${PAYLOAD_DIR}"
cp -R "${APP_PATH}" "${PAYLOAD_DIR}/"
echo "  ✓ Payload/SplitBudsPTT.app created."

# ─── Step 4: Ad-hoc codesign ───────────────────────────────────────
echo ""
echo "▸ [4/5] Applying ad-hoc code signature..."
codesign --force --deep --sign - "${PAYLOAD_DIR}/SplitBudsPTT.app"
echo "  ✓ Ad-hoc signature applied."

# ─── Step 5: Package as .ipa ───────────────────────────────────────
echo ""
echo "▸ [5/5] Packaging into SplitBudsPTT.ipa..."
IPA_PATH="${PROJECT_ROOT}/SplitBudsPTT.ipa"
rm -f "${IPA_PATH}"

cd "${PROJECT_ROOT}"
zip -r -X "${IPA_PATH}" Payload/ -x "*.DS_Store"

echo "  ✓ IPA created: ${IPA_PATH}"

# ─── Cleanup ───────────────────────────────────────────────────────
rm -rf "${PAYLOAD_DIR}"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  ✓ SplitBudsPTT.ipa is ready for sideloading!"
echo "  Size: $(du -h "${IPA_PATH}" | cut -f1)"
echo "═══════════════════════════════════════════════════════════"
