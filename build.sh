#!/usr/bin/env bash
# Copyright © 2026 PrismDM. All Rights Reserved. Proprietary and Confidential.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="PrismDM"
BUILD_DIR="${ROOT_DIR}/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
PAYLOAD_DIR="${BUILD_DIR}/Payload"
IPA_PATH="${ROOT_DIR}/${APP_NAME}.ipa"

SOURCES=(
    "src/main.m"
    "src/PDMTheme.m"
    "src/PDMUI.m"
    "src/PDMPrivacyShield.m"
    "src/PDMMediaSniffer.m"
    "src/PDMTranscoder.m"
    "src/PDMDownloadManager.m"
    "src/PDMMediaPlayer.m"
    "src/PDMLibrary.m"
    "src/PDMTabGrid.m"
    "src/PDMBrowser.m"
)

FRAMEWORKS=(
    UIKit
    Foundation
    WebKit
    AVFoundation
    AVKit
    AudioToolbox
    CoreMedia
    MediaPlayer
    LocalAuthentication
    QuartzCore
    UniformTypeIdentifiers
)

LIBRARIES=(
    -lz
)

CFLAGS=(
    -fobjc-arc
    -fmodules
    -arch arm64
    -miphoneos-version-min=26.0
    -Wall
    -Wextra
    -Werror
    -O2
)

echo "=== PrismDM Browser — Native iOS 26 Build ==="

SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG="$(xcrun --sdk iphoneos --find clang)"

echo "Using SDK: ${SDK_PATH}"
echo "Using Compiler: ${CLANG}"

rm -rf "${BUILD_DIR}" "${IPA_PATH}"
mkdir -p "${APP_BUNDLE}" "${PAYLOAD_DIR}"

FW_ARGS=()
for fw in "${FRAMEWORKS[@]}"; do
    FW_ARGS+=("-framework" "${fw}")
done

SRC_PATHS=()
for s in "${SOURCES[@]}"; do
    SRC_PATHS+=("${ROOT_DIR}/${s}")
done

echo "Compiling arm64 iOS 26 binary with strict -Wall -Wextra -Werror..."
"${CLANG}" \
    -isysroot "${SDK_PATH}" \
    "${CFLAGS[@]}" \
    -I"${ROOT_DIR}/src" \
    "${SRC_PATHS[@]}" \
    "${FW_ARGS[@]}" \
    "${LIBRARIES[@]}" \
    -o "${APP_BUNDLE}/${APP_NAME}"

echo "Copying Info.plist..."
cp "${ROOT_DIR}/Info.plist" "${APP_BUNDLE}/Info.plist"
plutil -convert binary1 "${APP_BUNDLE}/Info.plist"

echo "Generating iPhone & iPad App Icons from AppIcon1024.png..."
ICON_SRC="${ROOT_DIR}/AppIcon1024.png"
if [[ ! -f "${ICON_SRC}" ]]; then
    echo "ERROR: AppIcon1024.png not found at ${ICON_SRC}" >&2
    exit 1
fi

generate_icon() {
    local px="$1"
    local name="$2"
    sips -z "${px}" "${px}" -s format png "${ICON_SRC}" --out "${APP_BUNDLE}/${name}" >/dev/null
}

# iPhone & Universal Icons
generate_icon 40  "AppIcon20x20@2x.png"
generate_icon 60  "AppIcon20x20@3x.png"
generate_icon 58  "AppIcon29x29@2x.png"
generate_icon 87  "AppIcon29x29@3x.png"
generate_icon 80  "AppIcon40x40@2x.png"
generate_icon 120 "AppIcon40x40@3x.png"
generate_icon 120 "AppIcon60x60@2x.png"
generate_icon 180 "AppIcon60x60@3x.png"

# iPad Icons
generate_icon 20  "AppIcon20x20~ipad.png"
generate_icon 40  "AppIcon20x20@2x~ipad.png"
generate_icon 29  "AppIcon29x29~ipad.png"
generate_icon 58  "AppIcon29x29@2x~ipad.png"
generate_icon 40  "AppIcon40x40~ipad.png"
generate_icon 80  "AppIcon40x40@2x~ipad.png"
generate_icon 76  "AppIcon76x76~ipad.png"
generate_icon 152 "AppIcon76x76@2x~ipad.png"
generate_icon 167 "AppIcon83.5x83.5@2x~ipad.png"

# App Store / Bundle High-Res Icon
cp "${ICON_SRC}" "${APP_BUNDLE}/AppIcon1024.png"

# PkgInfo
printf "APPL????" > "${APP_BUNDLE}/PkgInfo"

echo "Packaging unsigned ${IPA_PATH}..."
cp -R "${APP_BUNDLE}" "${PAYLOAD_DIR}/${APP_NAME}.app"
(cd "${BUILD_DIR}" && zip -qry "${IPA_PATH}" Payload)

echo "=== Build Succeeded ==="
ls -lh "${IPA_PATH}"
