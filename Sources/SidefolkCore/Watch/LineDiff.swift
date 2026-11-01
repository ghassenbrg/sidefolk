import Foundation

/// One line of "what changed" between two versions of a watch's text (D87).
public enum DiffLine: Sendable, Hashable {
    case same(String)
    case removed(String)
    case added(String)
    /// Unchanged lines folded away.
    case skipped(Int)

    public var isChange: Bool {
        switch self {
        case .removed, .added: true
        case .same, .skipped: false
        }
    }
}

/// A row of the side-by-side view: before on the leading side, after on the trailing side. A line that only one side has
/// leaves the other empty.
public struct DiffRow: Sendable, Hashable {
    public var before: DiffLine?
    public var after: DiffLine?
}

/// Line by line differences for the watch detail page, in reading order with a little context around each change. Unlike
/// `TextDiff` (which decides whether a page changed and ignores dates and counters), this shows every line that differs:
/// the person asked to see it.
public enum LineDiff {
    /// Lines shown around each change; longer unchanged stretches fold into `.skipped`.
    public static let context = 2
    /// Lines shown at most; the rest fold into one `.skipped` at the end.
    public static let maxLines = 600

    public static func inline(old: String, new: String, context: Int = context, limit: Int = maxLines) -> [DiffLine] {
        let full = merged(old: old, new: new)
        guard full.contains(where: \.isChange) else { return [] }
        var near = Set<Int>()
        for (i, line) in full.enumerated() where line.isChange {
            near.formUnion(max(0, i - context)...min(full.count - 1, i + context))
        }
        var out: [DiffLine] = []
        var folded = 0
        for (i, line) in full.enumerated() {
            if near.contains(i) {
                if folded > 0 { out.append(.skipped(folded)) }
                folded = 0
                out.append(line)
            } else {
                folded += 1
            }
        }
        if folded > 0 { out.append(.skipped(folded)) }
        guard out.count > limit else { return out }
        let hidden = out[limit...].reduce(0) { sum, line in
            if case .skipped(let n) = line { return sum + n }
            return sum + 1
        }
        return Array(out.prefix(limit)) + [.skipped(hidden)]
    }

    /// The same lines in two columns: a removed line beside the line that came in its place.
    public static func sideBySide(old: String, new: String, context: Int = context, limit: Int = maxLines) -> [DiffRow] {
        var rows: [DiffRow] = []
        var removed: [DiffLine] = []
        var added: [DiffLine] = []
        func pair() {
            for k in 0..<max(removed.count, added.count) {
                rows.append(DiffRow(before: k < removed.count ? removed[k] : nil, after: k < added.count ? added[k] : nil))
            }
            removed.removeAll()
            added.removeAll()
        }
        for line in inline(old: old, new: new, context: context, limit: limit) {
            switch line {
            case .removed:
                if !added.isEmpty { pair() }
                removed.append(line)
            case .added: added.append(line)
            case .same, .skipped:
                pair()
                rows.append(DiffRow(before: line, after: line))
            }
        }
        pair()
        return rows
    }

    /// Every line of both versions in reading order: at each place, what went before what came.
    static func merged(old: String, new: String) -> [DiffLine] {
        let a = old.isEmpty ? [] : old.components(separatedBy: "\n")
        let b = new.isEmpty ? [] : new.components(separatedBy: "\n")
        var gone = Set<Int>()
        var came = Set<Int>()
        for change in b.difference(from: a) {
            switch change {
            case .remove(let offset, _, _): gone.insert(offset)
            case .insert(let offset, _, _): came.insert(offset)
            }
        }
        var out: [DiffLine] = []
        var i = 0
        var j = 0
        while i < a.count || j < b.count {
            if i < a.count, gone.contains(i) {
                out.append(.removed(a[i]))
                i += 1
            } else if j < b.count, came.contains(j) {
                out.append(.added(b[j]))
                j += 1
            } else if i < a.count, j < b.count {
                out.append(.same(b[j]))
                i += 1
                j += 1
            } else {
                break // unreachable: the difference accounts for every line left on either side
            }
        }
        return out
    }
}
