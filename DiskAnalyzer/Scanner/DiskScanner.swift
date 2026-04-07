import Foundation
import SwiftUI

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
    
    private var scanTask: Task<Void, Never>?
    private var scanStart: Date?
    private var progressTimer: Timer?
    
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
        errorMessage = nil
        totalScanned = 0
        scanStart = Date()
        
        let root = FileItem(url: url, isDirectory: true)
        rootItem = root
        selectedItem = root
        isScanning = true
        statusMessage = "Analizando \(url.path)..."
        progress = 0
        
        scanTask = Task {
            await scanDirectory(item: root, depth: 0)
            
            await MainActor.run {
                self.isScanning = false
                self.scanDuration = Date().timeIntervalSince(self.scanStart ?? Date())
                self.statusMessage = "Análisis completado — \(root.formattedSize) en \(root.itemCount) elementos — \(String(format: "%.1f", self.scanDuration))s"
                self.progress = 1.0
                self.sortChildren(of: root)
            }
        }
    }
    
    func cancelScan() {
        scanTask?.cancel()
        isScanning = false
        statusMessage = "Análisis cancelado"
    }
    
    // MARK: - Recursive Scan
    
    private func scanDirectory(item: FileItem, depth: Int) async {
        guard !Task.isCancelled else { return }
        
        let fm = FileManager.default
        let url = item.url
        
        // Get attributes of the directory itself
        let attrs = try? fm.attributesOfItem(atPath: url.path)
        item.modificationDate = attrs?[.modificationDate] as? Date
        item.creationDate = attrs?[.creationDate] as? Date
        item.size = (attrs?[.size] as? Int64) ?? 0
        
        do {
            let contents = try fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [
                    .fileSizeKey,
                    .isDirectoryKey,
                    .contentModificationDateKey,
                    .creationDateKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey
                ],
                options: [.skipsHiddenFiles]
            )
            
            var childItems: [FileItem] = []
            
            for childURL in contents {
                guard !Task.isCancelled else { return }
                
                let resourceValues = try? childURL.resourceValues(forKeys: [
                    .isDirectoryKey, .isSymbolicLinkKey
                ])
                
                let isSymLink = resourceValues?.isSymbolicLink ?? false
                let isDir = (resourceValues?.isDirectory ?? false) && !isSymLink
                
                let child = FileItem(url: childURL, isDirectory: isDir)
                child.parent = item
                childItems.append(child)
                
                if isDir {
                    await scanDirectory(item: child, depth: depth + 1)
                } else {
                    let fileAttrs = try? fm.attributesOfItem(atPath: childURL.path)
                    child.size = (fileAttrs?[.size] as? Int64) ?? 0
                    child.totalSize = child.size
                    child.modificationDate = fileAttrs?[.modificationDate] as? Date
                    child.creationDate = fileAttrs?[.creationDate] as? Date
                }
                
                await MainActor.run {
                    self.totalScanned += 1
                    if self.totalScanned % 100 == 0 {
                        self.statusMessage = "Analizando... \(self.totalScanned) elementos encontrados"
                    }
                }
            }
            
            // Compute totals
            var dirTotal: Int64 = item.size
            var count = 0
            for child in childItems {
                dirTotal += child.totalSize
                count += 1
                if child.isDirectory {
                    count += child.itemCount
                }
            }
            
            await MainActor.run {
                item.children = childItems
                item.totalSize = dirTotal
                item.itemCount = count
            }
            
        } catch {
            await MainActor.run {
                item.children = []
                item.totalSize = item.size
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
        
        // Recurse into directories
        for child in sorted where child.isDirectory {
            sortChildren(of: child)
        }
    }
    
    func resort() {
        if let root = rootItem {
            sortChildren(of: root)
        }
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
        let appleScript = NSAppleScript(source: script)
        appleScript?.executeAndReturnError(nil)
    }
}
