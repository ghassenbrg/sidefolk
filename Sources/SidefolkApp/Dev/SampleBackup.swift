#if DEBUG
import Foundation
import SidefolkCore

/// A backup and a restore's follow-up to look at (UISnapshots, D91): what the restore sheet shows, and Your data
/// halfway through bringing the add-ons back, with one that failed and one from a folder waiting for a look.
enum SampleBackup {
    static var manifest: BackupManifest {
        var counts = BackupManifest.Counts()
        (counts.notes, counts.reminders, counts.watchers, counts.conversations, counts.addons, counts.extensions, counts.skills)
            = (1240, 32, 6, 87, 3, 3, 2)
        let created = Calendar.current.date(bySettingHour: 10, minute: 42, second: 0, of: Date().addingTimeInterval(-86_400)) ?? Date()
        return BackupManifest(app: "0.1.0 snapshot 673", version: "0.1.0-snapshot.673", created: created, device: "Ghassen's MacBook Air",
                              schema: [], counts: counts, extensions: [], addons: [], keys: true, files: [:])
    }

    static var candidate: RestoreCandidate {
        RestoreCandidate(backup: OpenedBackup(manifest: manifest, folder: FileManager.default.temporaryDirectory),
                         file: URL(fileURLWithPath: "/Users/me/Desktop/Sidefolk Backup 2026-10-31.sidefolkbackup"))
    }

    @MainActor static func show(in model: RestoreModel) {
        model.undoable = BackupRestore.Plan(backupCreated: manifest.created, app: manifest.app, device: manifest.device, extensions: [],
                                            addons: [], restoredAt: Date())
        (model.running, model.done, model.total) = (true, 2, 5)
        model.review = [RestoreFollowUp.ReviewItem(kind: .extension, id: "local.pomodoro", name: "Pomodoro Log",
                                                   folder: FileManager.default.temporaryDirectory)]
    }

    @MainActor static func clear(_ model: RestoreModel) {
        (model.undoable, model.running, model.report, model.review) = (nil, false, nil, [])
    }
}
#endif
