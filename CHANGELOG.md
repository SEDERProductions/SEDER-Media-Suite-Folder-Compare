# Changelog

All notable changes to this project will be documented in this file.

## 0.1.25

- Fixed `QtObject`-illegal `Connections` child that prevented Main.qml from loading on Qt 6.4.
- Fixed application version reported to QML and the about label (was hard-coded to `0.1.4`); the QML preprocessor macro and CMake project version now agree with Cargo.toml.
- Corrected repository URL in README badges/links and `Cargo.toml` to `SEDERProductions/SEDER-Media-Suite-Folder-Compare`.
- Pinned Qt to 6.4.2 across CI and release workflows for deterministic builds.

## 0.1.5 – 0.1.24

- Redesigned folder picker and tree view UI; added comparison tree expand/collapse model.
- Added copy/move-to-A/B actions with overwrite confirmation and undo.
- Surfaced the app version to QML; added platform-aware StandardKey shortcuts and hints.
- Improved QML legibility and secondary contrast; made layout responsive at smaller window sizes; capped window size to screen bounds and centered on startup.
- Validated `FolderCompareController` mode range and refactored property-setter patterns.
- Hardened drop handling: use Qt URL conversion for dropped folder paths with explicit validation.
- Consolidated icon assets around a canonical SVG source.
- Added partial-transfer cleanup, deterministic timestamp test, and additional code-quality fixes.
- CI/build: applied clang-format across qt sources/tests, fixed include ordering, removed unused includes; updated CI actions (checkout v6, upload/download-artifact, action-gh-release v3); added concurrency control and rebase to prevent release race conditions.

## 0.1.4

- Removed non-functional sidebar rail.
- Fixed progress bar to reflect actual comparison progress.
- Extended thread shutdown timeout to prevent crashes on large datasets.
- Synced version numbers across Cargo.toml, CMakeLists.txt, and QML.
- Fixed CSV export status format.
- Added clang-format and cargo-audit to CI.
- Added test coverage for missing filter modes and PathSizeModified comparison.
- Deduplicated `takeError` helper into shared utility header.

## 0.1.3

- Added application icon for macOS, Windows, and Linux.

## 0.1.2

- Added cancel comparison support.
- Improved progress reporting during scan and checksum phases.

## 0.1.1

- Added drag-and-drop folder selection.
- Improved ignore pattern handling.

## 0.1.0 - Initial Open Source Release

- Added Qt 6/QML desktop app for Folder Compare.
- Added Rust core for scanning, checksums, comparison, filtering data, and report export.
- Added C ABI for the Qt backend.
- Added GitHub Actions CI and tag-driven release packaging for macOS, Windows, and Linux.

