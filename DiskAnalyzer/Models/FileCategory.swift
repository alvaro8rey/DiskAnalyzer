import SwiftUI

// MARK: - File Category

enum FileCategory: String, CaseIterable, Identifiable, Equatable {
    case video     = "Video"
    case audio     = "Audio"
    case images    = "Imágenes"
    case documents = "Documentos"
    case code      = "Código"
    case archives  = "Archivos comprimidos"
    case apps      = "Aplicaciones"
    case other     = "Otros"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .video:     return "film.fill"
        case .audio:     return "music.note"
        case .images:    return "photo.fill"
        case .documents: return "doc.richtext.fill"
        case .code:      return "curlybraces"
        case .archives:  return "archivebox.fill"
        case .apps:      return "app.fill"
        case .other:     return "doc.fill"
        }
    }

    var color: Color {
        switch self {
        case .video:     return .red
        case .audio:     return .pink
        case .images:    return .green
        case .documents: return .blue
        case .code:      return .orange
        case .archives:  return .purple
        case .apps:      return .indigo
        case .other:     return .gray
        }
    }

    var extensions: Set<String> {
        switch self {
        case .video:
            return ["mp4","mov","avi","mkv","m4v","wmv","flv","webm","mpg","mpeg",
                    "3gp","ts","mts","m2ts","vob","asf","rm","rmvb","f4v","ogv"]
        case .audio:
            return ["mp3","m4a","wav","flac","aac","ogg","wma","aiff","aif",
                    "opus","alac","mid","midi","ape","mka","oga","caf"]
        case .images:
            return ["png","jpg","jpeg","gif","webp","svg","heic","heif","tiff","tif",
                    "bmp","raw","cr2","cr3","nef","arw","dng","orf","rw2","psd","ai",
                    "eps","xcf","ico","icns","avif","jxl"]
        case .documents:
            return ["pdf","doc","docx","xls","xlsx","ppt","pptx","pages","numbers",
                    "keynote","txt","rtf","md","markdown","epub","mobi","odt","ods",
                    "odp","csv","tsv","tex","rst","org"]
        case .code:
            return ["swift","py","js","ts","jsx","tsx","vue","html","htm","css",
                    "scss","sass","less","java","kt","kts","c","cc","cpp","cxx",
                    "h","hpp","rs","go","rb","php","cs","sh","bash","zsh","fish",
                    "ps1","json","xml","yaml","yml","toml","ini","cfg","sql","r",
                    "m","mm","pl","lua","scala","ex","exs","clj","hs","fs","dart",
                    "jl","nim","zig","graphql","proto","dockerfile","makefile",
                    "podfile","gemfile","rakefile","gradle"]
        case .archives:
            return ["zip","tar","gz","tgz","bz2","tbz2","7z","rar","dmg","pkg",
                    "deb","rpm","iso","xz","txz","lz4","zst","cab","jar","ear",
                    "war","apk","ipa"]
        case .apps:
            return ["app","ipa","apk","exe","msi","widget","plugin","kext","bundle","mdimporter"]
        case .other:
            return []
        }
    }

    static func category(forExtension ext: String) -> FileCategory {
        let e = ext.lowercased()
        for cat in allCases where cat != .other {
            if cat.extensions.contains(e) { return cat }
        }
        return .other
    }
}

// MARK: - File Type Group

struct FileTypeGroup: Identifiable {
    var id: String { category.rawValue }
    let category: FileCategory
    var totalSize: Int64 = 0
    var count: Int = 0

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}
