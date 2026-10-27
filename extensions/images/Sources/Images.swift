import Foundation
import ImageIO
import SidefolkExtensionKit
import UniformTypeIdentifiers

/// Photos and pictures with ImageIO: what one is, and copies of many converted, made smaller or without their
/// location. Originals are never changed; copies go into a "Converted" folder beside them.
enum Images {
    static let readable: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp", "avif"]
    static let formats: [String: (type: UTType, ext: String, name: String)] = [
        "jpeg": (.jpeg, "jpg", "JPEG"), "png": (.png, "png", "PNG"), "heic": (.heic, "heic", "HEIC"), "tiff": (.tiff, "tiff", "TIFF"),
    ]

    static func info(_ raw: String) throws -> String {
        let path = try Paths.full(raw)
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw Problem("\(Paths.show(path)) isn't a picture I can read.")
        }
        let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0, height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        // Rotated by its orientation, as it looks.
        let (w, h) = orientation >= 5 ? (height, width) : (width, height)
        let type = (CGImageSourceGetType(source) as String?).flatMap { UTType($0)?.preferredFilenameExtension?.uppercased() } ?? "image"
        let bytes = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        var parts = ["\((path as NSString).lastPathComponent): \(w) × \(h) px (\(String(format: "%.1f", Double(w * h) / 1e6)) megapixels)",
                     type, ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        if let taken = exif[kCGImagePropertyExifDateTimeOriginal] as? String { parts.append("taken \(shown(taken))") }
        if let model = tiff[kCGImagePropertyTIFFModel] as? String { parts.append("with \(model)") }
        if CGImageSourceGetCount(source) > 1 { parts.append("\(CGImageSourceGetCount(source)) frames") }
        parts.append(props[kCGImagePropertyGPSDictionary] != nil ? "it records where it was taken (location)" : "no location in it")
        return parts.joined(separator: ", ") + "."
    }

    /// EXIF's "2026:05:12 14:03:22" as "2026-05-12 14:03".
    static func shown(_ exif: String) -> String {
        let parts = exif.split(separator: " ")
        guard parts.count == 2 else { return exif }
        return parts[0].replacingOccurrences(of: ":", with: "-") + " " + parts[1].prefix(5)
    }

    static func convert(folder raw: String, files: [String], format: String, maxSize: Int?, quality: Int, removeLocation: Bool) throws -> String {
        let folder = try Paths.full(raw)
        guard Paths.exists(folder, folder: true) else { throw Problem("\(Paths.show(folder)) isn't a folder.") }
        let names = files.isEmpty
            ? ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).filter { readable.contains(($0 as NSString).pathExtension.lowercased()) }.sorted()
            : files
        guard !names.isEmpty else { throw Problem("There are no pictures in \(Paths.show(folder)).") }
        guard names.count <= 200 else { throw Problem("That's \(names.count) pictures; do at most 200 at a time.") }
        let output = folder + "/Converted"
        try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
        var done = 0, before = 0, after = 0, problems: [String] = []
        for name in names {
            guard !name.contains("/"), let target = formats[format == "same" ? kind(of: name) : format] else {
                problems.append("\(name): not a file in that folder")
                continue
            }
            let source = folder + "/" + name
            do {
                let destination = Paths.free(output + "/" + ((name as NSString).deletingPathExtension as NSString).appendingPathExtension(target.ext)!)
                try write(source, to: destination, as: target.type, maxSize: maxSize, quality: quality, removeLocation: removeLocation)
                before += size(source)
                after += size(destination)
                done += 1
            } catch let problem as Problem {
                problems.append("\(name): \(problem.message)")
            }
        }
        guard done > 0 else { throw Problem("Nothing was converted. " + problems.prefix(5).joined(separator: "; ")) }
        let format = formats[format]?.name ?? "their own format"
        var what = [format]
        if let maxSize { what.append("at most \(maxSize) px") }
        if removeLocation { what.append("location removed") }
        let sizes = "\(ByteCountFormatter.string(fromByteCount: Int64(before), countStyle: .file)) → \(ByteCountFormatter.string(fromByteCount: Int64(after), countStyle: .file))"
        return "Made \(done) cop\(done == 1 ? "y" : "ies") in \(Paths.show(output)) (\(what.joined(separator: ", "))): \(sizes)."
            + (problems.isEmpty ? "" : " Skipped \(problems.count): " + problems.prefix(5).joined(separator: "; ") + ".")
    }

    static func kind(of name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "png": "png"
        case "heic", "heif": "heic"
        case "tif", "tiff": "tiff"
        default: "jpeg"
        }
    }

    static func size(_ path: String) -> Int { (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0 }

    static func write(_ path: String, to destination: String, as type: UTType, maxSize: Int?, quality: Int, removeLocation: Bool) throws {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            throw Problem("not a picture I can read")
        }
        var props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let image: CGImage?
        if let maxSize {
            // Made smaller with its orientation applied, so it no longer needs one.
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                    kCGImageSourceThumbnailMaxPixelSize: maxSize,
                                                                    kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
            props[kCGImagePropertyOrientation] = 1
            if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                tiff[kCGImagePropertyTIFFOrientation] = 1
                props[kCGImagePropertyTIFFDictionary] = tiff
            }
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard let image else { throw Problem("it couldn't be decoded") }
        if removeLocation { props.removeValue(forKey: kCGImagePropertyGPSDictionary) }
        props.removeValue(forKey: kCGImagePropertyPixelWidth)
        props.removeValue(forKey: kCGImagePropertyPixelHeight)
        props[kCGImageDestinationLossyCompressionQuality] = Double(quality) / 100
        guard let out = CGImageDestinationCreateWithURL(URL(fileURLWithPath: destination) as CFURL, type.identifier as CFString, 1, nil) else {
            throw Problem("that format can't be written")
        }
        CGImageDestinationAddImage(out, image, props as CFDictionary)
        guard CGImageDestinationFinalize(out) else {
            try? FileManager.default.removeItem(atPath: destination)
            throw Problem("it couldn't be written")
        }
    }
}
