import Foundation

/// The tools Sidefolk ships with: notebook, About you, clipboard, opening things, files and web.
/// Reminders and watchers are registered separately by their own modules.
///
/// Every tool runs through `ToolExecutor`, so Guard sees each call first. Register the result with
/// `ToolRegistry.register(_:)`.
public enum BuiltinTools {
    public static func make(
        notebook: NotebookStore, platform: any PlatformBridge, events: EventBus,
        fetcher: any WebFetching = URLSessionFetcher()
    ) -> [any Tool] {
        [
            // Notebook
            NotesSaveTool(notebook: notebook, events: events),
            NotesSearchTool(notebook: notebook),
            NotesListTool(notebook: notebook),
            NotesUpdateTool(notebook: notebook, events: events),
            NotesTrashTool(notebook: notebook, events: events),
            CollectionsListTool(notebook: notebook),
            CollectionsCreateTool(notebook: notebook, events: events),
            // About you
            ProfileRememberTool(notebook: notebook, events: events),
            ProfileListTool(notebook: notebook),
            ProfileForgetTool(notebook: notebook, events: events),
            // Clipboard
            ClipboardReadTool(platform: platform),
            ClipboardWriteTool(platform: platform),
            // Opening things
            OpenURLTool(platform: platform),
            OpenEmailTool(platform: platform),
            OpenAppTool(platform: platform),
            FilesRevealTool(platform: platform),
            // Files
            FilesListTool(),
            FilesReadTool(),
            FilesSearchTool(),
            FilesMoveTool(),
            FilesRenameTool(),
            FilesMkdirTool(),
            FilesTrashTool(),
            // Web
            WebFetchTool(fetcher: fetcher),
        ]
    }
}
