---
name: build
description: Build the Pepper compiler with cargo. Use when asked to build, compile, or check the project, or when a build fails and you need to iterate on errors.
---

# Building Pepper

Pepper is a Rust workspace: root crate `pepper` (lib + `main.rs` CLI) plus the crates `pepper-parser`, `pepper-sema`, `pepper-codegen`, `pepper-support`, and `pepper-driver` under `crates/`. Plain `cargo` commands work; no special setup.

## Build

```bash
cargo build
```

- Binary lands at `target/debug/pepper.exe` (Windows) / `target/debug/pepper` (POSIX).
- Errors are `rustc` diagnostics in `crates/*/src` — read them, fix, rebuild. The first error in the output is the real one; later ones are often fallout, so fix top-down.
- `cargo check` is faster when you only need type/ownership errors; use it for quick iteration and `cargo build` for the actual binary.

## Release

```bash
cargo build --release   # output at target/release/pepper(.exe)
```

## Workspace targets

All commands accept `-p <crate>` to scope them, e.g. `cargo build -p pepper-parser`. Useful when working on one crate and you want fast feedback.

## Notes

- There is no configure step. `Cargo.toml`/`Cargo.lock` are the only build configuration.
- Never edit `Cargo.lock` by hand; dependency changes go through `Cargo.toml` + `cargo` commands.
