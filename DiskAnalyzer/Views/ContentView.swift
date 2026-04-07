import SwiftUI

struct ContentView: View {
    @StateObject private var scanner = DiskScanner()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // MARK: Sidebar — Tree List
            SidebarView(scanner: scanner)
                .navigationSplitViewColumnWidth(min: 280, ideal: 380, max: 500)
        } detail: {
            // MARK: Detail — Treemap + Info
            DetailView(scanner: scanner)
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
        .onAppear {
            // Optional: auto-scan home or show welcome
        }
    }
}
