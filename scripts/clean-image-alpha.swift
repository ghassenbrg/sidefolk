// Technical cleanup of an imagegen cutout; keeps RGB artwork and only fixes its extraction matte.
// swift scripts/clean-image-alpha.swift input.png output.png
import AppKit
import ImageIO
import CoreImage
func bitmap(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func read(_ url: URL) -> CGImage {
    CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL, nil)!, 0, nil)!
}
func save(_ image: CGImage, _ url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest))
}
let ci = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
// Technical matte cleanup only: preserve the artwork and RGB, remove extraction flecks and
// normalize opaque interiors. Keep the untouched generated image as source.png beside the export.
func cleaned(_ image: CGImage) -> CGImage {
    let w = image.width, h = image.height, rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    let c = bitmap(w,h), mask = bitmap(w,h)
    c.draw(image,in:rect)
    let p = c.data!.assumingMemoryBound(to: UInt8.self)
    let m = mask.data!.assumingMemoryBound(to: UInt8.self)
    for i in 0..<(w*h) {
        let at = i*4, a = Int(p[at+3])
        let level = UInt8(min(255, max(0, (a-215)*11)))
        for j in 0..<3 { m[at+j] = level }; m[at+3] = 255
    }
    let matte = CIImage(cgImage: mask.makeImage()!)
        .applyingFilter("CIMorphologyMinimum", parameters: ["inputRadius": 1.5])
        .applyingFilter("CIMorphologyMaximum", parameters: ["inputRadius": 1.5])
        .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 0.5])
        .cropped(to:rect)
    mask.clear(rect); mask.draw(ci.createCGImage(matte, from:rect)!,in:rect)
    var seen = [Bool](repeating:false,count:w*h)
    for start in 0..<(w*h) where !seen[start] && m[start*4]>20 {
        var component = [start], cursor = 0
        seen[start] = true
        while cursor<component.count {
            let at=component[cursor], x=at%w, y=at/w
            cursor += 1
            for next in [x>0 ? at-1 : -1, x<w-1 ? at+1 : -1, y>0 ? at-w : -1, y<h-1 ? at+w : -1] where next>=0 {
                if !seen[next], m[next*4]>20 {seen[next]=true;component.append(next)}
            }
        }
        if component.count<256 { for at in component {m[at*4]=0} }
    }
    for i in 0..<(w*h) {
        let at=i*4, old=Double(p[at+3])/255
        let a = m[at]<12 ? 0.0 : m[at]>245 ? 1.0 : Double(m[at])/255
        for j in 0..<3 {
            let channel=old>0 ? min(1,Double(p[at+j])/255/old) : 0
            p[at+j]=UInt8((channel*a*255).rounded())
        }
        p[at+3]=UInt8((a*255).rounded())
    }
    return c.makeImage()!
}
guard CommandLine.arguments.count == 3 else { fatalError("usage: clean-image-alpha.swift input.png output.png") }
save(cleaned(read(URL(fileURLWithPath:CommandLine.arguments[1]))),URL(fileURLWithPath:CommandLine.arguments[2]))
