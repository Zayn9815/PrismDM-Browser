#!/usr/bin/env python3
# Copyright © 2026 PrismDM. All Rights Reserved. Proprietary and Confidential.
"""Comprehensive static verification suite for PrismDM Browser (iOS 26 Objective-C)."""

import os
import plistlib
import re
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = ROOT / "src"

ERRORS = []
WARNINGS = []


def fail(msg: str) -> None:
    ERRORS.append(msg)


def warn(msg: str) -> None:
    WARNINGS.append(msg)


def strip_objc_comments_and_strings(code: str) -> str:
    """Lexer-aware stripper preserving line structure while blanking strings/comments."""
    out = []
    i = 0
    n = len(code)
    state = "CODE"
    while i < n:
        ch = code[i]
        nxt = code[i + 1] if i + 1 < n else ""
        if state == "CODE":
            if ch == "/" and nxt == "/":
                state = "LINE_COMMENT"
                out.append("  ")
                i += 2
            elif ch == "/" and nxt == "*":
                state = "BLOCK_COMMENT"
                out.append("  ")
                i += 2
            elif ch == '"':
                state = "STRING"
                out.append(" ")
                i += 1
            elif ch == "'":
                state = "CHAR"
                out.append(" ")
                i += 1
            else:
                out.append(ch)
                i += 1
        elif state == "LINE_COMMENT":
            if ch == "\n":
                state = "CODE"
                out.append("\n")
            else:
                out.append(" ")
            i += 1
        elif state == "BLOCK_COMMENT":
            if ch == "*" and nxt == "/":
                state = "CODE"
                out.append("  ")
                i += 2
            elif ch == "\n":
                out.append("\n")
                i += 1
            else:
                out.append(" ")
                i += 1
        elif state == "STRING":
            if ch == "\\" and i + 1 < n:
                out.append("  ")
                i += 2
            elif ch == '"':
                state = "CODE"
                out.append(" ")
                i += 1
            elif ch == "\n":
                state = "CODE"
                out.append("\n")
                i += 1
            else:
                out.append(" ")
                i += 1
        elif state == "CHAR":
            if ch == "\\" and i + 1 < n:
                out.append("  ")
                i += 2
            elif ch == "'":
                state = "CODE"
                out.append(" ")
                i += 1
            else:
                out.append(" ")
                i += 1
    return "".join(out)


def check_delimiters(path: Path, stripped: str) -> None:
    pairs = {"{": "}", "(": ")", "[": "]"}
    closing = {"}": "{", ")": "(", "]": "["}
    stack = []
    line = 1
    for ch in stripped:
        if ch == "\n":
            line += 1
        elif ch in pairs:
            stack.append((ch, line))
        elif ch in closing:
            if not stack or stack[-1][0] != closing[ch]:
                fail(f"{path.name}:{line}: unmatched closing '{ch}'")
                return
            stack.pop()
    if stack:
        ch, ln = stack[-1]
        fail(f"{path.name}:{ln}: unclosed '{ch}'")


def check_info_plist() -> None:
    plist_path = ROOT / "Info.plist"
    if not plist_path.exists():
        fail("Info.plist missing")
        return
    try:
        with plist_path.open("rb") as f:
            data = plistlib.load(f)
    except Exception as exc:
        fail(f"Info.plist XML parse error: {exc}")
        return

    checks = {
        "CFBundleIdentifier": "com.prismdm.browser",
        "CFBundleDisplayName": "PrismDM",
        "CFBundleExecutable": "PrismDM",
        "MinimumOSVersion": "26.0",
        "UIFileSharingEnabled": True,
        "LSSupportsOpeningDocumentsInPlace": True,
    }
    for k, expected in checks.items():
        if data.get(k) != expected:
            fail(f"Info.plist key '{k}' expected {expected!r}, got {data.get(k)!r}")

    if "audio" not in data.get("UIBackgroundModes", []):
        fail("Info.plist missing UIBackgroundModes audio")
    if "All Rights Reserved" not in data.get("NSHumanReadableCopyright", ""):
        fail("Info.plist missing proprietary NSHumanReadableCopyright")
    if not data.get("NSFaceIDUsageDescription"):
        fail("Info.plist missing NSFaceIDUsageDescription")
    if not data.get("NSPhotoLibraryAddUsageDescription"):
        fail("Info.plist missing NSPhotoLibraryAddUsageDescription")
    if "CFBundleIcons" not in data or "CFBundleIcons~ipad" not in data:
        fail("Info.plist missing CFBundleIcons or CFBundleIcons~ipad")


def check_app_icon() -> None:
    icon_path = ROOT / "AppIcon1024.png"
    if not icon_path.exists():
        fail("AppIcon1024.png missing")
        return
    raw = icon_path.read_bytes()
    if len(raw) < 24 or raw[:8] != b"\x89PNG\r\n\x1a\n":
        fail("AppIcon1024.png is not a valid PNG file")
        return
    w, h = struct.unpack(">II", raw[16:24])
    if (w, h) != (1024, 1024):
        fail(f"AppIcon1024.png dimensions expected 1024x1024, got {w}x{h}")


def extract_bash_array(script_text: str, array_name: str) -> list:
    m = re.search(rf"{array_name}=\((.*?)\)", script_text, re.DOTALL)
    if not m:
        return []
    tokens = re.findall(r'"([^"]+)"|([^\s]+)', m.group(1))
    return [a or b for a, b in tokens]


def check_shell_scripts_and_parity() -> None:
    build_sh = ROOT / "build.sh"
    test_sh = ROOT / "tests" / "run_all_tests.sh"
    for sh in (build_sh, test_sh):
        if not sh.exists():
            fail(f"{sh.relative_to(ROOT)} missing")
            continue
        res = subprocess.run(["bash", "-n", str(sh)], capture_output=True, text=True)
        if res.returncode != 0:
            fail(f"bash -n failed for {sh.name}: {res.stderr.strip()}")

    if build_sh.exists() and test_sh.exists():
        b_txt = build_sh.read_text(encoding="utf-8")
        t_txt = test_sh.read_text(encoding="utf-8")
        for arr in ("SOURCES", "FRAMEWORKS", "LIBRARIES", "CFLAGS"):
            b_arr = extract_bash_array(b_txt, arr)
            t_arr = extract_bash_array(t_txt, arr)
            if not b_arr:
                fail(f"build.sh missing array {arr}")
            if b_arr != t_arr:
                fail(f"Parity mismatch for {arr}: build.sh={b_arr} vs run_all_tests.sh={t_arr}")
        # Verify every source listed in build.sh exists
        for src in extract_bash_array(b_txt, "SOURCES"):
            if not (ROOT / src).exists():
                fail(f"Source file listed in build.sh missing: {src}")


def check_objc_sources() -> None:
    all_files = sorted(list(SRC_DIR.glob("*.h")) + list(SRC_DIR.glob("*.m")))
    if not all_files:
        fail("No Objective-C source files found in src/")
        return

    impl_map = {}
    required_modules = [
        "main.m",
        "PDMTheme.h", "PDMTheme.m",
        "PDMUI.h", "PDMUI.m",
        "PDMPrivacyShield.h", "PDMPrivacyShield.m",
        "PDMMediaSniffer.h", "PDMMediaSniffer.m",
        "PDMTranscoder.h", "PDMTranscoder.m",
        "PDMDownloadManager.h", "PDMDownloadManager.m",
        "PDMMediaPlayer.h", "PDMMediaPlayer.m",
        "PDMLibrary.h", "PDMLibrary.m",
        "PDMTabGrid.h", "PDMTabGrid.m",
        "PDMBrowser.h", "PDMBrowser.m",
    ]
    for req in required_modules:
        if not (SRC_DIR / req).exists():
            fail(f"Required source file missing: src/{req}")

    forbidden_patterns = [
        (r"weakSelf\s*->\s*_", "Direct __weak ivar dereference (weakSelf->_ivar)"),
        (r"\bCCKeyDerivationPBKDF2\b", "Forbidden CCKeyDerivationPBKDF2 (use CCKeyDerivationPBKDF)"),
        (r"initWithTitle:[^;\n]*image:[^;\n]*primaryAction:[^;\n]*menu:", "Non-existent UIBarButtonItem initializer"),
        (r"initWithBarButtonSystemItem:[^;\n]*primaryAction:(?!.*menu:)", "Forbidden 2-arg UIBarButtonItem initializer without menu:"),
        (r"\bNSFileHandle\b", "Deprecated NSFileHandle usage (use POSIX open/pwrite/pread)"),
        (r"UIScreen\.mainScreen|\[UIScreen\s+mainScreen\]", "Soft-deprecated UIScreen.mainScreen"),
        (r"UIGraphicsBeginImageContextWithOptions", "Deprecated UIGraphicsBeginImageContextWithOptions"),
        (r"\.(contentEdgeInsets|titleEdgeInsets|imageEdgeInsets)\b", "Deprecated UIButton edge insets"),
    ]

    for path in all_files:
        raw = path.read_text(encoding="utf-8")
        if "Copyright © 2026 PrismDM. All Rights Reserved." not in raw:
            fail(f"{path.name}: missing proprietary copyright header")

        stripped = strip_objc_comments_and_strings(raw)
        check_delimiters(path, stripped)

        for pat, desc in forbidden_patterns:
            m = re.search(pat, stripped)
            if m:
                ln = stripped[: m.start()].count("\n") + 1
                fail(f"{path.name}:{ln}: {desc}")

        if path.suffix == ".m":
            # Check duplicate @implementation
            for m in re.finditer(r"@implementation\s+([A-Za-z_][A-Za-z0-9_]*)\b", stripped):
                cls = m.group(1)
                if cls in impl_map:
                    fail(f"Duplicate @implementation {cls} in {path.name} and {impl_map[cls]}")
                impl_map[cls] = path.name

            # Check unused static C functions
            for m in re.finditer(r"^\s*static\s+(?!const\b)[A-Za-z_][A-Za-z0-9_\s\*]*?\b([A-Za-z_][A-Za-z0-9_]*)\s*\([^;]*\)\s*\{", stripped, re.MULTILINE):
                fn_name = m.group(1)
                occurrences = len(re.findall(rf"\b{re.escape(fn_name)}\b", stripped))
                if occurrences < 2:
                    fail(f"{path.name}: unused static function '{fn_name}'")

            # Check @catch unused exception variable
            for m in re.finditer(r"@catch\s*\(\s*NSException\s*\*\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)", stripped):
                var = m.group(1)
                if var != "__unused":
                    # Check if followed by __unused or actually referenced in catch block
                    after = stripped[m.end() : m.end() + 180]
                    block_end = after.find("}")
                    body = after[:block_end] if block_end != -1 else after
                    if not re.search(rf"\b{re.escape(var)}\b", body):
                        fail(f"{path.name}: unused @catch exception variable '{var}' (annotate with __unused)")

            # Check unguarded AVAssetExportSession deprecation
            if "exportAsynchronouslyWithCompletionHandler:" in stripped:
                if "ignored" not in raw or "-Wdeprecated-declarations" not in raw:
                    fail(f"{path.name}: AVAssetExportSession exportAsynchronouslyWithCompletionHandler not wrapped in -Wdeprecated-declarations pragma")

            # Check unused Obj-C method parameters under -Wextra -Werror
            for m in re.finditer(r"^([-+]\s*\([^)]+\)\s*[^{\n;]+)\{", stripped, re.MULTILINE):
                header = m.group(1)
                start = m.end()
                depth = 1
                idx = start
                while idx < len(stripped) and depth > 0:
                    if stripped[idx] == "{":
                        depth += 1
                    elif stripped[idx] == "}":
                        depth -= 1
                    idx += 1
                body = stripped[start : idx - 1]
                for pm in re.finditer(r":\s*\(([^)]+)\)\s*([A-Za-z_][A-Za-z0-9_]*)", header):
                    ptype, pname = pm.group(1), pm.group(2)
                    if "__unused" in ptype or "__unused" in pname:
                        continue
                    if not re.search(rf"\b{re.escape(pname)}\b", body):
                        ln = stripped[: m.start()].count("\n") + 1
                        fail(f"{path.name}:{ln}: unused Obj-C parameter '{pname}'")

            # Check unused C static function parameters
            for m in re.finditer(r"^\s*static\s+[A-Za-z0-9_\s\*]+\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]+)\)\s*\{", stripped, re.MULTILINE):
                fn, params = m.group(1), m.group(2)
                start = m.end()
                depth = 1
                idx = start
                while idx < len(stripped) and depth > 0:
                    if stripped[idx] == "{":
                        depth += 1
                    elif stripped[idx] == "}":
                        depth -= 1
                    idx += 1
                body = stripped[start : idx - 1]
                for part in params.split(","):
                    part = part.strip()
                    if not part or part == "void" or "__unused" in part:
                        continue
                    part_clean = re.sub(r"\[[^\]]*\]", "", part).strip()
                    toks = re.findall(r"[A-Za-z_][A-Za-z0-9_]*", part_clean)
                    if not toks:
                        continue
                    pname = toks[-1]
                    if not re.search(rf"\b{re.escape(pname)}\b", body):
                        ln = stripped[: m.start()].count("\n") + 1
                        fail(f"{path.name}:{ln}: unused C parameter '{pname}' in {fn}()")


def check_proprietary_license_and_repo_files() -> None:
    lic_path = ROOT / "LICENSE"
    if not lic_path.exists():
        fail("LICENSE file missing")
    else:
        lic_txt = lic_path.read_text(encoding="utf-8")
        if "PROPRIETARY SOFTWARE LICENSE" not in lic_txt or "ALL RIGHTS RESERVED" not in lic_txt.upper():
            fail("LICENSE is not clearly titled PROPRIETARY SOFTWARE LICENSE — ALL RIGHTS RESERVED")
        for forbidden_oss in ("Permission is hereby granted, free of charge", "Apache License", "GNU GENERAL PUBLIC LICENSE", "BSD License"):
            if forbidden_oss in lic_txt:
                fail(f"LICENSE must be strictly proprietary, found open-source text: {forbidden_oss}")

    required_repo_files = [
        "README.md",
        "CHANGELOG.md",
        "SECURITY.md",
        ".gitignore",
        ".github/workflows/build-ipa.yml",
        ".github/ISSUE_TEMPLATE/bug_report.md",
        ".github/ISSUE_TEMPLATE/feature_request.md",
    ]
    for rf in required_repo_files:
        if not (ROOT / rf).exists():
            fail(f"Required repository file missing: {rf}")


def main() -> int:
    check_info_plist()
    check_app_icon()
    check_shell_scripts_and_parity()
    check_objc_sources()
    check_proprietary_license_and_repo_files()

    for w in WARNINGS:
        print(f"[WARN] {w}")

    if ERRORS:
        print(f"\nSTATIC VERIFICATION FAILED ({len(ERRORS)} error(s)):")
        for e in ERRORS:
            print(f"  [ERROR] {e}")
        return 1

    print("ALL STATIC VERIFICATION CHECKS PASSED (0 errors, 0 warnings)!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
