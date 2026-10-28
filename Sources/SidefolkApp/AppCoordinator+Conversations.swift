import SidefolkCore

/// Home › Conversations (D45): continuing a conversation however long ago it was, and forgetting one or all.
extension AppCoordinator {
    func continueConversation(_ thread: String, text: String) async -> AgentRunHandle? {
        guard runtime.settings.current.provider.kind != .none else { return nil }
        // It becomes the current conversation, for the Ask panel too (its own answers keep theirs for Reply).
        ask.thread = thread
        return await agent.submit(AgentRequest(text: text, threadId: thread))
    }

    func stopConversation(run runId: String) async {
        await agent.cancel(runId: runId)
    }

    func deleteConversation(_ thread: String) async -> UserFacingError? {
        do {
            try await agent.deleteConversation(thread)
            forgetInPanel { $0 == thread }
            Log.shared.info("brain", "conversation deleted")
            return nil
        } catch {
            return UserFacingError("I couldn't delete that conversation.", detail: String(describing: error))
        }
    }

    func deleteAllConversations() async -> UserFacingError? {
        do {
            try await agent.deleteAllConversations()
            forgetInPanel { _ in true }
            Log.shared.info("brain", "all conversations deleted")
            return nil
        } catch {
            return UserFacingError("I couldn't delete the conversation history.", detail: String(describing: error))
        }
    }

    /// Answers still in the Ask panel from a forgotten conversation go too: what was deleted isn't left on screen.
    private func forgetInPanel(_ gone: (String) -> Bool) {
        let ids = Set(ask.entries.compactMap { entry -> AskEntry.ID? in
            if case .answer(_, _, _, let thread?) = entry.content, gone(thread) { return entry.id }
            return nil
        })
        for request in ask.requests where request.entries.contains(where: { ids.contains($0.id) }) { ask.remove(request) }
        if ask.thread.map(gone) == true { ask.thread = nil }
    }
}
