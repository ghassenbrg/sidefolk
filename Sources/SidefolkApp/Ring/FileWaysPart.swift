import AppKit
import KeyboardShortcuts
import SidefolkCore
import SwiftUI

/// Sidefolk's own ways to hand files over (D152), on any page that places them: the ring's switch and keys, and Finder's right-click.
/// They belong to Sidefolk, since the ring serves every extension with a file offer.
struct FileWaysPart: View {
    var services: (any AppServices)?
    @State private var ring = FileRingSettings()

    var body: some View {
        RowsCard {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: "circle.circle").foregroundStyle(Theme.inkMuted).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text("The ring", comment: "A switch for the ring of what a file can become").font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                    Text("Off until you turn it on, since it looks for a file being dragged.", comment: "Under the ring's switch")
                        .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                }
                Spacer(minLength: Theme.Space.m)
                Toggle(isOn: Binding(get: { ring.enabled }, set: { on in change { $0.enabled = on } })) {
                    Text("The ring", comment: "A switch for the ring of what a file can become")
                }
                .labelsHidden().toggleStyle(.switch)
            }
            .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s + 2)
            row(symbol: nil, text: Text("Hold this while dragging a file, and the ring opens at the pointer.", comment: "The ring: its key during a drag")) {
                Picker(selection: Binding(get: { ring.dragKey }, set: { key in change { $0.dragKey = key } })) {
                    ForEach(FileRingSettings.DragKey.allCases, id: \.self) { Text(verbatim: $0.keycap).tag($0) }
                } label: { Text("Key", comment: "The ring: the menu choosing its key") }
                    .labelsHidden().fixedSize()
            }
            .disabled(!ring.enabled)
            row(symbol: nil, text: Text("Opens the ring for the files selected in Finder.", comment: "The ring: its shortcut")) {
                KeyboardShortcuts.Recorder(for: .fileRing)
            }
            .disabled(!ring.enabled)
            row(symbol: "contextualmenu.and.cursorarrow", text: Text("Right-click a file in Finder and choose Send to Sidefolk.", comment: "A way to hand a file over: Finder's Service")) { EmptyView() }
        }
        .onAppear { ring = services?.runtime.settings.current.fileRing ?? FileRingSettings() }
    }

    private func row<End: View>(symbol: String?, text: Text, @ViewBuilder end: () -> End) -> some View {
        HStack(spacing: Theme.Space.m) {
            if let symbol { Image(systemName: symbol).foregroundStyle(Theme.inkMuted).frame(width: 22) } else { Color.clear.frame(width: 22, height: 1) }
            text.font(Theme.Font.body).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.Space.m)
            end()
        }
        .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s + 2)
    }

    private func change(_ edit: @escaping @Sendable (inout FileRingSettings) -> Void) {
        edit(&ring)
        guard let services else { return }
        Task {
            await services.runtime.settings.update { edit(&$0.fileRing) }
            await MainActor.run { services.settingsChanged() }
        }
    }
}
