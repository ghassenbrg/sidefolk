import Foundation
import SidefolkExtensionKit

// Archives, an extension that ships with Sidefolk: one folder per call, and macOS's own zip (to make one) and ditto
// (to open one, the way Finder does).
let ext = Extension(name: "archives")
let zipProgram = "/usr/bin/zip", ditto = "/usr/bin/ditto"

func size(_ path: String) -> String {
    ByteCountFormatter.string(fromByteCount: Int64((try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0), countStyle: .file)
}

func plain(_ name: String, in folder: String) throws -> String {
    guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else {
        throw Problem("“\(name)” should be just a name of something in \(Paths.show(folder)).")
    }
    guard Paths.exists(folder + "/" + name) else { throw Problem("There's no “\(name)” in \(Paths.show(folder)).") }
    return folder + "/" + name
}

ext.tool("zip", "Make a zip file",
         "Puts files or folders from one folder into a new zip file in that folder, ready to send, the way Finder's Compress does.",
         input: Schema.object([
             "folder": Schema.path("The folder they are in, a full path like ~/Documents."),
             "items": Schema.array(of: Schema.string("A file or folder name in that folder.", maxLength: 255), "What to put in the zip.", maxItems: 100),
             "name": Schema.string("The zip file's name (the item's name, or Archive, if not given).", maxLength: 120),
         ], required: ["folder", "items"])) { args in
    let folder = try Paths.full(try args.required("folder"))
    let items = try args.strings("items").map { try plain($0, in: folder) }
    guard !items.isEmpty else { throw Problem("Name at least one file or folder to zip.") }
    let stem = (args.string("name") ?? (items.count == 1 ? (items[0] as NSString).lastPathComponent : "Archive")).replacingOccurrences(of: "/", with: "-")
    let zip = Paths.free(folder + "/" + (stem.lowercased().hasSuffix(".zip") ? stem : stem + ".zip"))
    // Names relative to the folder, so the zip holds them as they appear there; links stay links (-y).
    let names = items.map { ($0 as NSString).lastPathComponent }
    let result = try run(zipProgram, ["-r", "-q", "-y", "-X", zip, "--"] + names, in: folder, timeout: 280)
    guard result.status == 0 else {
        try? FileManager.default.removeItem(atPath: zip)
        throw Problem("The zip couldn't be made: \((result.err + result.out).trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))")
    }
    return "Made \(Paths.show(zip)) (\(size(zip))) with \(items.count == 1 ? (items[0] as NSString).lastPathComponent : "\(items.count) items")."
}

ext.tool("unzip", "Open a zip file", "Unpacks a zip file into a new folder beside it, named after it.",
         input: Schema.object([
             "folder": Schema.path("The folder the zip file is in, a full path like ~/Downloads."),
             "file": Schema.string("The zip file's name in that folder.", maxLength: 255),
         ], required: ["folder", "file"])) { args in
    let folder = try Paths.full(try args.required("folder"))
    let zip = try plain(try args.required("file"), in: folder)
    let destination = Paths.free(folder + "/" + ((zip as NSString).lastPathComponent as NSString).deletingPathExtension)
    let result = try run(ditto, ["-x", "-k", zip, destination], timeout: 280)
    guard result.status == 0 else {
        try? FileManager.default.removeItem(atPath: destination)
        throw Problem("It couldn't be unpacked: \(result.err.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))")
    }
    let count = (try? FileManager.default.contentsOfDirectory(atPath: destination).count) ?? 0
    return "Unpacked \((zip as NSString).lastPathComponent) into \(Paths.show(destination)) (\(count) item\(count == 1 ? "" : "s") at the top)."
}

await ext.serve()
