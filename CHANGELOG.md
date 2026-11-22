# Changelog

All notable changes to **PrismDM Browser** are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and Semantic Versioning.

## [1.0.0] — 2026-11-22

### Added
- **Flagship Liquid Glass Design System (`PDMTheme`, `PDMUI`):**
  - Bespoke 3D Liquid Glass crystal prism & downward chevron `AppIcon1024.png` + full iPhone & iPad icon generation pipeline.
  - 6 live-switchable themes with zero restart: *Liquid Glass (Default)*, *Obsidian OLED*, *Brave Ember*, *Chrome Minimal*, *Arctic Glacier*, and *Cyber Midnight*.
  - 3 live-switchable browser chrome presets: *Liquid Floating Bottom Bar*, *Chrome Minimal Top Bar*, and *Compact Power Bar*.
  - Custom Liquid Glass bottom sheets (`UISheetPresentationController`) replacing stock alert walls across all core workflows.
- **Brave-Style Privacy Shields & Power Browser (`PDMBrowser`, `PDMPrivacyShield`, `PDMTabGrid`):**
  - Native `WKContentRuleList` ad, tracker, malvertising, and optional third-party script blocker.
  - Cosmetic ad & cookie-banner hider, popup/redirect blocker, automatic HTTP → HTTPS upgrade, Force Dark Mode, and Distraction-Free Reader Mode.
  - Visual Card Tab Grid (2-column iPhone / 4-column iPad) with real `WKWebView` snapshots, live search, Reopen Last Closed Tab, and Face ID–locked Private Tabs (`WKWebsiteDataStore.nonPersistentDataStore`).
  - Speed Dial Start Page with live privacy/speed counters, instant Search Engine switcher, pinned tiles, clipboard quick-paste, and Active Downloads mini-card.
  - Find in Page, Bookmarks Manager with JSON export/import, Searchable History, Save Webpage as PDF, and Clear Browsing Data on Exit.
- **Live Media Sniffer & Liquid Glass Quality / Multi-Audio / Format Picker (`PDMMediaSniffer`):**
  - Real-time DOM/fetch/XHR/media-element sniffer detecting HLS (`.m3u8`), DASH (`.mpd`), MP4, MOV, WebM, MKV, MP3, M4A, FLAC, WAV, and Opus streams with automatic Referer/User-Agent/Cookie capture.
  - Full `#EXT-X-MEDIA:TYPE=AUDIO` multi-audio & `#EXT-X-STREAM-INF` video variant parser with FairPlay DRM alerting and clear-key AES-128 detection.
  - Page Resource Grabber ("Grab All Media & Links") with category filter chips and batch queueing.
- **Multi-Segment IDM / 1DM Download Manager & Auto-Transcoder (`PDMDownloadManager`, `PDMTranscoder`):**
  - True 2/4/8/16-part parallel downloads written directly via POSIX `open`/`ftruncate`/`pwrite`/`fsync`/`close` into `.pdmpart` files with full restart-safe pause/resume and Refresh Download Address.
  - Concurrent HLS video + multi-audio downloader with `CommonCrypto` AES-128 clear-key decryption and `AVMutableComposition` muxing.
  - Automatic post-download format & encoding conversion (`MP4 H.264/HEVC`, `MOV`, `M4V`, `M4A AAC/ALAC`, `FLAC`, `WAV`, plus 100% proprietary pure-C ISO/IEC 11172-3 `MP3` encoder).
  - Zero-idle-drain telemetry timer, optional speed limiter, Wi-Fi-only guard (`getifaddrs`), and Batch URL Importer.
- **Built-in Liquid Glass Pro Media Player & Offline Library (`PDMMediaPlayer`, `PDMLibrary`):**
  - Live in-player Multi-Audio track switcher, HLS quality/bitrate switcher, Captions picker, Floating Picture-in-Picture, Lock Screen Now Playing controls, AirPlay, double-tap ±10s seek, and brightness/volume gestures.
  - Categorized Offline Library with Face ID–protected Private Downloads Vault, pure-C `zlib` `.zip` extractor, `CC_SHA256` checksum verifier, video compression, and audio extraction.
- **Strict Proprietary Licensing & Xcode 26 CI Pipeline:**
  - Closed-source `LICENSE` (*All Rights Reserved*), copyright headers across all sources, About & Legal screen, `build.sh`, `tests/run_all_tests.sh`, Python static verifier, and GitHub Actions workflow.
