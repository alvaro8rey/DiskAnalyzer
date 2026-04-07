import Foundation
import SwiftUI
import Combine

// MARK: - FileItem Model

class FileItem: Identifiable, ObservableObject {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    var size: Int64 = 0         // Tamaño real del archivo/directorio
    var totalSize: Int64 = 0    // Tamaño total incluyendo subdirectorios
    var itemCount: Int = 0      // Número de ítems hijos
    var modificationDate: Date?
    var creationDate: Date?
    
    @Published var children: [FileItem]? = nil
    @Published var isLoading: Bool = false
    
    weak var parent: FileItem?
    
    init(url: URL, isDirectory: Bool) {
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = isDirectory
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    var formattedItemCount: String {
        if isDirectory {
            return "\(itemCount) \(itemCount == 1 ? "elemento" : "elementos")"
        }
        return ""
    }
    
    var formattedDate: String {
        guard let date = modificationDate else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var icon: String {
        if isDirectory {
            return "folder.fill"
        }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "swift", "py", "js", "ts", "kt", "java", "c", "cpp", "h", "rs", "go":
            return "doc.text.fill"
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "tiff":
            return "photo.fill"
        case "mp4", "mov", "avi", "mkv", "m4v":
            return "film.fill"
        case "mp3", "m4a", "wav", "flac", "aac":
            return "music.note"
        case "pdf":
            return "doc.richtext.fill"
        case "zip", "tar", "gz", "7z", "rar", "dmg":
            return "archivebox.fill"
        case "app":
            return "app.fill"
        case "pkg", "mpkg":
            return "shippingbox.fill"
        default:
            return "doc.fill"
        }
    }
    
    var iconColor: Color {
        if isDirectory {
            return .accentColor
        }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "swift", "py", "js", "ts", "kt", "java", "c", "cpp", "h", "rs", "go":
            return .orange
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "tiff":
            return .green
        case "mp4", "mov", "avi", "mkv", "m4v":
            return .red
        case "mp3", "m4a", "wav", "flac", "aac":
            return .pink
        case "pdf":
            return .red.opacity(0.8)
        case "zip", "tar", "gz", "7z", "rar", "dmg":
            return .purple
        case "app":
            return .blue
        default:
            return .secondary
        }
    }
    
    // Porcentaje respecto al padre
    func percentage(of parent: FileItem) -> Double {
        guard parent.totalSize > 0 else { return 0 }
        return Double(totalSize) / Double(parent.totalSize)
    }
}

// MARK: - Sort Options

enum SortOption: String, CaseIterable, Identifiable {
    case sizeDesc = "Tamaño ↓"
    case sizeAsc = "Tamaño ↑"
    case nameAsc = "Nombre A→Z"
    case nameDesc = "Nombre Z→A"
    case dateDesc = "Fecha ↓"
    case dateAsc = "Fecha ↑"
    
    var id: String { rawValue }
}
