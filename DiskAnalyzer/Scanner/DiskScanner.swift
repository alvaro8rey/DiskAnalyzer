import Foundation
import SwiftUI
import Combine

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
    @Published var scanRate: Int = 0          // elementos/segundo

    private var scanTask: Task<Void, Never>?
    private var scanStart: Date?
    private var rateTimer: Timer?
    private var lastRateSnapshot: Int = 0

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

        // Actualiza la tasa cada segundo
        rateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isScanning else { return }
                let n = self.totalScanned
                self.scanRate = n - self.lastRateSnapshot
                self.lastRateSnapshot = n
            }
        }

        // Task hereda @MainActor; al llamar a scanDir (nonisolated) el runtime
        // hace hop al thread pool cooperativo — el main thread queda libre.
        scanTask = Task {
            await scanDir(item: root)

            // De vuelta en @MainActor
            rateTimer?.invalidate()
            rateTimer = nil
            isScanning = false
            scanRate = 0
            scanDuration = Date().timeIntervalSince(scanStart ?? Date())
            statusMessage = "✓ \(root.formattedSize) · \(root.itemCount) elementos · \(String(format: "%.1f", scanDuration))s"
            progress = 1.0
            sortChildren(of: root)
        }
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

    /// Escanea un directorio en background.
    /// - Todos los atributos se leen en UNA sola llamada por entrada
    ///   (los resource values quedan cacheados por contentsOfDirectory).
    /// - Los subdirectorios se escanean en PARALELO con TaskGroup.
    nonisolated private func scanDir(item: FileItem) async {
        guard !Task.isCancelled else { return }

        let url = item.url
        let allKeys: Set<URLResourceKey> = [
            .fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey,
            .contentModificationDateKey, .creationDateKey
        ]

        // Atributos del propio directorio
        let ownRV   = try? url.resourceValues(forKeys: allKeys)
        let ownSize = Int64(ownRV?.fileSize ?? 0)

        await MainActor.run {
            item.size             = ownSize
            item.totalSize        = ownSize
            item.modificationDate = ownRV?.contentModificationDate
            item.creationDate     = ownRV?.creationDate
            item.children         = []      // aparece en árbol de inmediato
        }

        // Listar directorio — resource values prefetcheados, sin syscall extra por entrada
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(allKeys),
            options: .skipsHiddenFiles
        ) else { return }

        var fileItems: [FileItem] = []
        var dirItems:  [FileItem] = []
        var fileTotal: Int64      = 0

        for childURL in contents {
            guard !Task.isCancelled else { return }

            // resourceValues() aquí lee del caché — cero syscalls adicionales
            let rv       = try? childURL.resourceValues(forKeys: allKeys)
            let isSymLink = rv?.isSymbolicLink ?? false
            let isDir     = (rv?.isDirectory ?? false) && !isSymLink

            let child = FileItem(url: childURL, isDirectory: isDir)
            child.modificationDate = rv?.contentModificationDate
            child.creationDate     = rv?.creationDate

            if isDir {
                dirItems.append(child)
            } else {
                let sz      = Int64(rv?.fileSize ?? 0)
                child.size       = sz
                child.totalSize  = sz
                fileTotal       += sz
                fileItems.append(child)
            }
        }

        // Una sola actualización de UI por directorio (no por archivo)
        let allChildren = dirItems + fileItems
        let scanner = self
        await MainActor.run {
            for child in allChildren { child.parent = item }
            item.children  = allChildren
            item.totalSize += fileTotal
            item.itemCount += allChildren.count
            scanner.totalScanned += allChildren.count
        }

        // Escanear subdirectorios en PARALELO
        await withTaskGroup(of: Void.self) { group in
            for dirChild in dirItems {
                guard !Task.isCancelled else { break }
                group.addTask {
                    await self.scanDir(item: dirChild)
                    await MainActor.run {
                        item.totalSize += dirChild.totalSize
                        item.itemCount += dirChild.itemCount
                    }
                }
            }
        }
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
