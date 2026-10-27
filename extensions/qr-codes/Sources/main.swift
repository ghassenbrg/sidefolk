import CoreImage
import Foundation
import ImageIO
import SidefolkExtensionKit
import UniformTypeIdentifiers

// QR Codes, an extension that ships with Sidefolk: one file or folder per call, and the Mac's graphics hardware.
let ext = Extension(name: "qr-codes")
let context = CIContext(options: [.useSoftwareRenderer: true])

ext.tool("make_qr", "Make a QR code",
         "Makes a QR code picture (PNG) of a link or text, like a Wi-Fi network or a web address, in a folder.",
         input: Schema.object([
             "text": Schema.string("What the code holds: a link or text.", maxLength: 1500),
             "folder": Schema.path("Where to save it, a full path like ~/Desktop."),
             "name": Schema.string("The picture's name (QR code if not given).", maxLength: 120),
         ], required: ["text", "folder"])) { args in
    let text = try args.required("text"), folder = try Paths.full(try args.required("folder"))
    guard let filter = CIFilter(name: "CIQRCodeGenerator") else { throw Problem("This Mac can't make QR codes.") }
    filter.setValue(Data(text.utf8), forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    // Each module 12 pixels square, sharp edges, white around it.
    guard let code = filter.outputImage?.samplingNearest().transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
          let image = context.createCGImage(code.cropped(to: code.extent.insetBy(dx: -48, dy: -48))
              .composited(over: CIImage(color: .white).cropped(to: code.extent.insetBy(dx: -48, dy: -48))), from: code.extent.insetBy(dx: -48, dy: -48))
    else { throw Problem("The QR code couldn't be drawn.") }
    let stem = (args.string("name") ?? "QR code").replacingOccurrences(of: "/", with: "-")
    let path = Paths.free(folder + "/" + (stem.lowercased().hasSuffix(".png") ? stem : stem + ".png"))
    guard let out = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw Problem("\(Paths.show(folder)) can't be written to.")
    }
    CGImageDestinationAddImage(out, image, nil)
    guard CGImageDestinationFinalize(out) else { throw Problem("The picture couldn't be saved.") }
    return "Saved a QR code for “\(text.prefix(80))” as \(Paths.show(path)) (\(image.width) × \(image.height) px)."
}

ext.tool("read_qr", "Read a QR code", "Reads the QR codes in a picture, like a screenshot or a photo of one, and says what they hold.",
         input: Schema.object(["path": Schema.path("The picture, a full path like ~/Desktop/Screenshot.png.")], required: ["path"])) { args in
    let path = try Paths.full(try args.required("path"))
    guard let image = CIImage(contentsOf: URL(fileURLWithPath: path)) else { throw Problem("\(Paths.show(path)) isn't a picture I can read.") }
    let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: context, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
    let found = (detector?.features(in: image) ?? []).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
    guard !found.isEmpty else { throw Problem("I didn't find a QR code in \(Paths.show(path)).") }
    return found.count == 1 ? "The QR code holds: \(found[0])" : "The QR codes hold:\n" + found.map { "- \($0)" }.joined(separator: "\n")
}

await ext.serve()
