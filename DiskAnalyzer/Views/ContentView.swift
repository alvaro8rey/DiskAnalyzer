import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var scanner = DiskScanner()

    var body: some View {
        HSplitView {
            // MARK: Sidebar — Tree List
            SidebarView(scanner: scanner)
                .frame(minWidth: 300, idealWidth: 460, maxWidth: .infinity)

            // MARK: Detail — Treemap + Info
            DetailView(scanner: scanner)
                .frame(minWidth: 380)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: { scanner.selectDirectory() }) {
                    Label("Abrir directorio", systemImage: "folder.badge.plus")
                }
                .help("Abrir directorio para analizar (⌘O)")

                if scanner.isScanning {
                    Button(action: { scanner.cancelScan() }) {
                        Label("Cancelar", systemImage: "stop.circle.fill")
                    }
                    .foregroundColor(.red)
                    .help("Cancelar análisis")
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Ordenar", selection: Binding(
                    get: { scanner.sortOption },
                    set: { scanner.sortOption = $0; scanner.resort() }
                )) {
                    ForEach(SortOption.allCases) { opt in
                        Text(opt.rawValue).tag(opt)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openDirectoryPicker)) { _ in
            scanner.selectDirectory()
        }
    }
}
