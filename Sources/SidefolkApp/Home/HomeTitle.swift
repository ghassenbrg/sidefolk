import SwiftUI

/// The large-title behaviour of Home's places (D93's fix): a place whose page has its own title (an extension's page
/// Today, On duty, a watch, You, a collection) shows it once, large, in the page; the toolbar's
/// small title appears only after that one has scrolled up under the toolbar, as macOS does. A place without one keeps
/// the toolbar's title.
@MainActor @Observable
final class HomeTitleTracker {
    /// Where the toolbar ends, in the window's coordinates: the top of the page's scroll view (`clipsUnderToolbar`).
    var toolbarBottom: CGFloat = 0
    /// The page titles in sight now (a page leaving and the next arriving may overlap for a moment).
    private(set) var shown: Set<UUID> = []

    var pageTitleShown: Bool { !shown.isEmpty }

    func set(_ id: UUID, shown visible: Bool) {
        if visible { shown.insert(id) } else { shown.remove(id) }
    }
}

extension View {
    /// Marks the page's own title, so the toolbar keeps its small title out of the way while this is in sight.
    func homePageTitle() -> some View { modifier(HomePageTitle()) }
}

private struct HomePageTitle: ViewModifier {
    @Environment(HomeTitleTracker.self) private var tracker: HomeTitleTracker?
    @State private var id = UUID()
    @State private var bottom: CGFloat = .infinity

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { bottom = $0; update() }
            .onChange(of: tracker?.toolbarBottom) { update() }
            // A page shown again may lay out its title where it was, which reports no change: say it again.
            .onAppear { update() }
            .onDisappear { tracker?.set(id, shown: false) }
    }

    /// Seen while any of it is below the toolbar's edge.
    private func update() {
        guard let tracker else { return }
        tracker.set(id, shown: bottom > tracker.toolbarBottom + 4)
    }
}
