import Foundation

/// "Allow, and read pages it links to without asking" (D119, SECURITY T42): research without a card for every page.
///
/// Reading isn't harmless: an address can carry what the model knows to whoever runs the server, so a model steered by
/// a hostile page could put the person's notes in a link it fetches. So this never covers an address the model wrote.
/// It covers only **links on a page read since the person's yes, byte for byte**. That doesn't end every leak: a page can
/// steer which link is followed, a few bits a time. So a yes is worth a few pages, within the hour, in one conversation,
/// and ends at once when anything but reading pages comes back, when the model starts holding more worth leaving with.
public actor ResearchMode {
    public static let longest: TimeInterval = 3600
    /// Reads a yes covers: at about six bits a link, enough for a few pages and no more than some characters of anything.
    public static let budget = 12
    /// What leaves nothing new of the person's in the model's hands. Everything else that returns ends it, whatever it
    /// is: a tool that reads something personal needn't say so, and an extension's rarely can.
    static let harmless: Set<String> = ["web.fetch", "status", "sidefolk.about", "sidefolk.updates", "mac.software_updates", "sidefolk.open", "sidefolk.look"]

    private struct Grant {
        var until: Date
        var left: Int
    }

    private var threads: [String: String] = [:]
    private var grants: [String: Grant] = [:]
    private var links: [String: Set<String>] = [:]
    private var closed: Set<String> = []
    /// Conversations seen since launch; nothing else says what an older one read.
    private var seen: Set<String> = []

    public init() {}

    /// A run starts. `continuing`: the conversation has earlier turns, whose reads this may not know of if they were
    /// before a restart, and which a reply or attachment may quote.
    public func begin(run: String, thread: String, continuing: Bool) {
        threads[run] = thread
        if seen.insert(thread).inserted, continuing { closed.insert(thread) }
    }

    public func end(run: String) { threads[run] = nil }

    /// Whether a yes to reading on is still holding for some conversation (Trust › Allowed for now).
    func isGranted(now: Date) -> Bool {
        grants.contains { thread, grant in now < grant.until && grant.left > 0 && !closed.contains(thread) }
    }

    /// Takes every yes back: the next page asks again.
    func revokeAll() { grants = [:] }

    /// Forgets a conversation that was deleted.
    public func forget(thread: String) {
        grants[thread] = nil
        links[thread] = nil
        closed.remove(thread)
    }

    /// Whether a card may offer it: not once something else was read here, and not for an address with a query, where a
    /// model's writing has the most room.
    func canOffer(run: String, for address: String) -> Bool {
        guard let thread = threads[run], !closed.contains(thread) else { return false }
        return !Self.key(address).contains("?")
    }

    func grant(run: String, now: Date) {
        guard let thread = threads[run], !closed.contains(thread) else { return }
        grants[thread] = Grant(until: now.addingTimeInterval(Self.longest), left: Self.budget)
    }

    private func active(_ thread: String, now: Date) -> Bool {
        guard let grant = grants[thread], now < grant.until, !closed.contains(thread) else { return false }
        return grant.left > 0
    }

    /// Spends one read, if this address is one the person's yes covers. Compared as written: decoding either side would
    /// let `%61` and `a` pass as one and carry a message in the spelling.
    func take(_ address: String, run: String, now: Date) -> Bool {
        guard let thread = threads[run], active(thread, now: now), links[thread]?.contains(Self.key(address)) == true else { return false }
        grants[thread]?.left -= 1
        return true
    }

    /// What a page read under a yes links to, of `found`: what may now be read, for the model to see. A link off to
    /// another site that repeats words from the address just fetched may be the server echoing what the model wrote
    /// there, so it isn't counted.
    func note(links found: [String], from address: String, run: String, now: Date) -> [String] {
        guard let thread = threads[run], let grant = grants[thread], now < grant.until, !closed.contains(thread) else { return [] }
        let source = URL(string: address)
        let words = Set((source.map { "\($0.path) \($0.query ?? "")" } ?? "").lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 4 })
        let kept = found.filter { link in
            guard let url = URL(string: link), url.host?.lowercased() != source?.host?.lowercased() else { return true }
            let plain = (url.absoluteString.removingPercentEncoding ?? url.absoluteString).lowercased()
            return !words.contains { plain.contains($0) }
        }
        links[thread, default: []].formUnion(kept.map(Self.key))
        return kept
    }

    /// A tool came back. Anything that isn't known to leave nothing personal ends it for this conversation.
    func toolReturned(_ tool: String, run: String) {
        guard !Self.harmless.contains(tool), let thread = threads[run] else { return }
        closed.insert(thread)
        grants[thread] = nil
    }

    /// An address as written, without its fragment, which never leaves the Mac.
    static func key(_ address: String) -> String {
        address.firstIndex(of: "#").map { String(address[..<$0]) } ?? address
    }
}
