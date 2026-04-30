# Contributing

Thanks for helping improve SEDER Media Suite Folder Compare.

## License

By contributing, you agree that your contribution is licensed under `GPL-3.0-only`. No separate contributor license agreement is required.

## Development

Run the Rust checks before opening a pull request:

```sh
cargo fmt --check --manifest-path Cargo.toml
cargo clippy --manifest-path Cargo.toml -- -D warnings
cargo test --manifest-path Cargo.toml
```

With Qt 6 installed:

```sh
cmake -S qt -B build/qt -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build/qt
ctest --test-dir build/qt --output-on-failure
```

## Pull Requests

- Keep changes focused.
- Include tests for backend behavior and model changes where practical.
- Do not commit generated folders such as `target/`, `build/`, app bundles, ZIP files, or AppImages.
- Keep UI changes operational and compact; this app is a production utility, not a marketing page.

