import Foundation

// MARK: - Measure a single path via `du -sk`

func measureSize(at path: String) -> Int64 {
    guard FileManager.default.fileExists(atPath: path) else { return -1 }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
    process.arguments = ["-sk", path]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()  // silence stderr
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return -1
    }
    let raw = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    // du output: "<kb>\t<path>"
    guard let kbStr = raw.split(separator: "\t").first,
          let kb = Int64(kbStr.trimmingCharacters(in: .whitespaces)) else { return 0 }
    return kb * 1024
}

// MARK: - Scan all categories in parallel

func scanAll(categories: [Category], onCategoryDone: @escaping (String) -> Void) -> [CategoryResult] {
    var results: [CategoryResult?] = Array(repeating: nil, count: categories.count)
    let resultsLock = NSLock()
    let outerGroup = DispatchGroup()
    let queue = DispatchQueue.global(qos: .userInitiated)

    for (i, category) in categories.enumerated() {
        outerGroup.enter()
        queue.async {
            // Scan all targets within the category in parallel
            var items: [ScannedTarget] = []
            let innerGroup = DispatchGroup()
            let itemsLock = NSLock()

            for target in category.targets {
                innerGroup.enter()
                queue.async {
                    let bytes = measureSize(at: target.path)
                    var subItems: [SubItem] = []
                    if bytes > 0, let analyzer = target.subAnalyzer {
                        subItems = analyzer.analyze(basePath: target.path)
                    }
                    itemsLock.lock()
                    items.append(ScannedTarget(target: target, bytes: bytes, subItems: subItems))
                    itemsLock.unlock()
                    innerGroup.leave()
                }
            }

            innerGroup.wait()
            items.sort { $0.bytes > $1.bytes }

            let result = CategoryResult(category: category, items: items)
            resultsLock.lock()
            results[i] = result
            resultsLock.unlock()

            onCategoryDone(category.name)
            outerGroup.leave()
        }
    }

    outerGroup.wait()
    return results.compactMap { $0 }
}
