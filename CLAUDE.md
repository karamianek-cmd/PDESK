# ParsiDesk — notes for Claude

ParsiDesk is Parsipol's Persian fork of RustDesk, shipped for Windows 10/11 (x64) and Android only. Server: `desk.parsipol.com` (preconfigured).

`AGENTS.md` is the upstream RustDesk guide and is not loaded automatically. Read only the section you need:
- Rust, Tokio or logging work: "Rust Rules", "Tokio Rules"
- New FFI functions: "Flutter Rust Bridge"
- Translations or new UI strings: "Localization"
- Before calling a change done: "Mandatory regression-surface check"
- Skip "Web (Flutter Web) Architecture" and "Reviewing a PR"; they don't apply here.

## Layout
- `src/` Rust app (`src/server/` media/input/network, `src/platform/` OS-specific, `src/flutter_ffi.rs` FFI). `src/ui/` is the deprecated Sciter UI: don't edit it.
- `flutter/lib/` UI: `desktop/`, `mobile/`, shared `common/` and `models/`.
- `libs/base` holds client-only code and option keys (`libs/base/src/config/keys.rs`). `libs/hbb_common` is an upstream submodule: avoid changing it.
- `src/lang/fa.rs` is the Persian translation (the main one). `template.rs` is the master key list.

## Always
- Smallest valid diff. No refactors, formatting-only changes or unrelated fixes; prefer additive, feature-local code with thin hooks in shared files.
- No `unwrap()`/`expect()` in production code. Don't hold locks across `.await`, nest runtimes, or `block_on` in async code.
- Never run `flutter_rust_bridge_codegen`; hand-write Dart wrappers for new FFI functions.
- New UI strings: sentence-case key appended to `template.rs` and every `src/lang/*.rs` file (Persian filled in `fa.rs`, `""` elsewhere).

## Builds
- Builds run in GitHub Actions, not locally: `.github/workflows/client-builds.yml` runs on a push to `client-builds` that changes `.build-trigger`. Append a line to `.build-trigger` to rebuild, and only when asked.
- Toolchains (Flutter, Rust, JDK, LLVM) live in `F:\ParsiDev`; built artifacts land in `F:\ParsiDev\release`.

## Saving tokens
- Don't read or search `target/`, `flutter/build/`, `flutter/.dart_tool/`, generated bridge files, or `Cargo.lock`.
- `src/lang/` has 55 large files: open only the one you need, and grep for a key rather than reading a whole file.
- Workflow YAML is large: grep for the job or step you need rather than reading it all.
