# DevScout

A fast, native macOS CLI that finds developer disk hogs — build caches, SDK versions, emulator images, package caches — and tells you exactly what's safe to delete.

> [!NOTE]
> **DevScout never deletes anything.** It only shows what's there and suggests commands — you decide what to run.

```
══════════════════════════════════════════════════════════════
  DevScout · Developer Disk Analyzer · macOS
══════════════════════════════════════════════════════════════

  Scanning 13 categories in parallel...

══════════════════════════════════════════════════════════════
 🤖  Android                                         21.30 GB
──────────────────────────────────────────────────────────────
  Android SDK              13.53 GB  ██████████████████  ✎ manual decision
  Platform tools, NDK, build tools, emulators

    ├─ NDK 26.3.11579264    2.96 GB  ██████████████  ⚠ verify first
    │    Old NDK — check ndkVersion in your projects
    │    $ rm -rf "~/Library/Android/sdk/ndk/26.3.11579264"
    ├─ android-36 ps16k     2.84 GB  █████████████░  ⚠ verify first
    │    16KB page size image — only needed for page alignment testing
    ├─ NDK 27.0.12077973    2.41 GB  ███████████░░░  ✎ manual decision
    ...

══════════════════════════════════════════════════════════════
  Total found:                94.57 GB
  Safe to delete:             22.58 GB
  Reclaimable after check:    32.35 GB
  Total potential:            54.93 GB
══════════════════════════════════════════════════════════════
```

## What it scans

| Category | What's detected |
|---|---|
| 🔨 Xcode | DerivedData (per project), DeviceSupport (per iOS version), simulators (per device), archives |
| 🤖 Android | NDK versions, system images, build tools, cmake, AVD emulators |
| 🟩 Node.js | npm / yarn / pnpm caches, nvm / Volta node versions |
| 🦀 Rust | cargo registry, git deps, rustup toolchains |
| ☕ Java / Kotlin | Gradle caches, Gradle wrapper versions, Maven local repo |
| 🐍 Python | pyenv versions, pip cache, uv cache, virtualenvs |
| 💎 Ruby | rbenv versions, gems, CocoaPods cache and specs |
| 💙 Flutter / Dart | pub-cache |
| 🐹 Go | module cache, build cache |
| 📦 Swift PM | SwiftPM cache and checkouts |
| 🍺 Homebrew | Cellar, downloaded bottles |
| 🐳 Docker | images, containers, volumes |
| 📁 App Caches | ~/Library/Caches, simulator logs |

Each item is tagged:

- **✓ safe to delete** — build artifacts, always recreatable
- **⚠ verify first** — old versions, probably unused
- **✎ manual decision** — needs your judgment (active SDKs, emulators)

Deep analysis drills into subdirectories — NDK shows each version separately, Gradle shows each wrapper distribution, DerivedData shows each project — with the exact cleanup command.

## Requirements

- macOS 14+
- Swift 5.9+ (ships with Xcode or `xcode-select --install`)

## Install

### Run directly (no install)

```bash
git clone https://github.com/om1ji/devscout
cd devscout
swift run
```

### Install as a binary

```bash
git clone https://github.com/om1ji/devscout
cd devscout
swift build -c release
cp .build/release/devscout /usr/local/bin/devscout
```

Then just run `devscout` from anywhere.

## Roadmap

- [ ] **Windows support** ([#1](https://github.com/om1ji/devscout/issues/1)) — rewrite in Rust/Go for true cross-platform support with Windows-specific paths (NuGet, Visual Studio cache, etc.)
- [ ] `--json` output for scripting and third-party integrations
- [ ] `node_modules` scanner — find and sum across project directories
- [ ] Minimum size threshold flag (`--min 100mb`) to hide noise
- [ ] `--category <name>` flag to scan a single category

## How it works

- Scans all categories **in parallel** using GCD
- Measures each path with `du -sk` (fast, consistent with Finder)
- Deep-analysis runs concurrently within each category
- No network access, no sudo, read-only

## Adding a new category

1. Add a `Category` entry in `Sources/devscout/Categories.swift`
2. Optionally implement a `SubAnalyzer` in `Sources/devscout/SubAnalyzers.swift` for deep breakdown

## License

MIT
