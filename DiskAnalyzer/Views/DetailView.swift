import SwiftUI

struct DetailView: View {
    @ObservedObject var scanner: DiskScanner
    
    var body: some View {
        VSplitView {
            // Top: Treemap
            TreemapView(scanner: scanner)
                .frame(minHeight: 250)
            
            // Bottom: Info panel
            FileInfoPanel(scanner: scanner)
                .frame(minHeight: 180, idealHeight: 220, maxHeight: 300)
        }
    }
}

// MARK: - Treemap View

struct TreemapView: View {
    @ObservedObject var scanner: DiskScanner
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(NSColor.controlBackgroundColor)
                
                if let item = scanner.selectedItem ?? scanner.rootItem,
                   let children = item.children, !children.isEmpty {
                    TreemapLayout(
                        items: children,
                        frame: CGRect(origin: .zero, size: geo.size),
                        scanner: scanner
                    )
                } else if scanner.isScanning {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Analizando disco...")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                } else if scanner.rootItem == nil {
                    Text("Sin datos")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "doc")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("Archivo seleccionado")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay(alignment: .topLeading) {
            // Breadcrumb
            if let item = scanner.selectedItem ?? scanner.rootItem {
                BreadcrumbView(item: item, scanner: scanner)
            }
        }
    }
}

// MARK: - Treemap Layout

struct TreemapLayout: View {
    let items: [FileItem]
    let frame: CGRect
    @ObservedObject var scanner: DiskScanner
    
    var body: some View {
        let rects = squarify(items: items, in: frame)
        
        return ZStack(alignment: .topLeading) {
            ForEach(Array(zip(items.indices, items)), id: \.1.id) { index, item in
                if index < rects.count {
                    TreemapCell(item: item, rect: rects[index], scanner: scanner)
                }
            }
        }
        .frame(width: frame.width, height: frame.height)
    }
    
    // Squarified treemap algorithm
    private func squarify(items: [FileItem], in rect: CGRect) -> [CGRect] {
        let totalSize = items.reduce(0) { $0 + max($1.totalSize, 1) }
        guard totalSize > 0 else { return [] }
        
        var result: [CGRect] = Array(repeating: .zero, count: items.count)
        var remaining = rect
        var startIndex = 0
        
        while startIndex < items.count {
            let row = bestRow(
                items: Array(items[startIndex...]),
                remaining: remaining,
                totalSize: totalSize
            )
            
            let rowItems = Array(items[startIndex..<(startIndex + row)])
            let rowRects = layoutRow(items: rowItems, in: remaining, totalSize: totalSize)
            
            for (i, r) in rowRects.enumerated() {
                result[startIndex + i] = r
            }
            
            // Shrink remaining rect
            if let last = rowRects.last {
                let isHorizontal = remaining.width >= remaining.height
                if isHorizontal {
                    remaining = CGRect(
                        x: last.maxX,
                        y: remaining.minY,
                        width: remaining.maxX - last.maxX,
                        height: remaining.height
                    )
                } else {
                    remaining = CGRect(
                        x: remaining.minX,
                        y: last.maxY,
                        width: remaining.width,
                        height: remaining.maxY - last.maxY
                    )
                }
            }
            
            startIndex += row
        }
        
        return result
    }
    
    private func bestRow(items: [FileItem], remaining: CGRect, totalSize: Int64) -> Int {
        var best = 1
        var bestRatio = Double.infinity
        
        for count in 1...min(items.count, 20) {
            let ratio = worstRatio(
                items: Array(items[0..<count]),
                in: remaining,
                totalSize: totalSize
            )
            if ratio < bestRatio {
                bestRatio = ratio
                best = count
            } else {
                break
            }
        }
        return best
    }
    
    private func worstRatio(items: [FileItem], in rect: CGRect, totalSize: Int64) -> Double {
        guard !items.isEmpty else { return Double.infinity }
        let side = min(rect.width, rect.height)
        guard side > 0 else { return Double.infinity }
        
        let totalArea = rect.width * rect.height
        let rowTotal = items.reduce(0) { $0 + max($1.totalSize, 1) }
        let rowFraction = Double(rowTotal) / Double(totalSize)
        let rowArea = totalArea * rowFraction
        let rowWidth = rowArea / side
        
        var worst: Double = 0
        for item in items {
            let frac = Double(max(item.totalSize, 1)) / Double(rowTotal)
            let h = frac * side
            let ratio = rowWidth > h ? rowWidth / h : h / rowWidth
            worst = max(worst, ratio)
        }
        return worst
    }
    
    private func layoutRow(items: [FileItem], in rect: CGRect, totalSize: Int64) -> [CGRect] {
        guard !items.isEmpty else { return [] }
        
        let totalArea = rect.width * rect.height
        let rowTotal = items.reduce(0) { $0 + max($1.totalSize, 1) }
        let rowFraction = Double(rowTotal) / Double(totalSize)
        let rowArea = totalArea * rowFraction
        
        let isHorizontal = rect.width >= rect.height
        let side = isHorizontal ? rect.height : rect.width
        let rowWidth = side > 0 ? rowArea / side : 0
        
        var rects: [CGRect] = []
        var pos: CGFloat = isHorizontal ? rect.minY : rect.minX
        
        for item in items {
            let frac = Double(max(item.totalSize, 1)) / Double(rowTotal)
            let itemLen = frac * side
            
            let r: CGRect
            if isHorizontal {
                r = CGRect(x: rect.minX, y: pos, width: rowWidth, height: itemLen)
            } else {
                r = CGRect(x: pos, y: rect.minY, width: itemLen, height: rowWidth)
            }
            rects.append(r)
            pos += itemLen
        }
        
        return rects
    }
}

// MARK: - Treemap Cell

struct TreemapCell: View {
    let item: FileItem
    let rect: CGRect
    @ObservedObject var scanner: DiskScanner
    
    @State private var isHovered = false
    
    var isSelected: Bool { scanner.selectedItem?.id == item.id }
    
    var cellColor: Color {
        if item.isDirectory {
            return directoryColor(item: item)
        }
        return fileColor(item: item)
    }
    
    var body: some View {
        let minDim = min(rect.width, rect.height)
        let showLabel = minDim > 28 && rect.width > 40
        
        ZStack {
            Rectangle()
                .fill(cellColor.opacity(isSelected ? 1.0 : isHovered ? 0.9 : 0.75))
            
            if isSelected || isHovered {
                Rectangle()
                    .strokeBorder(Color.white.opacity(0.8), lineWidth: 2)
            }
            
            if showLabel {
                VStack(spacing: 2) {
                    if rect.height > 44 {
                        Image(systemName: item.icon)
                            .font(.system(size: min(minDim * 0.18, 20)))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    
                    Text(item.name)
                        .font(.system(size: min(minDim * 0.12, 12), weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                    
                    if rect.height > 52 {
                        Text(item.formattedSize)
                            .font(.system(size: min(minDim * 0.1, 10), design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: rect.width - 1, height: rect.height - 1)
        .position(x: rect.midX, y: rect.midY)
        .contentShape(Rectangle())
        .onTapGesture {
            scanner.selectedItem = item
        }
        .onTapGesture(count: 2) {
            if item.isDirectory {
                scanner.selectedItem = item
            }
        }
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Mostrar en Finder") { scanner.revealInFinder(item) }
            Button("Abrir") { scanner.openFile(item) }
            Divider()
            Button("Obtener información") { scanner.getInfo(item) }
        }
        .help("\(item.name)\n\(item.formattedSize)")
    }
    
    // Color palette for directories based on first letter / hash
    private func directoryColor(item: FileItem) -> Color {
        let colors: [Color] = [
            .blue, .indigo, .purple, .pink,
            .red, .orange, .yellow, .green, .teal, .cyan
        ]
        let hash = abs(item.name.hashValue) % colors.count
        return colors[hash]
    }
    
    private func fileColor(item: FileItem) -> Color {
        let ext = item.url.pathExtension.lowercased()
        switch ext {
        case "swift", "py", "js", "ts", "go", "rs", "kt", "java":
            return .orange
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic":
            return .green
        case "mp4", "mov", "avi", "mkv":
            return .red
        case "mp3", "m4a", "wav", "flac":
            return .pink
        case "pdf":
            return Color(red: 0.85, green: 0.15, blue: 0.1)
        case "zip", "tar", "gz", "7z", "rar", "dmg":
            return .purple
        case "app":
            return .blue
        default:
            return .gray
        }
    }
}

// MARK: - Breadcrumb

struct BreadcrumbView: View {
    let item: FileItem
    @ObservedObject var scanner: DiskScanner
    
    var ancestors: [FileItem] {
        var path: [FileItem] = []
        var current: FileItem? = item
        while let c = current {
            path.insert(c, at: 0)
            current = c.parent
        }
        return path
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(ancestors) { ancestor in
                    if ancestor.id != ancestors.first?.id {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Button(ancestor.name.isEmpty ? "/" : ancestor.name) {
                        scanner.selectedItem = ancestor
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(ancestor.id == item.id ? .primary : .secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(.regularMaterial)
    }
}

// MARK: - File Info Panel

struct FileInfoPanel: View {
    @ObservedObject var scanner: DiskScanner
    
    var item: FileItem? { scanner.selectedItem }
    
    var body: some View {
        if let item = item {
            HSplitView {
                // Left: Top children table
                TopChildrenTable(item: item, scanner: scanner)
                
                // Right: File attributes
                FileAttributesView(item: item)
            }
            .background(Color(NSColor.controlBackgroundColor))
        } else {
            Text("Selecciona un elemento")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Top Children Table

struct TopChildrenTable: View {
    @ObservedObject var item: FileItem
    @ObservedObject var scanner: DiskScanner
    
    var topChildren: [FileItem] {
        (item.children ?? []).sorted { $0.totalSize > $1.totalSize }.prefix(20).map { $0 }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Nombre")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Tamaño")
                    .frame(width: 80, alignment: .trailing)
                Text("%")
                    .frame(width: 44, alignment: .trailing)
                Text("Modificado")
                    .frame(width: 130, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(topChildren.enumerated()), id: \.element.id) { idx, child in
                        TableRow(
                            item: child,
                            parent: item,
                            index: idx,
                            scanner: scanner
                        )
                    }
                }
            }
        }
        .frame(minWidth: 300)
    }
}

struct TableRow: View {
    let item: FileItem
    let parent: FileItem
    let index: Int
    @ObservedObject var scanner: DiskScanner
    
    @State private var isHovered = false
    var isSelected: Bool { scanner.selectedItem?.id == item.id }
    
    var pct: Double { item.percentage(of: parent) }
    
    var body: some View {
        HStack(spacing: 0) {
            // Icon + name
            HStack(spacing: 6) {
                Image(systemName: item.icon)
                    .foregroundStyle(item.iconColor)
                    .font(.system(size: 11))
                    .frame(width: 16)
                
                Text(item.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Size bar + size
            ZStack(alignment: .trailing) {
                GeometryReader { g in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor.opacity(0.25))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor.opacity(0.7))
                        .frame(width: g.size.width * pct)
                }
                .frame(height: 8)
                .padding(.trailing, 2)
            }
            .frame(width: 60)
            
            Text(item.formattedSize)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            
            Text(String(format: "%.1f%%", pct * 100))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
            
            Text(item.formattedDate)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 130, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            isSelected ? Color.accentColor.opacity(0.15) :
            isHovered  ? Color.secondary.opacity(0.06) :
            index % 2 == 0 ? Color.clear : Color.secondary.opacity(0.03)
        )
        .contentShape(Rectangle())
        .onTapGesture { scanner.selectedItem = item }
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Mostrar en Finder") { scanner.revealInFinder(item) }
            Button("Abrir") { scanner.openFile(item) }
        }
    }
    
    var barColor: Color {
        switch pct {
        case 0.5...:  return .red
        case 0.2..:   return .orange
        case 0.05..:  return .yellow
        default:      return .green
        }
    }
}

// MARK: - File Attributes

struct FileAttributesView: View {
    let item: FileItem
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Big icon + name
                HStack(spacing: 12) {
                    Image(systemName: item.icon)
                        .font(.system(size: 40))
                        .foregroundStyle(item.iconColor)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name.isEmpty ? "/" : item.name)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(2)
                        Text(item.isDirectory ? "Directorio" : item.url.pathExtension.uppercased() + " archivo")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                
                Divider().padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 0) {
                    InfoRow(label: "Tamaño", value: item.formattedSize)
                    if item.isDirectory {
                        InfoRow(label: "Elementos", value: item.formattedItemCount)
                    }
                    InfoRow(label: "Ruta", value: item.url.path)
                    InfoRow(label: "Modificado", value: item.formattedDate)
                    if let created = item.creationDate {
                        let fmt = DateFormatter()
                        let _ = { fmt.dateStyle = .medium; fmt.timeStyle = .short }()
                        InfoRow(label: "Creado", value: fmt.string(from: created))
                    }
                    InfoRow(label: "Extensión", value: item.url.pathExtension.isEmpty ? "—" : ".\(item.url.pathExtension)")
                }
                .padding(.top, 4)
            }
        }
        .frame(minWidth: 220, idealWidth: 260)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
            Text(value)
                .font(.system(size: 11))
                .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
    }
}
