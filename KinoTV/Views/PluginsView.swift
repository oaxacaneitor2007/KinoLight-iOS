import SwiftUI
import UIKit

extension Addon {
    var capabilities: [String] {
        var c: [String] = []
        if !stream.isEmpty { c.append("Fuentes") }
        if !catalogs.isEmpty { c.append("Catálogos") }
        if !meta.isEmpty { c.append("Info") }
        if !subtitles.isEmpty { c.append("Subtítulos") }
        return c
    }
    var host: String { URL(string: base)?.host ?? base }
}

// MARK: - Lista de plugins

struct PluginsView: View {
    @EnvironmentObject var store: PluginStore
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false
    @State private var prefill = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { prefill = ""; showAdd = true } label: {
                        Label("Agregar plugin", systemImage: "plus.circle.fill")
                    }
                } footer: {
                    Text("Pega la dirección del manifest de un addon de Stremio (https://…/manifest.json o stremio://…). Para reproducir necesitas al menos un plugin de fuentes que entregue enlaces directos (por ejemplo, uno con servicio debrid). Los torrents puros no se pueden reproducir en iOS.")
                }

                Section("Mis plugins") {
                    if store.userPlugins.isEmpty {
                        Text("Aún no agregaste ninguno.").foregroundStyle(.secondary)
                    }
                    ForEach(store.userPlugins) { p in
                        UserPluginRow(plugin: p)
                    }
                    .onDelete { offsets in store.removeUserPlugins(at: offsets) }
                }

                Section("Incluidos") {
                    ForEach(store.builtin) { a in
                        BuiltinPluginRow(addon: a)
                    }
                }

                Section {
                    Button {
                        Task { await store.refreshPlugins() }
                    } label: {
                        HStack {
                            Label("Actualizar mis plugins", systemImage: "arrow.clockwise")
                            if store.refreshing { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(store.refreshing || store.userPlugins.isEmpty)
                }
            }
            .navigationTitle("Plugins")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
            .sheet(isPresented: $showAdd) {
                AddPluginView(initial: prefill).environmentObject(store)
            }
            .onAppear { takeIncoming() }
            .onChange(of: store.incoming) { _ in takeIncoming() }
        }
    }

    /// Si llego un enlace stremio:// / kinotv://, abre "Agregar" con la direccion ya escrita.
    private func takeIncoming() {
        if let u = store.incoming {
            prefill = u
            store.incoming = nil
            showAdd = true
        }
    }
}

struct UserPluginRow: View {
    @EnvironmentObject var store: PluginStore
    let plugin: UserPlugin

    var body: some View {
        Toggle(isOn: Binding(get: { plugin.enabled }, set: { store.setEnabled(plugin.id, $0) })) {
            VStack(alignment: .leading, spacing: 3) {
                Text(plugin.name)
                if let a = plugin.addon {
                    Text(a.host + " · " + a.capabilities.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let e = plugin.error {
                    Text("Sin respuesta: " + e).font(.caption).foregroundStyle(.orange)
                } else if let n = plugin.note {
                    Text(n).font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }
}

struct BuiltinPluginRow: View {
    @EnvironmentObject var store: PluginStore
    let addon: Addon

    var body: some View {
        Toggle(isOn: Binding(get: { !store.disabledBuiltin.contains(addon.base) },
                             set: { store.setBuiltinEnabled(addon.base, $0) })) {
            VStack(alignment: .leading, spacing: 3) {
                Text(addon.name)
                Text(addon.host + " · " + addon.capabilities.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Agregar

struct AddResultRow: Identifiable {
    let id = UUID()
    let ok: Bool
    let text: String
}

struct AddPluginView: View {
    @EnvironmentObject var store: PluginStore
    @Environment(\.dismiss) private var dismiss
    @State private var input: String
    @State private var busy = false
    @State private var results: [AddResultRow] = []

    init(initial: String) {
        _input = State(initialValue: initial)
    }

    private var canAdd: Bool {
        !busy && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…/manifest.json", text: $input, axis: .vertical)
                        .lineLimit(1...6)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button {
                        if let s = UIPasteboard.general.string { input = s }
                    } label: {
                        Label("Pegar del portapapeles", systemImage: "doc.on.clipboard")
                    }
                } header: {
                    Text("Dirección del addon")
                } footer: {
                    Text("Acepta https://, stremio:// o la dirección sin esquema. Puedes pegar varias, una por línea.")
                }

                if busy {
                    Section { HStack { ProgressView(); Text("Verificando…").foregroundStyle(.secondary) } }
                }

                if !results.isEmpty {
                    Section("Resultado") {
                        ForEach(results) { r in
                            Label(r.text, systemImage: r.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(r.ok ? Color.green : Color.red)
                        }
                    }
                }
            }
            .navigationTitle("Agregar plugin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Agregar") { Task { await add() } }.disabled(!canAdd)
                }
            }
        }
    }

    private func add() async {
        busy = true
        results = []
        let lines = input
            .split(whereSeparator: { $0.isNewline || $0 == " " || $0 == "," })
            .map(String.init)
            .filter { !$0.isEmpty }

        var out: [AddResultRow] = []
        for l in lines {
            switch await store.addPlugin(l) {
            case .added(let name, let warning):
                var t = "Agregado: \(name)."
                if let w = warning { t += " " + w }
                out.append(AddResultRow(ok: true, text: t))
            case .exists(let name):
                out.append(AddResultRow(ok: true, text: "\(name) ya estaba agregado."))
            case .failed(let msg):
                out.append(AddResultRow(ok: false, text: "\(String(l.prefix(40))): \(msg)"))
            }
        }
        results = out
        busy = false
        if !out.isEmpty && out.allSatisfy({ $0.ok }) {
            input = ""
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            dismiss()
        }
    }
}
