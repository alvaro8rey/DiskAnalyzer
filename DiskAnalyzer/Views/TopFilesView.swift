import SwiftUI
import UniformTypeIdentifiers

struct TopFilesView: View {
    @ObservedObject var scanner: DiskScanner

    @State private var selectedIDs: Set<UUID> = []
    @State private var sortOrder: [KeyPathComparator<FileItem>] = [
        KeyPathComparator(\.totalSize, order: .reverse)
    ]
    @State private var minSize: Int64 = 0
    @State private var allFiles: [FileItem] = []

    private let filterOptions: [(label: String, short: String, size: Int64)] = [
        ("Todos",   "Todo",  0),
        (">1 MB",   "1 MB",  1_048_576),
        (">10 MB",  "10 MB", 10_485_760),
        (">100 MB", "100M",  104_857_600),
        (">1 GB",   "1 GB",  1_073_741_824)
    ]

    var displayedFiles: [FileItem] {
        let filtered = minSize == 0 ? allFiles : allFiles.filter { $0.totalSize >= minSize }
        return filtered.sorted(using: sortOrder)
    }

    var body: some View {
        mainContent
            .onAppear { refreshFiles() }
            .onChange(of: scanner.isScanning) { _, scanning in
                if !scanning { refreshFiles() }
            }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                toolbarContent(width: geo.size.width)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 50)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if allFiles.isEmpty { emptyState } else { fileTable }
        }
    }

    private var fileTable: some View {
        Table(displayedFiles, selection: $selectedIDs, sortOrder: $sortOrder) {
            tableColumns
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            tableContextMenu(for: ids)
        }
        .onChange(of: selectedIDs) { _, ids in
            if let id = ids.first, let item = allFiles.first(where: { $0.id == id }) {
                scanner.selectedItem = item
            }
        }
    }

    @TableColumnBuilder<FileItem, KeyPathComparator<FileItem>>
    private var tableColumns: some TableColumnContent<FileItem, KeyPathComparator<FileItem>> {
        TableColumn("Nombre", value: \.name) { item in
            HStack(spacing: 6) {
                Image(systemName: item.icon)
                    .foregroundStyle(item.iconColor)
                    .font(.system(size: 11))
                    .frame(width: 16)
                Text(item.name).lineLimit(1)
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

    @ViewBuilder
    private func tableContextMenu(for ids: Set<UUID>) -> some View {
        let selected = allFiles.filter { ids.contains($0.id) }
        if selected.count == 1, let item = selected.first {
            Button("Mostrar en Finder") { scanner.revealInFinder(item) }
            Button("Abrir")             { scanner.openFile(item) }
            Button("Copiar ruta")       { scanner.copyPath(item) }
            Divider()
            Button("Mover a la papelera", role: .destructive) {
                scanner.confirmAndMoveToTrash(item)
                allFiles.removeAll { $0.id == item.id }
            }
        } else if selected.count > 1 {
            Button("Copiar rutas (\(selected.count))") {
                let paths = selected.map { $0.url.path }.joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(paths, forType: .string)
            }
            Divider()
            Button("Mover \(selected.count) elementos a la papelera", role: .destructive) {
                scanner.confirmAndMoveMultipleToTrash(selected) { moved in
                    let ids = Set(moved.map { $0.id })
                    allFiles.removeAll { ids.contains($0.id) }
                    selectedIDs.subtract(ids)
                }
            }
        }
    }

    // ── Sub-views ────────────────────────────────────────────────────────

    @ViewBuilder
    private func toolbarContent(width w: CGFloat) -> some View {
        HStack(spacing: 8) {
            if w > 480 {
                titleAndCount
            } else {
                Text("\(displayedFiles.count.formatted()) archivos")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if w > 310 {
                shortFilterPicker.pickerStyle(.segmented).fixedSize()
            } else {
                filterMenuPicker.pickerStyle(.menu).fixedSize()
            }
            Button(action: exportToCSV) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Exportar resultados a CSV")
            .disabled(allFiles.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

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

    /// Picker segmentado con etiquetas cortas (~220 px intrínseco)
    private var shortFilterPicker: some View {
        Picker("Mostrar", selection: $minSize) {
            ForEach(filterOptions, id: \.size) { opt in
                Text(opt.short).tag(opt.size)
            }
        }
    }

    /// Picker compacto tipo menú (siempre cabe)
    private var filterMenuPicker: some View {
        Picker("Mostrar", selection: $minSize) {
            ForEach(filterOptions, id: \.size) { opt in
                Text(opt.label).tag(opt.size)
            }
        }
    }

    // ── Helpers ─────────────────────────────────────────────────────────

    private func exportToCSV() {
        let csv = scanner.exportTopFilesToCSV()
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.commaSeparatedText]
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            panel.nameFieldStringValue = "DiskAnalyzer_\(df.string(from: Date())).csv"
            panel.title = "Exportar resultados"
            panel.makeKeyAndOrderFront(nil)
            if panel.runModal() == .OK, let url = panel.url {
                try? csv.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

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
