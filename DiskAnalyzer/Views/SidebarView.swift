import SwiftUI

struct SidebarView: View {
    @ObservedObject var scanner: DiskScanner
    @State private var expandedItems: Set<UUID> = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            if scanner.rootItem != nil {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))
                    TextField("Buscar...", text: $scanner.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    if !scanner.searchText.isEmpty {
                        Button(action: { scanner.searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.regularMaterial)
                
                Divider()
            }
            
            // Tree list
            if let root = scanner.rootItem {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        FileRowView(
                            item: root,
                            depth: 0,
                            scanner: scanner,
                            expandedItems: $expandedItems,
                            isRoot: true
                        )
                    }
                }
            } else {
                WelcomeView(scanner: scanner)
            }
            
            Divider()
            
            // Status bar
            StatusBarView(scanner: scanner)
        }
    }
}

// MARK: - File Row

struct FileRowView: View {
    @ObservedObject var item: FileItem
    let depth: Int
    @ObservedObject var scanner: DiskScanner
    @Binding var expandedItems: Set<UUID>
    var isRoot: Bool = false
    
    @State private var isHovered = false
    
    var isExpanded: Bool {
        expandedItems.contains(item.id)
    }
    
    var isSelected: Bool {
        scanner.selectedItem?.id == item.id
    }
    
    var filteredChildren: [FileItem] {
        guard let children = item.children else { return [] }
        if scanner.searchText.isEmpty { return children }
        return children.filter { child in
            child.name.localizedCaseInsensitiveContains(scanner.searchText)
            || (child.children?.contains(where: { $0.name.localizedCaseInsensitiveContains(scanner.searchText) }) ?? false)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row
            HStack(spacing: 0) {
                // Indent
                Color.clear
                    .frame(width: CGFloat(depth) * 16 + 4, height: 1)
                
                // Expand toggle
                if item.isDirectory {
                    Button(action: toggleExpand) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 16, height: 16)
                }
                
                // Icon
                Image(systemName: item.icon)
                    .foregroundStyle(item.iconColor)
                    .font(.system(size: 13))
                    .frame(width: 20, height: 20)
                
                // Name
                Text(item.name.isEmpty ? "/" : item.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, 4)
                
                Spacer(minLength: 8)
                
                // Size bar
                if let parent = item.parent, parent.totalSize > 0 {
                    let pct = item.percentage(of: parent)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.secondary.opacity(0.15))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(sizeBarColor(pct: pct))
                                .frame(width: geo.size.width * pct)
                        }
                    }
                    .frame(width: 60, height: 6)
                }
                
                // Size
                Text(item.formattedSize)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 72, alignment: .trailing)
                    .padding(.trailing, 8)
            }
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        isSelected ? Color.accentColor.opacity(0.2) :
                        isHovered ? Color.secondary.opacity(0.08) : .clear
                    )
                    .padding(.horizontal, 4)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                selectItem()
                if item.isDirectory { toggleExpand() }
            }
            .onHover { isHovered = $0 }
            .contextMenu {
                Button("Mostrar en Finder") { scanner.revealInFinder(item) }
                Button("Abrir")             { scanner.openFile(item) }
                Button("Copiar ruta")        { scanner.copyPath(item) }
                Divider()
                Button("Obtener información") { scanner.getInfo(item) }
                Divider()
                Button("Mover a la papelera", role: .destructive) { scanner.moveToTrash(item) }
            }
            
            // Children (when expanded)
            if isExpanded || isRoot {
                ForEach(filteredChildren) { child in
                    FileRowView(
                        item: child,
                        depth: depth + 1,
                        scanner: scanner,
                        expandedItems: $expandedItems
                    )
                }
            }
        }
        .onAppear {
            if isRoot { expandedItems.insert(item.id) }
        }
    }
    
    private func selectItem() {
        scanner.selectedItem = item
    }
    
    private func toggleExpand() {
        if expandedItems.contains(item.id) {
            expandedItems.remove(item.id)
        } else {
            expandedItems.insert(item.id)
        }
    }
    
    private func sizeBarColor(pct: Double) -> Color {
        switch pct {
        case 0.5...:  return .red.opacity(0.75)
        case 0.2...:  return .orange.opacity(0.75)
        case 0.05...: return .yellow.opacity(0.75)
        default:      return .green.opacity(0.6)
        }
    }
}

// MARK: - Status Bar

struct StatusBarView: View {
    @ObservedObject var scanner: DiskScanner

    var body: some View {
        VStack(spacing: 0) {
            // Barra de progreso animada durante el escaneo
            if scanner.isScanning {
                ProgressView()
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 10)
                    .padding(.top, 5)
                    .padding(.bottom, 1)
            }

            HStack(spacing: 6) {
                if scanner.isScanning {
                    // Contador en vivo + velocidad
                    Text("\(scanner.totalScanned.formatted()) elementos")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()

                    if scanner.scanRate > 0 {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text("\(formatRate(scanner.scanRate))/s")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: scanner.rootItem == nil ? "externaldrive" : "checkmark.circle.fill")
                        .foregroundStyle(scanner.rootItem == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.green))
                        .font(.system(size: 11))

                    Text(scanner.statusMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(.regularMaterial)
    }

    private func formatRate(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    @ObservedObject var scanner: DiskScanner

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 16)

                Image(systemName: "externaldrive.badge.magnifyingglass")
                    .font(.system(size: 52))
                    .foregroundStyle(.secondary)

                VStack(spacing: 6) {
                    Text("Disk Analyzer")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Analiza el uso del espacio en disco")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Button(action: { scanner.selectDirectory() }) {
                    Label("Seleccionar directorio...", systemImage: "folder.badge.plus")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("o", modifiers: .command)

                // ── Recientes ────────────────────────────────────────────
                if !scanner.recentDirectories.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("RECIENTES")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)

                        VStack(spacing: 0) {
                            ForEach(scanner.recentDirectories, id: \.path) { url in
                                Button(action: { scanner.startScan(url: url) }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: url.pathComponents.count <= 2
                                              ? "externaldrive.fill" : "folder.fill")
                                            .foregroundStyle(.accentColor)
                                            .frame(width: 20)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent)
                                                .font(.system(size: 12, weight: .medium))
                                                .lineLimit(1)
                                            Text(url.path)
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.head)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)

                                if url != scanner.recentDirectories.last {
                                    Divider().padding(.leading, 38)
                                }
                            }
                        }
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
                        )
                    }
                    .frame(maxWidth: 340)
                }

                Spacer().frame(height: 16)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
    }
}
