import Foundation
import SidefolkCore

/// What Settings › Trust › Your data says about the last restore (D91): its add-ons coming back, what failed, what waits
/// for a look, and until when Undo restore is offered. The coordinator keeps it.
@MainActor @Observable
final class RestoreModel {
    /// The latest restore that can still be undone.
    var undoable: BackupRestore.Plan?
    /// Add-ons being installed again after the relaunch: how many are done of how many.
    var running = false
    var done = 0
    var total = 0
    /// What the follow-up did, once it's done.
    var report: RestoreFollowUp.Report?
    /// Extensions and companions from a folder, waiting for the person's look.
    var review: [RestoreFollowUp.ReviewItem] = []

    /// Undo restore is offered until this day.
    var undoUntil: Date? { undoable?.restoredAt?.addingTimeInterval(BackupRestore.keepUndo) }

    var isEmpty: Bool { undoable == nil && !running && report == nil && review.isEmpty }
}

/// A backup chosen for restoring, opened and checked, waiting for the person's yes in the restore sheet.
struct RestoreCandidate: Identifiable {
    let id = UUID()
    let backup: OpenedBackup
    let file: URL
}
