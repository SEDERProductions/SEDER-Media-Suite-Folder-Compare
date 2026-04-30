# SEDER Media Suite Folder Compare Qt Build

Folder Compare is a Qt 6/QML application with a Rust core library.

## macOS Setup

```sh
brew install qt cmake ninja rust
export CMAKE_PREFIX_PATH="$(brew --prefix qt)"
```

## Build

From `desktop/seder-folder-compare`:

```sh
cmake -S qt -B build/qt -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$(brew --prefix qt)"
cmake --build build/qt
```

The CMake build invokes Cargo to build the Rust static library, then links it into the Qt app.

## Run Tests

Rust core:

```sh
cargo test --manifest-path Cargo.toml
```

Qt model tests, after configuring CMake:

```sh
cmake --build build/qt --target compare-model-tests
ctest --test-dir build/qt --output-on-failure
```

## Notes

- Qt/CMake tools were not available on PATH in this environment during implementation, so the Qt sources and build structure were prepared but not locally compiled here.
- Heavy comparison work runs in a Qt worker thread and calls the Rust core through `include/seder_folder_compare.h`.
- Result rows are copied into `CompareResultTableModel`, and QML renders them through `TableView` so large reports stay virtualized.
- GitHub release builds are produced by tag-driven Actions workflows and published at `https://github.com/sederproductions/seder-folder-compare/releases/latest`.

## Manual Verification Targets

- 1k rows: confirm progress updates, filters, exports, and row striping remain immediate.
- 10k rows: confirm table scrolling stays smooth and filter changes do not trigger comparison work.
- 100k rows: confirm the UI thread remains responsive while Rust scans/checksums in the worker thread, and that QML creates delegates only for visible rows.
- Empty folders: expect a PASS-style empty result with no rows and exportable empty reports.
- Long paths: relative paths should elide in the center of the table and remain complete in TXT/CSV exports.
- Failures: missing folders, read errors, canceled folder/export dialogs, and canceled comparisons should update the status/log area without clearing a previous successful report unless a new run has started.
- Themes: verify `system`, `light`, and `dark`; system follows Qt's current color scheme through `QStyleHints`.
