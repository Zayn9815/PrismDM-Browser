#!/usr/bin/env bash
# Copyright © 2026 PrismDM. All Rights Reserved. Proprietary and Confidential.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

echo "=== Step 1: Running Python Static Verifier ==="
python3 "${ROOT_DIR}/tests/verify_project.py"

if [[ "$(uname -s)" == "Darwin" ]]; then
    echo "=== Step 2: Strict Xcode 26 Compile & Link Check ==="
    SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
    CLANG="$(xcrun --sdk iphoneos --find clang)"

    FW_ARGS=()
    for fw in "${FRAMEWORKS[@]}"; do
        FW_ARGS+=("-framework" "${fw}")
    done

    SRC_PATHS=()
    for s in "${SOURCES[@]}"; do
        SRC_PATHS+=("${ROOT_DIR}/${s}")
    done

    TMP_BIN="$(mktemp /tmp/PrismDM_test_bin.XXXXXX)"
    trap 'rm -f "${TMP_BIN}"' EXIT

    "${CLANG}" \
        -isysroot "${SDK_PATH}" \
        "${CFLAGS[@]}" \
        -I"${ROOT_DIR}/src" \
        "${SRC_PATHS[@]}" \
        "${FW_ARGS[@]}" \
        "${LIBRARIES[@]}" \
        -o "${TMP_BIN}"

    echo "=== Strict iOS 26 Compile & Link PASSED (Zero Warnings) ==="
else
    echo "=== Non-macOS host detected: skipping Darwin clang invocation (static verification passed) ==="
fi
