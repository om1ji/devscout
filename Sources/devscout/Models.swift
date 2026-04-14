import Foundation

// MARK: - Safety level

enum Safety {
    case safe    // build caches, always recreatable — delete freely
    case soft    // old versions, probably unused — verify first
    case manual  // needs human decision — don't auto-delete

    var label: String {
        switch self {
        case .safe:   return "\u{1B}[32m✓ safe to delete\u{1B}[0m"
        case .soft:   return "\u{1B}[33m⚠ verify first\u{1B}[0m"
        case .manual: return "\u{1B}[36m✎ manual decision\u{1B}[0m"
        }
    }
}

// MARK: - Sub-analysis

struct SubItem {
    let label: String
    let path: String?
    let bytes: Int64
    let hint: String
    let cleanup: String?
    let safety: Safety
}

protocol SubAnalyzer {
    func analyze(basePath: String) -> [SubItem]
}

// MARK: - Data structures

struct Target {
    let label: String
    let path: String
    let hint: String
    let cleanup: String?
    let safety: Safety
    let subAnalyzer: SubAnalyzer?

    init(label: String, path: String, hint: String, cleanup: String?,
         safety: Safety, subAnalyzer: SubAnalyzer? = nil) {
        self.label = label; self.path = path; self.hint = hint
        self.cleanup = cleanup; self.safety = safety; self.subAnalyzer = subAnalyzer
    }
}

struct ScannedTarget {
    let target: Target
    let bytes: Int64        // -1 = path doesn't exist
    var subItems: [SubItem]

    var exists: Bool { bytes >= 0 }

    init(target: Target, bytes: Int64, subItems: [SubItem] = []) {
        self.target = target; self.bytes = bytes; self.subItems = subItems
    }
}

struct Category {
    let name: String
    let icon: String
    let targets: [Target]
}

struct CategoryResult {
    let category: Category
    let items: [ScannedTarget]

    var total: Int64 {
        items.filter(\.exists).reduce(0) { $0 + $1.bytes }
    }
    var reclaimable: Int64 {
        items.filter { $0.exists && $0.target.safety == .safe }.reduce(0) { $0 + $1.bytes }
    }
    var hasContent: Bool { items.contains(where: \.exists) }
}

// MARK: - String helpers

extension String {
    func leftPad(to length: Int) -> String {
        count >= length ? self : String(repeating: " ", count: length - count) + self
    }
    func rightPad(to length: Int) -> String {
        count >= length ? self : self + String(repeating: " ", count: length - count)
    }
}

func shortenPath(_ path: String) -> String {
    path.replacingOccurrences(of: HOME, with: "~")
}
