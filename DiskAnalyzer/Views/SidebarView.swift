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
            .onTapGesture { selectItem() }
            .onTapGesture(count: 2) {
                if item.isDirectory { toggleExpand() }
            }
            .onHover { isHovered = $0 }
            .contextMenu {
                Button("Mostrar en Finder") { scanner.revealInFinder(item) }
                Button("Abrir") { scanner.openFile(item) }
                Divider()
                Button("Obtener información") { scanner.getInfo(item) }
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
        HStack(spacing: 8) {
            if scanner.isScanning {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: scanner.rootItem == nil ? "externaldrive" : "checkmark.circle.fill")
                    .foregroundStyle(scanner.rootItem == nil ? .secondary : .green)
                    .font(.system(size: 11))
            }
            
            Text(scanner.statusMessage)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial)
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    @ObservedObject var scanner: DiskScanner
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "externaldrive.badge.magnifyingglass")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 8) {
                Text("Disk Analyzer")
                    .font(.system(size: 20, weight: .semibold))
                Text("Analiza el uso del espacio en disco\ncomo WinDirStat / TreeSize")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: { scanner.selectDirectory() }) {
                Label("Seleccionar directorio...", systemImage: "folder.badge.plus")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("o", modifiers: .command)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
