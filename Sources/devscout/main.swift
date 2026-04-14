import Foundation

// MARK: - ANSI

let BOLD  = "\u{1B}[1m"
let DIM   = "\u{1B}[2m"
let R     = "\u{1B}[0m"
let RED   = "\u{1B}[31m"
let YEL   = "\u{1B}[33m"
let GRN   = "\u{1B}[32m"
let CYN   = "\u{1B}[36m"
let MAG   = "\u{1B}[35m"

// MARK: - Formatting helpers

let LINE_WIDTH = 62

func hr(_ ch: Character = "─") -> String {
    String(repeating: ch, count: LINE_WIDTH)
}

func fmtBytes(_ b: Int64) -> String {
    if b < 0 { return "—" }
    let mb = Double(b) / 1_048_576
    if mb < 1 { return "<1 MB" }
    if mb < 1024 { return String(format: "%.0f MB", mb) }
    return String(format: "%.2f GB", mb / 1024)
}

func colorFor(_ b: Int64) -> String {
    let gb = Double(b) / 1_073_741_824
    if gb > 5  { return RED }
    if gb > 1  { return YEL }
    return GRN
}

func bar(_ b: Int64, max m: Int64, width w: Int = 18) -> String {
    guard m > 0, b > 0 else { return String(repeating: "░", count: w) }
    let filled = min(Int(Double(b) / Double(m) * Double(w)), w)
    return String(repeating: "█", count: filled) + String(repeating: "░", count: w - filled)
}

// MARK: - Print report for one category

func printCategory(_ result: CategoryResult) {
    let existing = result.items.filter(\.exists)
    guard !existing.isEmpty else { return }

    let maxBytes = existing.map(\.bytes).max() ?? 1
    let totalStr = fmtBytes(result.total)
    let recStr   = result.reclaimable > 0
        ? "  \(GRN)reclaimable \(fmtBytes(result.reclaimable))\(R)"
        : ""

    // Category header
    print("\(BOLD)\(hr("═"))\(R)")
    let header = " \(result.category.icon)  \(BOLD)\(result.category.name)\(R)"
    let sizeLabel = "\(colorFor(result.total))\(BOLD)\(totalStr)\(R)\(recStr)"
    print("\(header)  \(sizeLabel)")
    print(hr())

    // Per-item rows
    for item in existing {
        let lbl  = item.target.label.rightPad(to: 24)
        let sz   = fmtBytes(item.bytes).leftPad(to: 8)
        let b    = bar(item.bytes, max: maxBytes)
        print("  \(lbl) \(colorFor(item.bytes))\(sz)\(R)  \(DIM)\(b)\(R)  \(item.target.safety.label)")
        print("  \(DIM)\(item.target.hint)\(R)")
        if let cmd = item.target.cleanup {
            print("  \(CYN)$ \(cmd)\(R)")
        }

        // Sub-items (deep analysis)
        if !item.subItems.isEmpty {
            let subMax = item.subItems.map(\.bytes).max() ?? 1
            print()
            for (i, sub) in item.subItems.enumerated() {
                let isLast  = i == item.subItems.count - 1
                let tree    = isLast ? "  └─ " : "  ├─ "
                let subLbl  = (tree + sub.label).rightPad(to: 32)
                let subSz   = fmtBytes(sub.bytes).leftPad(to: 8)
                let subBar  = bar(sub.bytes, max: subMax, width: 14)
                print("  \(DIM)\(subLbl)\(R) \(colorFor(sub.bytes))\(subSz)\(R)  \(DIM)\(subBar)\(R)  \(sub.safety.label)")
                if !sub.hint.isEmpty {
                    let indent = isLast ? "       " : "  │    "
                    print("  \(DIM)\(indent)\(sub.hint)\(R)")
                }
                if let cmd = sub.cleanup {
                    let indent = isLast ? "       " : "  │    "
                    print("  \(indent)\(CYN)$ \(cmd)\(R)")
                }
            }
        }

        print()
    }
}

// MARK: - Progress indicator (thread-safe)

let progressLock = NSLock()
var scannedCount = 0
let totalCount = allCategories.count

func onCategoryDone(_ name: String) {
    progressLock.lock()
    scannedCount += 1
    let done = scannedCount
    progressLock.unlock()
    let pct = Int(Double(done) / Double(totalCount) * 100)
    let filled = Int(Double(done) / Double(totalCount) * 20)
    let barStr = String(repeating: "█", count: filled) + String(repeating: "░", count: 20 - filled)
    // \r to overwrite the line
    print("\r  [\(barStr)] \(pct)%  \(name.rightPad(to: 20))", terminator: "")
    fflush(stdout)
}

// MARK: - Entry point

print()
print("\(BOLD)\(hr("═"))\(R)")
print("  DevScout · Developer Disk Analyzer · macOS")
print("\(BOLD)\(hr("═"))\(R)")
print()
print("  Scanning \(totalCount) categories in parallel...")
print()

let results = scanAll(categories: allCategories, onCategoryDone: onCategoryDone)

// Clear progress line
print("\r  \(String(repeating: " ", count: 55))\r", terminator: "")
fflush(stdout)

// Filter categories that have something and sort by total size descending
let activeResults = results
    .filter { $0.hasContent }
    .sorted { $0.total > $1.total }

print()
for result in activeResults {
    printCategory(result)
}

// Grand totals
let grandTotal      = activeResults.reduce(0) { $0 + $1.total }
let grandReclaimable = activeResults.reduce(0) { $0 + $1.reclaimable }
let grandSoft       = activeResults.reduce(0) { acc, r in
    acc + r.items.filter { $0.exists && $0.target.safety == .soft }.reduce(0) { $0 + $1.bytes }
}

print("\(BOLD)\(hr("═"))\(R)")
print("  Total found:                \(colorFor(grandTotal))\(BOLD)\(fmtBytes(grandTotal))\(R)")
print("  \(GRN)Safe to delete:             \(BOLD)\(fmtBytes(grandReclaimable))\(R)")
print("  \(YEL)Reclaimable after check:    \(BOLD)\(fmtBytes(grandSoft))\(R)")
print("  Total potential:            \(BOLD)\(fmtBytes(grandReclaimable + grandSoft))\(R)")
print("\(BOLD)\(hr("═"))\(R)")
print()
print("  \(DIM)Legend:  \(GRN)✓ safe to delete\(R)\(DIM)   — always recreatable, delete freely")
print("           \(YEL)⚠ verify first\(R)\(DIM)     — old versions, check before removing")
print("           \(CYN)✎ manual decision\(R)\(DIM)  — needs your judgement\(R)")
print()
