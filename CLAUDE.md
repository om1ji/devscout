# DevScout — CLAUDE.md

Native macOS CLI (Swift) that scans developer directories and reports disk usage with safety ratings and cleanup commands.

**Repo:** https://github.com/om1ji/devscout  
**Location:** `~/Documents/Personal Projects/devscout`  
**Run:** `swift run` from project root  
**Install:** `swift build -c release && cp .build/release/devscout /usr/local/bin/devscout`

## Architecture

```
Sources/devscout/
├── main.swift          # Entry point, ANSI formatting, output rendering
├── Models.swift        # Safety enum, Target, ScannedTarget, Category, CategoryResult, SubItem, SubAnalyzer protocol
├── Categories.swift    # allCategories: [Category] — all scan targets with paths, hints, safety, cleanup commands
├── Scanner.swift       # measureSize(at:) via `du -sk`, scanAll() with GCD parallel scanning
└── SubAnalyzers.swift  # Concrete SubAnalyzer implementations per technology
```

### Data flow

```
allCategories → scanAll() → [CategoryResult] → printCategory() → stdout
                    └─ per target: measureSize() + SubAnalyzer.analyze() run concurrently
```

### Key types

```swift
// Safety rating shown next to each item
enum Safety { case safe, soft, manual }

// A path to scan, with metadata
struct Target {
    label, path, hint, cleanup: String?
    safety: Safety
    subAnalyzer: SubAnalyzer?   // optional deep-dive
}

// Result of scanning one Target
struct ScannedTarget {
    target: Target
    bytes: Int64        // -1 = path doesn't exist
    subItems: [SubItem] // populated if subAnalyzer present
}

// One entry inside a SubAnalyzer result
struct SubItem { label, path, bytes, hint, cleanup, safety }

protocol SubAnalyzer {
    func analyze(basePath: String) -> [SubItem]
}
```

## Extending

### Add a new scan category

Edit `Categories.swift`, append to `allCategories`:

```swift
.init(name: "MyTool", icon: "🔧", targets: [
    .init(label: "cache",
          path: "\(HOME)/.mytool/cache",
          hint: "MyTool package cache",
          cleanup: "mytool cache clean",
          safety: .safe),
])
```

### Add deep analysis to a target

1. Implement `SubAnalyzer` in `SubAnalyzers.swift`:

```swift
struct MyToolAnalyzer: SubAnalyzer {
    func analyze(basePath: String) -> [SubItem] {
        listSubdirs(in: basePath).compactMap { d in
            guard let bytes = nonZero(measureSize(at: d.path)) else { return nil }
            return SubItem(label: d.name, path: d.path, bytes: bytes,
                           hint: "...", cleanup: "...", safety: .soft)
        }.sorted { $0.bytes > $1.bytes }
    }
}
```

2. Pass it in `Categories.swift`:

```swift
.init(label: "versions", path: "...", ..., subAnalyzer: MyToolAnalyzer())
```

### Helpers available in SubAnalyzers

- `listSubdirs(in path: String) -> [(name, path)]` — immediate subdirectories
- `measureSize(at path: String) -> Int64` — calls `du -sk`, returns bytes (-1 if missing)
- `shortenPath(_ path: String) -> String` — replaces home dir with `~`
- `nonZero(_ b: Int64) -> Int64?` — private, filters out 0-byte results

## Existing SubAnalyzers

| Struct | Target |
|---|---|
| `AndroidSDKAnalyzer` | NDK versions, system images, build-tools, cmake, platforms |
| `AndroidAVDAnalyzer` | AVD emulator images |
| `XcodeDeviceSupportAnalyzer` | DeviceSupport by OS version |
| `XcodeDerivedDataAnalyzer` | DerivedData by project name |
| `XcodeSimulatorAnalyzer` | CoreSimulator devices (reads device.plist for names) |
| `GradleWrapperAnalyzer` | Gradle wrapper distributions |
| `RustupToolchainsAnalyzer` | rustup toolchains |
| `NVMNodeAnalyzer` | nvm Node versions |
| `PyenvVersionsAnalyzer` | pyenv Python versions |
| `RbenvVersionsAnalyzer` | rbenv Ruby versions |

## Known issues / future ideas

- DerivedData shows duplicate "Runner" labels (Flutter projects all use Runner — hash stripped by design, cosmetic issue)
- Sub-items have no minimum size threshold — tiny items clutter output (add `bytes > 1_048_576` filter?)
- No `--json` output mode for scripting
- Could add `node_modules` scanner (find + sum across project directories)
- Docker: `docker system df` would give more accurate image/volume breakdown than `du` on the container dir
- Could add `--category android` flag to show only one category
