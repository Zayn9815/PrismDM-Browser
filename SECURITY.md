# Security Policy

**PrismDM Browser** is strictly proprietary software developed with security and user privacy as foundational principles.

## Supported Versions

| Version | Supported iOS | Security Updates |
| :--- | :--- | :---: |
| `1.0.x` | iOS 26.0+ (`arm64`) | ✅ Active |

## Security Architecture Highlights

- **Private Browsing Isolation:** Private Tabs execute inside `WKWebsiteDataStore.nonPersistentDataStore` so cookies, caches, and browsing history are never persisted to disk.
- **Biometric Vault Protection:** Private Tabs and the Private Downloads Vault (`.PrivateVault`) are guarded via iOS `LocalAuthentication` (Face ID / Touch ID with passcode fallback).
- **Archive Safety:** The built-in `.zip` extractor enforces canonical path prefix verification to prevent Zip-Slip directory traversal attacks.
- **Memory & File Safety:** Multi-segment parallel writes use bounds-checked POSIX `pwrite` into pre-allocated `.pdmpart` files; WebKit script handlers use weak proxies (`PDMWeakScriptMessageHandler`) to prevent retain cycles.
- **Zero Third-Party Supply Chain Risk:** 100% native Apple system frameworks and proprietary code — zero external CocoaPods, SPM, or third-party binaries.

## Reporting a Vulnerability

**Do NOT open a public GitHub issue for security vulnerabilities.**

To report a security issue privately:
1. Use GitHub's **Private Vulnerability Reporting** ("Security" tab → "Report a vulnerability") on the repository, or contact the repository owner directly via private channel.
2. Include the affected iOS version, PrismDM Browser version, clear reproduction steps, and potential impact.
3. We aim to acknowledge reports within **48 hours** and provide remediation guidance or a patch release promptly after verification.
