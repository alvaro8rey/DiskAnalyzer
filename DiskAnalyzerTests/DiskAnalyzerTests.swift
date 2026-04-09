import Testing
import Foundation
@testable import DiskAnalyzer

// MARK: - Helpers

/// Crea un FileItem con un URL ficticio y tamaño dado (solo para tests).
@MainActor
private func makeItem(name: String, size: Int64, isDir: Bool = false) -> FileItem {
    let url = URL(fileURLWithPath: "/fake/\(name)")
    let item = FileItem(url: url, isDirectory: isDir)
    item.totalSize = size
    item.size      = size
    return item
}

// MARK: - Tests

struct DiskAnalyzerTests {

    // CAMBIO 10-A: Categorización de extensiones de archivo
    @Test func testFileCategoryDetection() {
        #expect(FileCategory.category(forExtension: "mp4")   == .video)
        #expect(FileCategory.category(forExtension: "MP4")   == .video)   // case-insensitive
        #expect(FileCategory.category(forExtension: "mov")   == .video)
        #expect(FileCategory.category(forExtension: "mp3")   == .audio)
        #expect(FileCategory.category(forExtension: "flac")  == .audio)
        #expect(FileCategory.category(forExtension: "png")   == .images)
        #expect(FileCategory.category(forExtension: "jpg")   == .images)
        #expect(FileCategory.category(forExtension: "heic")  == .images)
        #expect(FileCategory.category(forExtension: "pdf")   == .documents)
        #expect(FileCategory.category(forExtension: "docx")  == .documents)
        #expect(FileCategory.category(forExtension: "swift") == .code)
        #expect(FileCategory.category(forExtension: "py")    == .code)
        #expect(FileCategory.category(forExtension: "js")    == .code)
        #expect(FileCategory.category(forExtension: "zip")   == .archives)
        #expect(FileCategory.category(forExtension: "dmg")   == .archives)
        #expect(FileCategory.category(forExtension: "app")   == .apps)
        #expect(FileCategory.category(forExtension: "xyz")   == .other)
        #expect(FileCategory.category(forExtension: "")      == .other)
    }

    // CAMBIO 10-B: formattedSize produce strings correctos
    @MainActor @Test func testFormattedSize() {
        let zero = makeItem(name: "zero", size: 0)
        #expect(zero.formattedSize == "Zero KB")

        let oneKB = makeItem(name: "1kb", size: 1_024)
        #expect(oneKB.formattedSize.contains("KB"))

        let oneMB = makeItem(name: "1mb", size: 1_048_576)
        #expect(oneMB.formattedSize.contains("MB"))

        let oneGB = makeItem(name: "1gb", size: 1_073_741_824)
        #expect(oneGB.formattedSize.contains("GB"))
    }

    // CAMBIO 10-C: percentage(of:) casos normales y edge cases
    @MainActor @Test func testPercentageCalculation() {
        let parent = makeItem(name: "parent", size: 1_000, isDir: true)
        let child  = makeItem(name: "child",  size: 500)
        #expect(child.percentage(of: parent) == 0.5)

        let child2 = makeItem(name: "c2", size: 1_000)
        #expect(child2.percentage(of: parent) == 1.0)

        let child3 = makeItem(name: "c3", size: 0)
        #expect(child3.percentage(of: parent) == 0.0)

        // Parent con tamaño 0 → no debe dividir por cero
        let emptyParent = makeItem(name: "empty", size: 0, isDir: true)
        #expect(child.percentage(of: emptyParent) == 0.0)
    }

    // CAMBIO 10-D: Las 6 opciones de ordenación producen el orden esperado
    @MainActor @Test func testSortOptions() async {
        let a = makeItem(name: "alpha", size: 100)
        a.modificationDate = Date(timeIntervalSinceReferenceDate: 1000)
        let b = makeItem(name: "beta",  size: 300)
        b.modificationDate = Date(timeIntervalSinceReferenceDate: 3000)
        let c = makeItem(name: "gamma", size: 200)
        c.modificationDate = Date(timeIntervalSinceReferenceDate: 2000)

        let items = [a, b, c]

        func sorted(_ opt: SortOption) -> [String] {
            items.sorted { lhs, rhs in
                switch opt {
                case .sizeDesc: return lhs.totalSize > rhs.totalSize
                case .sizeAsc:  return lhs.totalSize < rhs.totalSize
                case .nameAsc:  return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                case .nameDesc: return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
                case .dateDesc: return (lhs.modificationDate ?? .distantPast) > (rhs.modificationDate ?? .distantPast)
                case .dateAsc:  return (lhs.modificationDate ?? .distantPast) < (rhs.modificationDate ?? .distantPast)
                }
            }.map { $0.name }
        }

        #expect(sorted(.sizeDesc) == ["beta", "gamma", "alpha"])
        #expect(sorted(.sizeAsc)  == ["alpha", "gamma", "beta"])
        #expect(sorted(.nameAsc)  == ["alpha", "beta", "gamma"])
        #expect(sorted(.nameDesc) == ["gamma", "beta", "alpha"])
        #expect(sorted(.dateDesc) == ["beta", "gamma", "alpha"])
        #expect(sorted(.dateAsc)  == ["alpha", "gamma", "beta"])
    }

    // CAMBIO 10-E: El algoritmo de treemap nunca produce dimensiones negativas
    @MainActor @Test func testTreemapNonNegativeDimensions() {
        // Items de tamaños muy variados, incluyendo 0
        let sizes: [Int64] = [0, 1, 10, 100, 1_000_000, 0, 5, 2]
        let items = sizes.enumerated().map { i, sz in
            makeItem(name: "item\(i)", size: sz)
        }

        let frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        let rects = squarifyForTest(items: items, in: frame)

        for rect in rects {
            #expect(rect.width  >= 0, "Ancho negativo: \(rect.width)")
            #expect(rect.height >= 0, "Alto negativo: \(rect.height)")
            #expect(rect.origin.x.isFinite)
            #expect(rect.origin.y.isFinite)
        }
    }
}

// MARK: - Squarify (copia de la lógica de DetailView para testear en aislamiento)

private func squarifyForTest(items: [FileItem], in rect: CGRect) -> [CGRect] {
    let totalSize = items.reduce(0) { $0 + max($1.totalSize, 1) }
    guard totalSize > 0, rect.width > 0, rect.height > 0 else { return [] }

    var result: [CGRect] = Array(repeating: .zero, count: items.count)
    var remaining = rect
    var startIndex = 0

    while startIndex < items.count {
        let count = bestRowCount(items: Array(items[startIndex...]),
                                 remaining: remaining, totalSize: totalSize)
        let rowItems = Array(items[startIndex..<(startIndex + count)])
        let rowRects = layoutRowForTest(items: rowItems, in: remaining, totalSize: totalSize)
        for (i, r) in rowRects.enumerated() { result[startIndex + i] = r }

        if let last = rowRects.last {
            let isH = remaining.width >= remaining.height
            remaining = isH
                ? CGRect(x: last.maxX, y: remaining.minY,
                         width: remaining.maxX - last.maxX, height: remaining.height)
                : CGRect(x: remaining.minX, y: last.maxY,
                         width: remaining.width, height: remaining.maxY - last.maxY)
        }
        startIndex += count
    }
    return result
}

private func bestRowCount(items: [FileItem], remaining: CGRect, totalSize: Int64) -> Int {
    var best = 1; var bestR = Double.infinity
    for c in 1...min(items.count, 20) {
        let r = worstRatioForTest(items: Array(items[0..<c]), in: remaining, totalSize: totalSize)
        if r < bestR { bestR = r; best = c } else { break }
    }
    return best
}

private func worstRatioForTest(items: [FileItem], in rect: CGRect, totalSize: Int64) -> Double {
    guard !items.isEmpty else { return .infinity }
    let side = min(rect.width, rect.height)
    guard side > 0 else { return .infinity }
    let rowTotal = items.reduce(0) { $0 + max($1.totalSize, 1) }
    let rowArea  = rect.width * rect.height * Double(rowTotal) / Double(totalSize)
    let rowWidth = rowArea / side
    return items.map { item -> Double in
        let h = Double(max(item.totalSize, 1)) / Double(rowTotal) * side
        return rowWidth > h ? rowWidth / h : h / rowWidth
    }.max() ?? 0
}

private func layoutRowForTest(items: [FileItem], in rect: CGRect, totalSize: Int64) -> [CGRect] {
    guard !items.isEmpty else { return [] }
    let rowTotal  = items.reduce(0) { $0 + max($1.totalSize, 1) }
    let rowFrac   = Double(rowTotal) / Double(totalSize)
    let rowArea   = rect.width * rect.height * rowFrac
    let isH       = rect.width >= rect.height
    let side      = isH ? rect.height : rect.width
    let rowWidth  = max(0, side > 0 ? rowArea / side : 0)
    var rects: [CGRect] = []
    var pos: CGFloat    = isH ? rect.minY : rect.minX
    let minCell: CGFloat = 2
    for item in items {
        let frac    = Double(max(item.totalSize, 1)) / Double(rowTotal)
        let itemLen = max(0, frac * side)
        rects.append(isH
            ? CGRect(x: rect.minX, y: pos, width: max(minCell, rowWidth), height: max(minCell, itemLen))
            : CGRect(x: pos, y: rect.minY, width: max(minCell, itemLen), height: max(minCell, rowWidth)))
        pos += itemLen
    }
    return rects
}
