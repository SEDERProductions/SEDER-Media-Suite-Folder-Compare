# Changelog

All notable changes to this project will be documented in this file.

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

