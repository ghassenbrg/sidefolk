import SidefolkCore
import SwiftUI

/// How a collection looks in the sidebar and its header (D53): the person's emoji or symbol and colour, else
/// the kind's own. Colours are stored by name, so the palette can be retuned without touching anyone's data.
enum CollectionLook {
    static let colors: [(name: String, color: Color)] = [
        ("red", Color(hex: 0xF0605D)), ("orange", Color(hex: 0xF5913E)), ("yellow", Color(hex: 0xF2C230)),
        ("green", Color(hex: 0x4CC26E)), ("mint", Color(hex: 0x3CCFB4)), ("teal", Theme.aqua),
        ("blue", Color(hex: 0x3E8BF0)), ("indigo", Color(hex: 0x6366E8)), ("purple", Color(hex: 0xA25DDC)),
        ("pink", Color(hex: 0xEE6BA8)), ("brown", Color(hex: 0xA77B58)), ("gray", Color(hex: 0x8A97AD)),
    ]

    static let symbols = [
        "folder.fill", "tray.fill", "star.fill", "heart.fill", "bookmark.fill", "flag.fill",
        "lightbulb.fill", "sparkles", "flame.fill", "bolt.fill", "leaf.fill", "pawprint.fill",
        "book.fill", "graduationcap.fill", "briefcase.fill", "hammer.fill", "paintbrush.fill", "music.note",
        "camera.fill", "gamecontroller.fill", "airplane", "house.fill", "cart.fill", "fork.knife",
        "dumbbell.fill", "cross.case.fill", "dollarsign.circle.fill", "calendar", "checklist", "globe",
    ]

    static func color(_ c: NotebookCollection) -> Color {
        if let name = c.color, let found = colors.first(where: { $0.name == name }) { return found.color }
        return c.kind == .profile ? Theme.aqua : Theme.folkColor("pip")
    }

    static func symbol(_ c: NotebookCollection) -> String {
        if let symbol = c.symbol, !symbol.isEmpty { return symbol }
        switch c.kind {
        case .inbox: return "tray.fill"
        case .profile: return "person.crop.circle.fill"
        case .project: return "folder.fill"
        case .topic: return "number"
        case .list: return "checklist"
        }
    }
}

/// A collection's emoji, or its symbol in its colour.
struct CollectionIcon: View {
    var collection: NotebookCollection
    var size: CGFloat = 13
    /// In Home's navigation, where colorful icons are tiles (D67); an emoji is colourful already.
    var nav = false

    var body: some View {
        if let emoji = collection.emoji, !emoji.isEmpty {
            Text(verbatim: emoji).font(.system(size: size + 1))
        } else if nav {
            NavIcon(symbol: CollectionLook.symbol(collection), color: CollectionLook.color(collection))
        } else {
            Image(systemName: CollectionLook.symbol(collection)).foregroundStyle(CollectionLook.color(collection))
        }
    }
}

/// The same on a tinted tile, for a collection's header.
struct CollectionTile: View {
    var collection: NotebookCollection
    var size: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(CollectionLook.color(collection).opacity(0.2))
            .frame(width: size, height: size)
            .overlay {
                if let emoji = collection.emoji, !emoji.isEmpty {
                    Text(verbatim: emoji).font(.system(size: size * 0.55))
                } else {
                    Image(systemName: CollectionLook.symbol(collection))
                        .font(.system(size: size * 0.46, weight: .semibold))
                        .foregroundStyle(CollectionLook.color(collection))
                }
            }
            .accessibilityHidden(true)
    }
}

/// Picking an icon and a colour, in the collection sheet: a colour row, then symbols, and an emoji instead.
struct CollectionLookPicker: View {
    @Binding var symbol: String?
    @Binding var color: String?
    @Binding var emoji: String
    var kind: NotebookCollection.Kind

    private var preview: NotebookCollection {
        var c = NotebookCollection(name: "", kind: kind)
        c.symbol = symbol
        c.color = color
        c.emoji = emoji.isEmpty ? nil : emoji
        return c
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: 6) {
                ForEach(CollectionLook.colors, id: \.name) { option in
                    Button { color = option.name } label: {
                        Circle().fill(option.color).frame(width: 20, height: 20)
                            .overlay { if color == option.name { Circle().strokeBorder(Theme.ink.opacity(0.7), lineWidth: 2).padding(-3) } }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: option.name))
                    .accessibilityAddTraits(color == option.name ? .isSelected : [])
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 10), spacing: 6) {
                ForEach(CollectionLook.symbols, id: \.self) { name in
                    Button { symbol = name; emoji = "" } label: {
                        Image(systemName: name).font(.system(size: 13, weight: .medium)).frame(width: 30, height: 30)
                            .foregroundStyle(chosen(name) ? CollectionLook.color(preview) : Theme.inkMuted)
                            .background(chosen(name) ? CollectionLook.color(preview).opacity(0.18) : Theme.surfaceSunken,
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: name))
                    .accessibilityAddTraits(chosen(name) ? .isSelected : [])
                }
            }
            HStack(spacing: Theme.Space.s) {
                CollectionTile(collection: preview, size: 30)
                TextField("Emoji", text: Binding(get: { emoji }, set: { emoji = String($0.trimmingCharacters(in: .whitespaces).prefix(2)) }),
                          prompt: Text("Or an emoji"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                Spacer()
                if symbol != nil || color != nil || !emoji.isEmpty {
                    Button("Reset") { symbol = nil; color = nil; emoji = "" }.buttonStyle(.sfPlain)
                }
            }
        }
    }

    private func chosen(_ name: String) -> Bool { emoji.isEmpty && CollectionLook.symbol(preview) == name }
}
