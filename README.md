# SEDER Media Suite Folder Compare

[![CI](https://github.com/sederproductions/seder-folder-compare/actions/workflows/ci.yml/badge.svg)](https://github.com/sederproductions/seder-folder-compare/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/sederproductions/seder-folder-compare?label=download)](https://github.com/sederproductions/seder-folder-compare/releases/latest)
[![License: GPL-3.0-only](https://img.shields.io/badge/license-GPL--3.0--only-blue.svg)](LICENSE)

SEDER Media Suite Folder Compare is a local-first desktop utility for recursively comparing two folders in post-production, editorial, DIT, and archive workflows.

## Download

Download the latest macOS, Windows, and Linux builds from:

[GitHub Releases](https://github.com/sederproductions/seder-folder-compare/releases/latest)

Builds are ad-hoc signed by SEDER Productions for tamper-detection. On macOS, you may still need to right-click the app → Open the first time, or approve it in **System Settings > Privacy & Security**. Windows SmartScreen will show a "More info → Run anyway" prompt — Apple notarization and a paid Windows Authenticode certificate are not configured.

## Features

- Native Qt 6/QML interface with dense production-style controls.
- Rust core for local recursive scanning, checksums, and report generation.
- Compare modes: path + size, path + size + modified time, and path + size + checksum.
- Ignore hidden/system files and comma-separated ignore patterns.
- Background comparison worker so the UI stays responsive.
- Virtualized Qt table model for large result sets.
- Filters for all, matching, changed, only A, only B, and folders.
- TXT and CSV report export.

All processing is local. The app does not upload folders, file names, checksums, or reports.

## Build From Source

Install Rust, CMake, Ninja, and Qt 6.5 or newer.

macOS:

```sh
brew install rust cmake ninja qt
export CMAKE_PREFIX_PATH="$(brew --prefix qt)"
```

Linux:

```sh
sudo apt-get update
sudo apt-get install -y build-essential cmake ninja-build qt6-base-dev qt6-declarative-dev qt6-tools-dev
```

Configure and build:

```sh
cmake -S qt -B build/qt -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build/qt
```

Run tests:

```sh
cargo fmt --check --manifest-path Cargo.toml
cargo clippy --manifest-path Cargo.toml -- -D warnings
cargo test --manifest-path Cargo.toml
ctest --test-dir build/qt --output-on-failure
```

## Release Process

Releases are tag-driven. Pushing a tag like `v0.1.0` starts GitHub Actions on standard hosted runners:

- `macos-latest` builds a zipped `.app`.
- `windows-latest` builds a zipped Windows folder.
- `ubuntu-22.04` builds an AppImage.

The workflow uploads release assets and `SHA256SUMS.txt` to the matching GitHub Release.

## Project Layout

- `src/` - Rust comparison core and C ABI.
- `include/` - public C header used by Qt.
- `qt/` - Qt 6/C++/QML application shell, models, worker, and tests.
- `assets/` - application icon and intentional static assets.
- `.github/` - CI, release automation, and contribution templates.

## License

Code is licensed under `GPL-3.0-only`. See [LICENSE](LICENSE).

The SEDER and Seder Productions names, logos, and marks are not granted as trademarks by the GPL license. See [TRADEMARKS.md](TRADEMARKS.md).

