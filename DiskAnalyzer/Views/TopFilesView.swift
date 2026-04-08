import SwiftUI

struct TopFilesView: View {
    @ObservedObject var scanner: DiskScanner

    @State private var selectedIDs: Set<UUID> = []
    @State private var sortOrder: [KeyPathComparator<FileItem>] = [
        KeyPathComparator(\.totalSize, order: .reverse)
    ]
    @State private var minSize: Int64 = 0
    @State private var allFiles: [FileItem] = []

    private let filterOptions: [(label: String, size: Int64)] = [
        ("Todos",    0),
        (">1 MB",    1_048_576),
        (">10 MB",   10_485_760),
        (">100 MB",  104_857_600),
        (">1 GB",    1_073_741_824)
    ]

    var displayedFiles: [FileItem] {
        let filtered = minSize == 0 ? allFiles : allFiles.filter { $0.totalSize >= minSize }
        return filtered.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Toolbar (adaptativa con GeometryReader) ──────────────────
            GeometryReader { geo in
                let w = geo.size.width
                HStack(spacing: 8) {
                    if w > 460 {
                        titleAndCount
                    } else {
                        Text("\(displayedFiles.count.formatted()) archivos")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    if w > 440 {
                        filterPicker.pickerStyle(.segmented).frame(width: 280)
                    } else if w > 330 {
                        filterPicker.pickerStyle(.segmented).frame(width: 195)
                    } else {
                        filterPicker.pickerStyle(.menu).fixedSize()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 50)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // ── Content ──────────────────────────────────────────────────
            if allFiles.isEmpty {
                emptyState
            } else {
                Table(displayedFiles, selection: $selectedIDs, sortOrder: $sortOrder) {
                    TableColumn("Nombre", value: \.name) { item in
                        HStack(spacing: 6) {
                            Image(systemName: item.icon)
                                .foregroundStyle(item.iconColor)
                                .font(.system(size: 11))
                                .frame(width: 16)
                            Text(item.name)
                                .lineLimit(1)
                        }
                    }
                    TableColumn("Tamaño", value: \.totalSize) { item in
                        Text(item.formattedSize)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .width(90)
                    TableColumn("Tipo") { item in
                        let ext = item.url.pathExtension.lowercased()
                        Text(ext.isEmpty ? "—" : ".\(ext)")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    .width(64)
                    TableColumn("Ubicación") { item in
                        Text(item.url.deletingLastPathComponent().path)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    TableColumn("Modificado") { item in
                        Text(item.formattedDate)
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                            .lineLimit(1)
                    }
                    .width(150)
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    if let id = ids.first,
                       let item = allFiles.first(where: { $0.id == id }) {
                        Button("Mostrar en Finder") { scanner.revealInFinder(item) }
                        Button("Abrir")             { scanner.openFile(item) }
                        Button("Copiar ruta")        { scanner.copyPath(item) }
                        Divider()
                        Button("Mover a la papelera", role: .destructive) {
                            scanner.moveToTrash(item)
                            allFiles.removeAll { $0.id == item.id }
                        }
                    }
                }
                .onChange(of: selectedIDs) { ids in
                    if let id = ids.first,
                       let item = allFiles.first(where: { $0.id == id }) {
                        scanner.selectedItem = item
                    }
                }
            }
        }
        .onAppear { refreshFiles() }
        .onChange(of: scanner.isScanning) { scanning in
            if !scanning { refreshFiles() }
        }
    }

    // ── Sub-views ────────────────────────────────────────────────────────

    private var titleAndCount: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Archivos más grandes")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Text("\(displayedFiles.count.formatted()) archivos")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var filterPicker: some View {
        Picker("Mostrar", selection: $minSize) {
            ForEach(filterOptions, id: \.size) { opt in
                Text(opt.label).tag(opt.size)
            }
        }
    }

    // ── Helpers ─────────────────────────────────────────────────────────

    private func refreshFiles() {
        allFiles = scanner.topFiles
    }

    private var emptyState: some View {
        ContentUnavailableView(
            scanner.isScanning ? "Analizando..." : "Sin datos",
            systemImage: scanner.isScanning ? "arrow.2.circlepath" : "list.number",
            description: Text(scanner.isScanning
                              ? "Espera a que termine el escaneo"
                              : "Analiza un directorio primero")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
