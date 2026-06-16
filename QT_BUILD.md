# SEDER Media Suite Folder Compare Qt Build

Folder Compare is a **Qt 6.5+/QML** application with a Rust core library.

## macOS Setup

```sh
brew install qt cmake ninja rust
export CMAKE_PREFIX_PATH="$(brew --prefix qt)"
```

## Build

From the repository root:

Regenerate application icons from the canonical source asset (`assets/icon.svg`):

```sh
python3 scripts/generate-icons.py .
```

Then configure/build:

```sh
cmake -S qt -B build/qt -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$(brew --prefix qt)"
cmake --build build/qt
```

The CMake build invokes Cargo to build the Rust static library, then links it into the Qt app.

## UI architecture

The front end is an Adobe-grade QML app organized as a proper Qt QML module (`URI Seder.UI`,
declared in `qt/CMakeLists.txt` and loaded via `engine.loadFromModule` in `qt/src/main.cpp`).

- `qt/qml/theme/Theme.qml` — `pragma Singleton` design-token system: colors (warm dark/light
  palette), spacing/radius/typography/motion/elevation scales, and status helpers. `Theme.dark`
  is bound once to `folderController.effectiveDark`.
- `qt/qml/components/` — reusable, themed controls (`AppButton`, `AppComboBox`, `AppCheckBox`,
  `AppTextField`, `SectionLabel`, `MetricBox`, `FolderPicker`), the `Icon` system, and `DockPanel`.
  `Icon.qml` renders crisp, recolorable line icons via `QtQuick.Shapes` from path data in the
  generated `IconPaths.qml` (run `python3 scripts/generate-icon-paths.py` to regenerate from
  Lucide, MIT).
- Dockable workspace: `Main.qml` hosts nested `SplitView`s of `DockPanel`s (SETTINGS / RESULTS /
  PREVIEW / CONSOLE) on a gutter. Panels resize, collapse, and tear off into floating `Window`s;
  a top WORKSPACE bar offers Compare/Review/Triage presets, persisted via
  `FolderCompareController::saveLayout/loadLayout` (QSettings).
- Media preview: `qt/src/ThumbnailImageProvider` (a `QQuickAsyncImageProvider` with a disk cache)
  serves `image://thumb/<path>`; `MediaPreviewPanel.qml` shows side-by-side A/B with a metadata
  strip fed by the additive `sfc_media_probe` FFI (`src/ffi.rs`, wrapping `src/media.rs`).
- Command palette: `Ctrl/Cmd+K` opens a filterable action list in `Main.qml`.

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

- Requires Qt 6.5+ (uses `qt_add_qml_module` + `loadFromModule`, `QtQuick.Shapes`, and an
  async image provider). CI and release workflows install Qt 6.5.3.
- Heavy comparison work runs in a Qt worker thread and calls the Rust core through `include/seder_folder_compare.h`.
- Result rows are copied into `CompareResultTableModel`; the results panel renders them through a
  virtualized `ListView` tree (list view) or a `GridView` of thumbnail cards (grid view), so large
  reports stay responsive and delegates are created only for visible rows.
- GitHub release builds are produced by tag-driven Actions workflows and published at `https://github.com/sederproductions/seder-folder-compare/releases/latest`.

## Manual Verification Targets

- 1k rows: confirm progress updates, filters, exports, and row striping remain immediate.
- 10k rows: confirm table scrolling stays smooth and filter changes do not trigger comparison work.
- 100k rows: confirm the UI thread remains responsive while Rust scans/checksums in the worker thread, and that QML creates delegates only for visible rows.
- Empty folders: expect a PASS-style empty result with no rows and exportable empty reports.
- Long paths: relative paths should elide in the center of the table and remain complete in TXT/CSV exports.
- Failures: missing folders, read errors, canceled folder/export dialogs, and canceled comparisons should update the status/log area without clearing a previous successful report unless a new run has started.
- Themes: verify `system`, `light`, and `dark`; system follows Qt's current color scheme through `QStyleHints`.
