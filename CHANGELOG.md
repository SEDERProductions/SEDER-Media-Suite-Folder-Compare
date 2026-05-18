# Changelog

All notable changes to this project will be documented in this file.

## 0.2.0

Major feature release. Adds media-aware comparison, sync planner, rename detection,
a `sfc` CLI, ETA on the progress bar, and quality-of-life polish to the GUI.

### Added

- **Media-aware comparison.** Two new compare modes: `MediaMetadata` (compares
  image dimensions, EXIF DateTimeOriginal, video/audio duration, codec, sample
  rate) and `PerceptualHash` (image pHash with configurable Hamming tolerance,
  BLAKE3 fallback for non-image files). Powered by pure-Rust crates
  (`kamadak-exif`, `image`, `img_hash`, `symphonia`) so cross-platform builds
  stay clean.
- **Tolerances.** New `CompareTolerance` covers mtime drift, duration drift,
  and pHash Hamming distance, plumbed end-to-end through the core, FFI, and
  CLI.
- **Sync planner & executor.** New `SyncMode` (mirror A→B, mirror B→A, two-way
  newer/larger wins, two-way manual) with `ConflictStrategy` and dry-run.
  Reuses existing `transfer` primitives for the actual file operations.
- **Rename detection.** New `FileStatus::Renamed` plus a `detect_renames`
  pass that collapses `OnlyInA` + `OnlyInB` pairs sharing size and either
  BLAKE3 checksum or pHash similarity. Exposed as a sidebar toggle.
- **`sfc` CLI.** New binary with `compare`, `sync`, and `hash` subcommands.
  Text/CSV/JSON output, exit codes 0 (clean), 1 (differences), 2 (error).
- **ETA on progress bar.** Rolling 5s byte-throughput window in the
  controller surfaces an `etaText` label next to the progress bar during
  transfers.
- **Symlink handling toggle.** New "Follow symlinks" option in the sidebar
  (default off, persisted).
- **Recent folders.** Last 10 folders for both A and B persisted via
  `QSettings`; missing paths are pruned on load. Exposed as
  `recentFoldersA`/`recentFoldersB` properties.
- **Row context menu actions.** Right-click on a result row now offers
  open file (A/B), reveal in file manager (A/B), copy relative path, and
  copy absolute path (A/B). Reveal uses the native flow on each platform.
- **Text & hex diff helpers.** New `src/diff.rs` plus FFI bindings for a
  per-file content-diff view (text via `similar`, hex via windowed reads).
  UI surface deferred to a future point release.

### Changed

- `ProgressEvent` gained `bytes_done` / `bytes_total` fields used by the
  ETA tracker. The existing `ProgressEvent::new` constructor keeps callers
  source-compatible.
- `ScanOptions` gained `probe_media` and `follow_symlinks`; old callers can
  now use `..Default::default()`.
- `SfcCompareRequest` gained tolerance, follow-symlinks, and detect-renames
  fields. Existing C callers zero-initializing the struct continue to work
  (zeros fall back to defaults).
- Mode dropdown now lists five options including the two media-aware modes.

### Build / dev

- New Rust dependencies: `clap`, `serde`/`serde_json`, `similar`,
  `kamadak-exif`, `image`, `img_hash`, `symphonia`.
- 7 new lib tests for tolerance, rename detection, sync plan/execute,
  dry-run behavior, text diff, and hex window (27 total, all green).
- `cargo fmt --check`, `cargo clippy -D warnings`, and the Qt
  `compare-model-tests` are all green.

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

