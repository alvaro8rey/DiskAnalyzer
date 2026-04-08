import Foundation
import SwiftUI
import Combine

// MARK: - View Mode

enum ViewMode: String, CaseIterable, Identifiable {
    case treemap   = "Mapa"
    case topFiles  = "Archivos"
    case fileTypes = "Tipos"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .treemap:   return "square.grid.2x2.fill"
        case .topFiles:  return "list.number"
        case .fileTypes: return "chart.bar.fill"
        }
    }
}

// MARK: - Disk Scanner

@MainActor
class DiskScanner: ObservableObject {

    @Published var rootItem: FileItem?
    @Published var isScanning: Bool = false
    @Published var progress: Double = 0
    @Published var statusMessage: String = "Selecciona un directorio para analizar"
    @Published var selectedItem: FileItem?
    @Published var sortOption: SortOption = .sizeDesc
    @Published var searchText: String = ""
    @Published var errorMessage: String?

    // Stats
    @Published var totalScanned: Int = 0
    @Published var scanDuration: TimeInterval = 0
    @Published var scanRate: Int = 0

    // UI state
    @Published var viewMode: ViewMode = .treemap
    @Published var showHiddenFiles: Bool = false
    @Published var recentDirectories: [URL] = []

    private var scanTask: Task<Void, Never>?
    private var scanStart: Date?
    private var rateTimer: Timer?
    private var lastRateSnapshot: Int = 0
    private let recentKey = "recentDirectories"

    init() {
        loadRecentDirectories()
    }

    // MARK: - Directory Selection

    func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Selecciona un disco o directorio para analizar"
        panel.prompt = "Analizar"
        if panel.runModal() == .OK, let url = panel.url {
            startScan(url: url)
        }
    }

    func startScan(url: URL) {
        scanTask?.cancel()
        rateTimer?.invalidate()

        errorMessage = nil
        totalScanned = 0
        scanRate = 0
        lastRateSnapshot = 0
        scanStart = Date()

        let root = FileItem(url: url, isDirectory: true)
        rootItem = root
        selectedItem = root
        isScanning = true
        statusMessage = "Iniciando análisis..."
        progress = 0

        addToRecent(url)

        rateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isScanning else { return }
                let n = self.totalScanned
                self.scanRate = n - self.lastRateSnapshot
                self.lastRateSnapshot = n
            }
        }

        let hidden = showHiddenFiles
        scanTask = Task {
            await scanDir(item: root, showHidden: hidden)
            rateTimer?.invalidate()
            rateTimer = nil
            isScanning = false
            scanRate = 0
            scanDuration = Date().timeIntervalSince(scanStart ?? Date())
            if errorMessage == nil {
                statusMessage = "✓ \(root.formattedSize) · \(root.itemCount.formatted()) elementos · \(String(format: "%.1f", scanDuration))s"
                sortChildren(of: root)
            } else {
                statusMessage = "Error al analizar el directorio"
            }
            progress = 1.0
        }
    }

    func rescan() {
        guard let url = rootItem?.url else { return }
        startScan(url: url)
    }

    func cancelScan() {
        scanTask?.cancel()
        rateTimer?.invalidate()
        rateTimer = nil
        isScanning = false
        scanRate = 0
        statusMessage = "Análisis cancelado"
    }

    // MARK: - Scanning (nonisolated → cooperative thread pool)

    nonisolated private func scanDir(item: FileItem, showHidden: Bool) async {
        guard !Task.isCancelled else { return }

        let url = item.url
        let allKeys: Set<URLResourceKey> = [
            .fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey,
            .contentModificationDateKey, .creationDateKey
        ]

        let ownRV   = try? url.resourceValues(forKeys: allKeys)
        let ownSize = Int64(ownRV?.fileSize ?? 0)

        await MainActor.run {
            item.size             = ownSize
            item.totalSize        = ownSize
            item.modificationDate = ownRV?.contentModificationDate
            item.creationDate     = ownRV?.creationDate
            item.children         = []
        }

        var options: FileManager.DirectoryEnumerationOptions = []
        if !showHidden { options.insert(.skipsHiddenFiles) }

        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: Array(allKeys),
                options: options
            )
        } catch {
            if item.parent == nil {
                let scanner = self
                let msg = "No se puede acceder a '\(url.lastPathComponent)': \(error.localizedDescription)"
                await MainActor.run { scanner.errorMessage = msg }
            }
            return
        }

        var fileItems: [FileItem] = []
        var dirItems:  [FileItem] = []
        var fileTotal: Int64      = 0

        for childURL in contents {
            guard !Task.isCancelled else { return }

            let rv        = try? childURL.resourceValues(forKeys: allKeys)
            let isSymLink = rv?.isSymbolicLink ?? false
            let isDir     = (rv?.isDirectory ?? false) && !isSymLink

            let child = FileItem(url: childURL, isDirectory: isDir)
            child.modificationDate = rv?.contentModificationDate
            child.creationDate     = rv?.creationDate

            if isDir {
                dirItems.append(child)
            } else {
                let sz      = Int64(rv?.fileSize ?? 0)
                child.size      = sz
                child.totalSize = sz
                fileTotal      += sz
                fileItems.append(child)
            }
        }

        let allChildren = dirItems + fileItems
        let scanner = self
        await MainActor.run {
            for child in allChildren { child.parent = item }
            item.children  = allChildren
            item.totalSize += fileTotal
            item.itemCount += allChildren.count
            scanner.totalScanned += allChildren.count
        }

        await withTaskGroup(of: Void.self) { group in
            for dirChild in dirItems {
                guard !Task.isCancelled else { break }
                group.addTask {
                    await self.scanDir(item: dirChild, showHidden: showHidden)
                    await MainActor.run {
                        item.totalSize += dirChild.totalSize
                        item.itemCount += dirChild.itemCount
                    }
                }
            }
        }
    }

    // MARK: - Computed Data (post-scan)

    /// Top archivos más grandes (máx. 5 000 para rendimiento).
    var topFiles: [FileItem] {
        guard let root = rootItem, !isScanning else { return [] }
        var result: [FileItem] = []
        func collect(_ item: FileItem) {
            if !item.isDirectory { result.append(item) }
            item.children?.forEach { collect($0) }
        }
        collect(root)
        return result.sorted { $0.totalSize > $1.totalSize }
    }

    /// Desglose de espacio por categoría de archivo.
    var fileTypeGroups: [FileTypeGroup] {
        guard let root = rootItem, !isScanning else { return [] }

        var groups: [FileCategory: FileTypeGroup] = Dictionary(
            uniqueKeysWithValues: FileCategory.allCases.map { ($0, FileTypeGroup(category: $0)) }
        )
        func traverse(_ item: FileItem) {
            if !item.isDirectory {
                let cat = FileCategory.category(forExtension: item.url.pathExtension)
                groups[cat]?.totalSize += item.totalSize
                groups[cat]?.count     += 1
            }
            item.children?.forEach { traverse($0) }
        }
        traverse(root)

        return groups.values
            .filter { $0.count > 0 }
            .sorted { $0.totalSize > $1.totalSize }
    }

    // MARK: - File Actions

    func moveToTrash(_ item: FileItem) {
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            if let parent = item.parent {
                parent.children?.removeAll { $0.id == item.id }
                propagateSizeRemoval(
                    size:  item.totalSize,
                    count: item.isDirectory ? item.itemCount + 1 : 1,
                    from:  parent
                )
            } else {
                rootItem = nil
            }
            if selectedItem?.id == item.id {
                selectedItem = item.parent ?? rootItem
            }
        } catch {
            errorMessage = "No se pudo mover a la papelera: \(error.localizedDescription)"
        }
    }

    func copyPath(_ item: FileItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.url.path, forType: .string)
    }

    private func propagateSizeRemoval(size: Int64, count: Int, from startItem: FileItem) {
        var current: FileItem? = startItem
        while let node = current {
            node.totalSize = max(0, node.totalSize - size)
            node.itemCount = max(0, node.itemCount - count)
            current = node.parent
        }
    }

    // MARK: - Recent Directories

    func addToRecent(_ url: URL) {
        var recent = recentDirectories.filter { $0 != url }
        recent.insert(url, at: 0)
        recentDirectories = Array(recent.prefix(8))
        UserDefaults.standard.set(recentDirectories.map { $0.path }, forKey: recentKey)
    }

    private func loadRecentDirectories() {
        let paths = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
        recentDirectories = paths
            .compactMap { URL(fileURLWithPath: $0, isDirectory: true) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - Sorting

    func sortChildren(of item: FileItem) {
        guard let children = item.children else { return }
        let sorted = children.sorted { a, b in
            switch sortOption {
            case .sizeDesc: return a.totalSize > b.totalSize
            case .sizeAsc:  return a.totalSize < b.totalSize
            case .nameAsc:  return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .nameDesc: return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedDescending
            case .dateDesc: return (a.modificationDate ?? .distantPast) > (b.modificationDate ?? .distantPast)
            case .dateAsc:  return (a.modificationDate ?? .distantPast) < (b.modificationDate ?? .distantPast)
            }
        }
        item.children = sorted
        for child in sorted where child.isDirectory {
            sortChildren(of: child)
        }
    }

    func resort() {
        if let root = rootItem { sortChildren(of: root) }
    }

    // MARK: - File Operations

    func revealInFinder(_ item: FileItem) {
        NSWorkspace.shared.selectFile(item.url.path, inFileViewerRootedAtPath: "")
    }

    func openFile(_ item: FileItem) {
        NSWorkspace.shared.open(item.url)
    }

    func getInfo(_ item: FileItem) {
        let script = "tell application \"Finder\"\nopen information window of (POSIX file \"\(item.url.path)\" as alias)\nactivate\nend tell"
        NSAppleScript(source: script)?.executeAndReturnError(nil)
    }
}
