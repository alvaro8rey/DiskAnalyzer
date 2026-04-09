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
    @Published var pendingAccessURL: URL?

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

    func selectDirectory(initialURL: URL? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Analizar"
        if let initial = initialURL {
            panel.message = "Selecciona '\(initial.lastPathComponent)' para confirmar el acceso"
            panel.directoryURL = initial.deletingLastPathComponent()
        } else {
            panel.message = "Selecciona un disco o directorio para analizar"
        }
        if panel.runModal() == .OK, let url = panel.url {
            startScan(url: url)
        }
    }

    func startScan(url: URL) {
        scanTask?.cancel()
        rateTimer?.invalidate()

        errorMessage = nil
        pendingAccessURL = nil
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
            if errorMessage == nil, pendingAccessURL == nil {
                statusMessage = "✓ \(root.formattedSize) · \(root.itemCount.formatted()) elementos · \(String(format: "%.1f", scanDuration))s"
                sortChildren(of: root)
            } else if errorMessage != nil {
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
                await MainActor.run {
                    scanner.isScanning = false
                    scanner.statusMessage = "Sin acceso a '\(url.lastPathComponent)'"
                    scanner.pendingAccessURL = url
                }
            }
            return
        }

        // ── Recopilar datos en background (sin tocar FileItem) ──────────
        struct ChildData {
            let url: URL
            let isDir: Bool
            let size: Int64
            let modDate: Date?
            let creDate: Date?
        }
        var childDataList: [ChildData] = []
        var fileTotal: Int64 = 0

        for childURL in contents {
            guard !Task.isCancelled else { return }
            let rv        = try? childURL.resourceValues(forKeys: allKeys)
            let isSymLink = rv?.isSymbolicLink ?? false
            let isDir     = (rv?.isDirectory ?? false) && !isSymLink
            let sz        = isDir ? Int64(0) : Int64(rv?.fileSize ?? 0)
            if !isDir { fileTotal += sz }
            childDataList.append(ChildData(
                url:     childURL,
                isDir:   isDir,
                size:    sz,
                modDate: rv?.contentModificationDate,
                creDate: rv?.creationDate
            ))
        }

        // ── Crear y configurar FileItems en MainActor (hilo principal) ───
        let scanner = self
        let dirChildren: [FileItem] = await MainActor.run {
            var dirs: [FileItem] = []
            var all:  [FileItem] = []
            for d in childDataList {
                let child          = FileItem(url: d.url, isDirectory: d.isDir)
                child.size         = d.size
                child.totalSize    = d.size
                child.modificationDate = d.modDate
                child.creationDate     = d.creDate
                child.parent       = item
                all.append(child)
                if d.isDir { dirs.append(child) }
            }
            // dirs primero para que el árbol muestre directorios arriba
            item.children   = dirs + all.filter { !$0.isDirectory }
            item.totalSize += fileTotal
            item.itemCount += all.count
            scanner.totalScanned += all.count
            return dirs
        }

        await withTaskGroup(of: Void.self) { group in
            for dirChild in dirChildren {
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

    func confirmAndMoveToTrash(_ item: FileItem) {
        let alert = NSAlert()
        alert.messageText = "¿Mover «\(item.name.isEmpty ? "/" : item.name)» a la papelera?"
        alert.informativeText = "\(item.isDirectory ? "El directorio" : "El archivo") ocupa \(item.formattedSize). Podrás recuperarlo desde la Papelera."
        alert.addButton(withTitle: "Mover a la papelera")
        alert.addButton(withTitle: "Cancelar")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            moveToTrash(item)
        }
    }

    func confirmAndMoveMultipleToTrash(_ items: [FileItem], completion: @escaping ([FileItem]) -> Void) {
        guard !items.isEmpty else { return }
        let totalSize = items.reduce(Int64(0)) { $0 + $1.totalSize }
        let sizeStr = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
        let alert = NSAlert()
        alert.messageText = "¿Mover \(items.count) elementos a la papelera?"
        alert.informativeText = "Ocupan \(sizeStr) en total. Podrás recuperarlos desde la Papelera."
        alert.addButton(withTitle: "Mover a la papelera")
        alert.addButton(withTitle: "Cancelar")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            var moved: [FileItem] = []
            for item in items {
                do {
                    try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                    if let parent = item.parent {
                        parent.children?.removeAll { $0.id == item.id }
                        propagateSizeRemoval(
                            size:  item.totalSize,
                            count: item.isDirectory ? item.itemCount + 1 : 1,
                            from:  parent
                        )
                    }
                    moved.append(item)
                } catch {
                    errorMessage = "No se pudo mover «\(item.name)»: \(error.localizedDescription)"
                }
            }
            if selectedItem.map({ moved.contains(where: { $0.id == $0.id }) }) == true {
                selectedItem = rootItem
            }
            completion(moved)
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
