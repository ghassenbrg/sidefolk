import Foundation

/// What a collection can look like (D53, D117), for its sheet and for the tool that changes it.
public enum CollectionLooks {
    /// Colours are stored by name, so the palette can be retuned without touching anyone's data; a person's own is #rrggbb.
    public static let colorNames = ["red", "orange", "yellow", "green", "mint", "teal", "blue", "indigo", "purple", "pink", "brown", "gray"]

    public static let symbols = [
        "folder.fill", "tray.fill", "archivebox.fill", "doc.text.fill", "note.text", "list.bullet", "checklist", "bookmark.fill", "tag.fill", "paperclip",
        "star.fill", "heart.fill", "flag.fill", "bell.fill", "lightbulb.fill", "sparkles", "flame.fill", "bolt.fill", "drop.fill", "snowflake",
        "leaf.fill", "tree.fill", "pawprint.fill", "fish.fill", "bird.fill", "ant.fill", "ladybug.fill", "sun.max.fill", "moon.fill", "cloud.fill",
        "book.fill", "books.vertical.fill", "graduationcap.fill", "pencil", "paintbrush.fill", "paintpalette.fill", "scissors", "ruler.fill", "hammer.fill", "wrench.fill",
        "briefcase.fill", "building.2.fill", "chart.bar.fill", "chart.pie.fill", "banknote.fill", "creditcard.fill", "dollarsign.circle.fill", "cart.fill", "bag.fill", "gift.fill",
        "music.note", "guitars.fill", "mic.fill", "headphones", "camera.fill", "film.fill", "tv.fill", "gamecontroller.fill", "puzzlepiece.fill", "dice.fill",
        "airplane", "car.fill", "bicycle", "tram.fill", "ferry.fill", "map.fill", "globe", "mountain.2.fill", "tent.fill", "beach.umbrella.fill",
        "house.fill", "bed.double.fill", "sofa.fill", "fork.knife", "cup.and.saucer.fill", "wineglass.fill", "carrot.fill", "birthday.cake.fill", "dumbbell.fill", "figure.run",
        "cross.case.fill", "pills.fill", "stethoscope", "brain.head.profile", "person.2.fill", "figure.2.and.child.holdinghands", "laptopcomputer", "terminal.fill", "server.rack", "cpu.fill",
    ]

    /// A colour's name, or #rrggbb.
    public static func isColor(_ text: String) -> Bool {
        colorNames.contains(text.lowercased()) || hex(text) != nil
    }

    public static func hex(_ text: String) -> UInt32? {
        guard text.first == "#", text.count == 7, text.dropFirst().allSatisfy(\.isHexDigit) else { return nil }
        return UInt32(text.dropFirst(), radix: 16)
    }

    /// An emoji for an icon, or nil: one picture, not any text, and not a pile of combining marks to draw.
    public static func emoji(_ text: String) -> String? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count == 1, clean.unicodeScalars.count <= 8, clean.unicodeScalars.contains(where: \.properties.isEmoji) else { return nil }
        return clean
    }
}
