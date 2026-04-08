import SwiftUI

// MARK: - FileTypesView

struct FileTypesView: View {
    @ObservedObject var scanner: DiskScanner

    @State private var selectedCategory: FileCategory? = nil
    @State private var groups: [FileTypeGroup] = []

    var totalSize: Int64 { groups.reduce(0) { $0 + $1.totalSize } }

    var body: some View {
        HSplitView {
            categoryList
                .frame(minWidth: 260, idealWidth: 310)

            rightPane
        }
        .onAppear { groups = scanner.fileTypeGroups }
        .onChange(of: scanner.isScanning) { scanning in
            if !scanning { groups = scanner.fileTypeGroups }
        }
    }

    // ── Left: category list ──────────────────────────────────────────────

    var categoryList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Uso por tipo de archivo")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if totalSize > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if groups.isEmpty {
                ContentUnavailableView(
                    scanner.isScanning ? "Analizando..." : "Sin datos",
                    systemImage: "chart.bar.fill",
                    description: Text(scanner.isScanning
                                      ? "Espera a que termine el escaneo"
                                      : "Analiza un directorio primero")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(groups) { group in
                            FileTypeCategoryRow(
                                group: group,
                                totalSize: totalSize,
                                isSelected: selectedCategory == group.category
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { selectedCategory = group.category }

                            Divider().padding(.leading, 50)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // ── Right: file list for selected category ───────────────────────────

    @ViewBuilder
    var rightPane: some View {
        if let cat = selectedCategory {
            CategoryFilesView(scanner: scanner, category: cat)
        } else {
            Color(NSColor.underPageBackgroundColor)
                .overlay {
                    if !groups.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "hand.tap")
                                .font(.system(size: 36))
                                .foregroundStyle(.secondary)
                            Text("Selecciona una categoría")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
        }
    }
}

// MARK: - Category Row

struct FileTypeCategoryRow: View {
    let group: FileTypeGroup
    let totalSize: Int64
    let isSelected: Bool

    @State private var isHovered = false

    var pct: Double {
        totalSize > 0 ? Double(group.totalSize) / Double(totalSize) : 0
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(group.category.color.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: group.category.icon)
                    .foregroundStyle(group.category.color)
                    .font(.system(size: 17))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(group.category.rawValue)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(group.formattedSize)
                        .font(.system(size: 11, design: .monospaced))
                    Text(String(format: "%.1f%%", pct * 100))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }

                // Size bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.12))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(group.category.color.opacity(0.75))
                            .frame(width: max(2, geo.size.width * pct))
                    }
                }
                .frame(height: 5)

                Text("\(group.count.formatted()) archivos")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Group {
                if isSelected        { Color.accentColor.opacity(0.12) }
                else if isHovered    { Color.secondary.opacity(0.06) }
                else                 { Color.clear }
            }
        )
        .onHover { isHovered = $0 }
    }
}

// MARK: - Category Files View

struct CategoryFilesView: View {
    @ObservedObject var scanner: DiskScanner
    let category: FileCategory

    @State private var files: [FileItem] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .foregroundStyle(category.color)
                Text(category.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(files.count.formatted()) archivos")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(ByteCountFormatter.string(
                    fromByteCount: files.reduce(0) { $0 + $1.totalSize },
                    countStyle: .file))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if files.isEmpty {
                ContentUnavailableView(
                    "Sin archivos",
                    systemImage: category.icon,
                    description: Text("No se encontraron archivos de tipo \(category.rawValue.lowercased())")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(files) { file in
                            CategoryFileRow(item: file, scanner: scanner)
                            Divider().padding(.leading, 42)
                        }
                    }
                }
            }
        }
        .onAppear { loadFiles() }
        .onChange(of: category) { _ in loadFiles() }
    }

    private func loadFiles() {
        guard let root = scanner.rootItem else { files = []; return }
        var result: [FileItem] = []
        func traverse(_ item: FileItem) {
            if !item.isDirectory,
               FileCategory.category(forExtension: item.url.pathExtension) == category {
                result.append(item)
            }
            item.children?.forEach { traverse($0) }
        }
        traverse(root)
        files = result.sorted { $0.totalSize > $1.totalSize }
    }
}

// MARK: - Category File Row

struct CategoryFileRow: View {
    let item: FileItem
    @ObservedObject var scanner: DiskScanner
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .foregroundStyle(item.iconColor)
                .font(.system(size: 12))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Text(item.url.deletingLastPathComponent().path)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer()

            Text(item.formattedSize)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(isHovered ? Color.secondary.opacity(0.07) : Color.clear)
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
        .onTapGesture { scanner.selectedItem = item }
        .contextMenu {
            Button("Mostrar en Finder") { scanner.revealInFinder(item) }
            Button("Abrir")             { scanner.openFile(item) }
            Button("Copiar ruta")        { scanner.copyPath(item) }
            Divider()
            Button("Mover a la papelera", role: .destructive) { scanner.moveToTrash(item) }
        }
    }
}
