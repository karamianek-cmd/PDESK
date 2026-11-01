# ParsiDesk — notes for Claude

ParsiDesk is Parsipol's Persian fork of RustDesk, shipped for Windows 10/11 (x64) and Android only. Server: `desk.parsipol.com` (preconfigured).

`AGENTS.md` is the upstream RustDesk guide and is not loaded automatically. Read only the section you need:
- Rust, Tokio or logging work: "Rust Rules", "Tokio Rules"
- New FFI functions: "Flutter Rust Bridge"
- Before calling a change done: "Mandatory regression-surface check"
- Skip "Web (Flutter Web) Architecture" and "Reviewing a PR"; they don't apply here.

## Layout
- `src/` Rust app (`src/server/` media/input/network, `src/platform/` OS-specific, `src/flutter_ffi.rs` FFI). `src/ui/` is the deprecated Sciter UI: don't edit it.
- `flutter/lib/` UI: `desktop/`, `mobile/`, shared `common/` and `models/`.
- `libs/base` holds client-only code and option keys (`libs/base/src/config/keys.rs`). `libs/hbb_common` is an upstream submodule: avoid changing it.
- Languages: only Persian (`src/lang/fa.rs`, the default) and English (`src/lang/en.rs`) are built. The other files in `src/lang/` are unused upstream leftovers: never open, search or edit them, and don't re-add them to `src/lang.rs` or `supportedLocales` in `flutter/lib/common.dart`.

## Always
- Smallest valid diff. No refactors, formatting-only changes or unrelated fixes; prefer additive, feature-local code with thin hooks in shared files.
- No `unwrap()`/`expect()` in production code. Don't hold locks across `.await`, nest runtimes, or `block_on` in async code.
- Never run `flutter_rust_bridge_codegen`; hand-write Dart wrappers for new FFI functions.
- New UI strings: use a sentence-case English key and add its Persian translation at the end of `fa.rs`. Add an `en.rs` entry only when the English text must differ from the key. Keep `{}` placeholders.

## Builds
- Builds run in GitHub Actions, not locally: `.github/workflows/client-builds.yml` runs on a push to `client-builds` that changes `.build-trigger`. Append a line to `.build-trigger` to rebuild, and only when asked.
- Toolchains (Flutter, Rust, JDK, LLVM) live in `F:\ParsiDev`; built artifacts land in `F:\ParsiDev\release`.

## Saving tokens
- Don't read or search `target/`, `flutter/build/`, `flutter/.dart_tool/`, generated bridge files, or `Cargo.lock`.
- `fa.rs` is about 75 KB: grep for a key rather than reading the whole file.
- Workflow YAML is large: grep for the job or step you need rather than reading it all.
