import Foundation

// MARK: - Shared helpers

func listSubdirs(in path: String) -> [(name: String, path: String)] {
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: path) else { return [] }
    return entries.compactMap { name -> (String, String)? in
        let full = path + "/" + name
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: full, isDirectory: &isDir),
              isDir.boolValue else { return nil }
        return (name, full)
    }.sorted { $0.0 < $1.0 }
}

// MARK: - Android SDK

struct AndroidSDKAnalyzer: SubAnalyzer {
    func analyze(basePath: String) -> [SubItem] {
        var items: [SubItem] = []

        // NDK — can have multiple versions
        let ndkPath = basePath + "/ndk"
        if FileManager.default.fileExists(atPath: ndkPath) {
            let dirs = listSubdirs(in: ndkPath).sorted { $0.name > $1.name }
            let latest = dirs.first?.name
            for d in dirs {
                guard let bytes = nonZero(measureSize(at: d.path)) else { continue }
                items.append(SubItem(
                    label: "NDK \(d.name)",
                    path: d.path,
                    bytes: bytes,
                    hint: d.name == latest ? "Latest NDK" : "Old NDK — check ndkVersion in your projects",
                    cleanup: d.name == latest ? nil : "rm -rf \"\(shortenPath(d.path))\"",
                    safety: d.name == latest ? .manual : .soft
                ))
            }
        }

        // System images — list by API level + variant
        let sysPath = basePath + "/system-images"
        if FileManager.default.fileExists(atPath: sysPath) {
            for api in listSubdirs(in: sysPath) {
                for variant in listSubdirs(in: api.path) {
                    guard let bytes = nonZero(measureSize(at: variant.path)) else { continue }
                    let isPs16k = variant.name.contains("ps16k")
                    let hint = isPs16k
                        ? "16KB page size image — only needed for page alignment testing"
                        : "Emulator image for \(api.name)"
                    items.append(SubItem(
                        label: "\(api.name)  \(variant.name)",
                        path: variant.path,
                        bytes: bytes,
                        hint: hint,
                        cleanup: nil,
                        safety: isPs16k ? .soft : .manual
                    ))
                }
            }
        }

        // Build tools — old versions usually safe to remove
        let btPath = basePath + "/build-tools"
        if FileManager.default.fileExists(atPath: btPath) {
            let versions = listSubdirs(in: btPath).sorted { $0.name > $1.name }
            let latest = versions.first?.name
            for v in versions {
                guard let bytes = nonZero(measureSize(at: v.path)) else { continue }
                let isLatest = v.name == latest
                items.append(SubItem(
                    label: "build-tools \(v.name)",
                    path: v.path,
                    bytes: bytes,
                    hint: isLatest ? "Current version" : "Old version — check buildToolsVersion in your projects",
                    cleanup: isLatest ? nil : "rm -rf \"\(shortenPath(v.path))\"",
                    safety: isLatest ? .manual : .soft
                ))
            }
        }

        // cmake — usually 1-2 versions
        let cmakePath = basePath + "/cmake"
        if FileManager.default.fileExists(atPath: cmakePath) {
            let versions = listSubdirs(in: cmakePath).sorted { $0.name > $1.name }
            let latest = versions.first?.name
            for v in versions {
                guard let bytes = nonZero(measureSize(at: v.path)) else { continue }
                items.append(SubItem(
                    label: "cmake \(v.name)",
                    path: v.path,
                    bytes: bytes,
                    hint: v.name == latest ? "Latest cmake" : "Old cmake version",
                    cleanup: v.name == latest ? nil : "rm -rf \"\(shortenPath(v.path))\"",
                    safety: v.name == latest ? .manual : .soft
                ))
            }
        }

        // Platforms
        let platformsPath = basePath + "/platforms"
        if FileManager.default.fileExists(atPath: platformsPath) {
            let versions = listSubdirs(in: platformsPath).sorted { $0.name > $1.name }
            let latest = versions.first?.name
            for p in versions {
                guard let bytes = nonZero(measureSize(at: p.path)) else { continue }
                items.append(SubItem(
                    label: p.name,
                    path: p.path,
                    bytes: bytes,
                    hint: p.name == latest ? "Current platform SDK" : "Old platform SDK",
                    cleanup: nil,
                    safety: p.name == latest ? .manual : .soft
                ))
            }
        }

        return items.sorted { $0.bytes > $1.bytes }
    }
}

// MARK: - Android AVD

struct AndroidAVDAnalyzer: SubAnalyzer {
    func analyze(basePath: String) -> [SubItem] {
        listSubdirs(in: basePath)
            .filter { $0.name.hasSuffix(".avd") }
            .compactMap { d -> SubItem? in
                guard let bytes = nonZero(measureSize(at: d.path)) else { return nil }
                let name = String(d.name.dropLast(4))  // strip ".avd"
                return SubItem(
                    label: name,
                    path: d.path,
                    bytes: bytes,
                    hint: "Emulator userdata (grows with usage)",
                    cleanup: "avdmanager delete avd -n \"\(name)\"",
                    safety: .manual
                )
            }
            .sorted { $0.bytes > $1.bytes }
    }
}

// MARK: - Xcode iOS/watchOS/visionOS DeviceSupport

struct XcodeDeviceSupportAnalyzer: SubAnalyzer {
    func analyze(basePath: String) -> [SubItem] {
        listSubdirs(in: basePath).compactMap { d -> SubItem? in
            guard let bytes = nonZero(measureSize(at: d.path)) else { return nil }
            return SubItem(
                label: d.name,
                path: d.path,
                bytes: bytes,
                hint: "Debug symbols for \(d.name) — only needed when actively debugging that OS version",
                cleanup: "rm -rf \"\(shortenPath(d.path))\"",
                safety: .soft
            )
        }.sorted { $0.bytes > $1.bytes }
    }
}

// MARK: - Xcode DerivedData

struct XcodeDerivedDataAnalyzer: SubAnalyzer {
    func analyze(basePath: String) -> [SubItem] {
        listSubdirs(in: basePath).compactMap { d -> SubItem? in
            guard let bytes = nonZero(measureSize(at: d.path)) else { return nil }
            // DerivedData dirs: "ProjectName-<hash>"
            let label = d.name.components(separatedBy: "-").dropLast().joined(separator: "-")
            return SubItem(
                label: label.isEmpty ? d.name : label,
                path: d.path,
                bytes: bytes,
                hint: "Xcode rebuilds this on next build",
                cleanup: "rm -rf \"\(shortenPath(d.path))\"",
                safety: .safe
            )
        }.sorted { $0.bytes > $1.bytes }
    }
}

// MARK: - Xcode CoreSimulator

struct XcodeSimulatorAnalyzer: SubAnalyzer {
    func analyze(basePath: String) -> [SubItem] {
        // Each subdir is a UUID — read device.plist for human name
        return listSubdirs(in: basePath).compactMap { d -> SubItem? in
            guard let bytes = nonZero(measureSize(at: d.path)) else { return nil }
            // Try to get device name from plist
            let plistPath = d.path + "/device.plist"
            var name = d.name
            if let plist = NSDictionary(contentsOfFile: plistPath),
               let n = plist["name"] as? String,
               let rt = plist["runtime"] as? String {
                let runtimeShort = rt.components(separatedBy: ".").last ?? rt
                name = "\(n) · \(runtimeShort)"
            }
            return SubItem(
                label: name,
                path: d.path,
                bytes: bytes,
                hint: "Simulator data",
                cleanup: "xcrun simctl delete \(d.name)",
                safety: .soft
            )
        }.sorted { $0.bytes > $1.bytes }
    }
}

// MARK: - Gradle Wrapper dists

struct GradleWrapperAnalyzer: SubAnalyzer {
    func analyze(basePath: String) -> [SubItem] {
        let versions = listSubdirs(in: basePath).sorted { $0.name > $1.name }
        let latest = versions.first?.name
        return versions.compactMap { d -> SubItem? in
            guard let bytes = nonZero(measureSize(at: d.path)) else { return nil }
            let isLatest = d.name == latest
            return SubItem(
                label: d.name,
                path: d.path,
                bytes: bytes,
                hint: isLatest ? "Latest Gradle version" : "Old version — check if any project still requires it",
                cleanup: isLatest ? nil : "rm -rf \"\(shortenPath(d.path))\"",
                safety: isLatest ? .manual : .soft
            )
        }.sorted { $0.bytes > $1.bytes }
    }
}

// MARK: - Rustup toolchains

struct RustupToolchainsAnalyzer: SubAnalyzer {
    func analyze(basePath: String) -> [SubItem] {
        listSubdirs(in: basePath).compactMap { d -> SubItem? in
            guard let bytes = nonZero(measureSize(at: d.path)) else { return nil }
            let isStable  = d.name.hasPrefix("stable")
            let isNightly = d.name.hasPrefix("nightly")
            let kind = isStable ? "stable" : isNightly ? "nightly" : "custom"
            // rustup toolchain uninstall needs the short name (stable-aarch64-apple-darwin → stable)
            let shortName = d.name.components(separatedBy: "-").prefix(3).joined(separator: "-")
            return SubItem(
                label: d.name,
                path: d.path,
                bytes: bytes,
                hint: "\(kind) toolchain",
                cleanup: "rustup toolchain uninstall \(shortName)",
                safety: .manual
            )
        }.sorted { $0.bytes > $1.bytes }
    }
}

// MARK: - NVM Node versions

struct NVMNodeAnalyzer: SubAnalyzer {
    func analyze(basePath: String) -> [SubItem] {
        let versions = listSubdirs(in: basePath).sorted { $0.name > $1.name }
        let latest = versions.first?.name
        return versions.compactMap { d -> SubItem? in
            guard let bytes = nonZero(measureSize(at: d.path)) else { return nil }
            return SubItem(
                label: "Node \(d.name)",
                path: d.path,
                bytes: bytes,
                hint: d.name == latest ? "Latest installed version" : "Old version — check .nvmrc files in your projects",
                cleanup: "nvm uninstall \(d.name)",
                safety: d.name == latest ? .manual : .soft
            )
        }.sorted { $0.bytes > $1.bytes }
    }
}

// MARK: - pyenv Python versions

struct PyenvVersionsAnalyzer: SubAnalyzer {
    func analyze(basePath: String) -> [SubItem] {
        let versions = listSubdirs(in: basePath).sorted { $0.name > $1.name }
        let latest = versions.first?.name
        return versions.compactMap { d -> SubItem? in
            guard let bytes = nonZero(measureSize(at: d.path)) else { return nil }
            return SubItem(
                label: "Python \(d.name)",
                path: d.path,
                bytes: bytes,
                hint: d.name == latest ? "Latest installed version" : "Old Python version",
                cleanup: "pyenv uninstall \(d.name)",
                safety: d.name == latest ? .manual : .soft
            )
        }.sorted { $0.bytes > $1.bytes }
    }
}

// MARK: - rbenv Ruby versions

struct RbenvVersionsAnalyzer: SubAnalyzer {
    func analyze(basePath: String) -> [SubItem] {
        let versions = listSubdirs(in: basePath).sorted { $0.name > $1.name }
        let latest = versions.first?.name
        return versions.compactMap { d -> SubItem? in
            guard let bytes = nonZero(measureSize(at: d.path)) else { return nil }
            return SubItem(
                label: "Ruby \(d.name)",
                path: d.path,
                bytes: bytes,
                hint: d.name == latest ? "Latest installed version" : "Old Ruby version",
                cleanup: "rbenv uninstall \(d.name)",
                safety: d.name == latest ? .manual : .soft
            )
        }.sorted { $0.bytes > $1.bytes }
    }
}

// MARK: - Helper

private func nonZero(_ b: Int64) -> Int64? {
    b > 0 ? b : nil
}
