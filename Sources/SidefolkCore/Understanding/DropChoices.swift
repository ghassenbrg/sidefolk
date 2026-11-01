import Foundation

/// What can be done with something dropped on the companion (D84): four likely choices by kind, the first one what
/// Return does. Each is a path that already exists (a note, a watch, Ask, a reminder, the clipboard, an app, Miraya's
/// tool); the app shows them as a 2×2 card in Ask and runs them.
public enum DropChoice: String, Sendable, CaseIterable {
    case save, watch, ask, openWith, remind, copy, playOnTV
}

public enum DropKind: Sendable, Equatable {
    case file, folder, link, text
}

public enum DropChoices {
    /// The four choices for this kind, the likeliest first. A link to a video file or stream plays on the TV when
    /// Miraya is there to do it; any other link offers a reminder to look at it.
    public static func choices(for kind: DropKind, link: URL? = nil, canPlayOnTV: Bool = false) -> [DropChoice] {
        switch kind {
        case .file, .folder: [.save, .watch, .ask, .openWith]
        case .link: [.save, .watch, .ask, canPlayOnTV && link.map(isVideoLink) == true ? .playOnTV : .remind]
        case .text: [.save, .remind, .ask, .copy]
        }
    }

    /// Endings of video files and streams a TV plays.
    static let videoEndings: Set<String> = ["mp4", "m4v", "mov", "mkv", "webm", "m3u8", "ts", "avi"]

    /// An https link to the video itself, which Miraya can hand a TV; a web page with a video in it (YouTube) isn't.
    public static func isVideoLink(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false && videoEndings.contains(url.pathExtension.lowercased())
    }
}
