import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var scanner = DiskScanner()

    var body: some View {
        HSplitView {
            SidebarView(scanner: scanner)
                .frame(minWidth: 300, idealWidth: 460, maxWidth: .infinity)
            DetailView(scanner: scanner)
                .frame(minWidth: 380)
        }
        .toolbar {
            // ── Navigation: abrir / cancelar / archivos ocultos ──────────
            ToolbarItemGroup(placement: .navigation) {
                Button(action: { scanner.selectDirectory() }) {
                    Label("Abrir directorio", systemImage: "folder.badge.plus")
                }
                .help("Abrir directorio (⌘O)")

                if scanner.isScanning {
                    Button(action: { scanner.cancelScan() }) {
                        Label("Cancelar", systemImage: "stop.circle.fill")
                    }
                    .foregroundColor(.red)
                    .help("Cancelar análisis en curso")
                }

                if scanner.rootItem != nil, !scanner.isScanning {
                    Button(action: { scanner.rescan() }) {
                        Label("Volver a analizar", systemImage: "arrow.clockwise")
                    }
                    .help("Volver a analizar el mismo directorio")

                    Button(action: {
                        scanner.showHiddenFiles.toggle()
                        scanner.rescan()
                    }) {
                        Label(
                            scanner.showHiddenFiles ? "Ocultar archivos ocultos" : "Mostrar archivos ocultos",
                            systemImage: scanner.showHiddenFiles ? "eye.fill" : "eye.slash"
                        )
                    }
                    .help(scanner.showHiddenFiles
                          ? "Excluir archivos ocultos del análisis"
                          : "Incluir archivos ocultos (. prefijo)")
                }
            }

            // ── Centro: selector de vista ────────────────────────────────
            ToolbarItem(placement: .principal) {
                if scanner.rootItem != nil {
                    Picker("Vista", selection: $scanner.viewMode) {
                        ForEach(ViewMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 230)
                }
            }

            // ── Derecha: ordenación (sólo en modo árbol) ─────────────────
            ToolbarItemGroup(placement: .primaryAction) {
                if scanner.viewMode == .treemap, scanner.rootItem != nil {
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
        }
        .onReceive(NotificationCenter.default.publisher(for: .openDirectoryPicker)) { _ in
            scanner.selectDirectory()
        }
    }
}
