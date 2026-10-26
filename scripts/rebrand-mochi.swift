#!/usr/bin/env swift
// Consistent palette grading of the existing 16 poses preserves identity and animation scale.
// Never grade an already graded image: retain the original source pose set for reproducibility.
import AppKit
import ImageIO
let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
let folder=root.appendingPathComponent("Resources/Companions/mochi")
let sources=root.appendingPathComponent("Resources/Companions/masters/mochi-legacy")
let fm=FileManager.default
try fm.createDirectory(at:sources,withIntermediateDirectories:true)
let poses=["idle","blink","listen","think","work1","work2","write1","write2","note","alert","sad","done","wave","sit","sleep","dangle"]
for pose in poses {
    let file=folder.appendingPathComponent(pose+".png"), source=sources.appendingPathComponent(pose+".png")
    if !fm.fileExists(atPath:source.path) {try fm.copyItem(at:file,to:source)}
    let input=CGImageSourceCreateWithURL(source as CFURL,nil)!
    let image=CGImageSourceCreateImageAtIndex(input,0,nil)!
    let w=image.width,h=image.height
    let c=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,
                    space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.draw(image,in:CGRect(x:0,y:0,width:w,height:h))
    let p=c.data!.assumingMemoryBound(to:UInt8.self)
    for i in 0..<(w*h) {
        let at=i*4, alpha=Double(p[at+3])/255
        guard alpha>0 else {continue}
        let r=Double(p[at])/255/alpha,g=Double(p[at+1])/255/alpha,b=Double(p[at+2])/255/alpha
        let maximum=max(r,max(g,b)),minimum=min(r,min(g,b))
        let saturation=maximum>0 ? (maximum-minimum)/maximum : 0
        var color=(r,g,b)
        if maximum<0.4 && saturation<0.3 {
            // Black ear tips, eyes and nose become shaded navy; keep the existing highlights.
            color=(r*0.35,g*0.7,min(1,b*1.35+0.06))
        } else if g>r*1.15 && g>b*0.95 && saturation>0.15 && r<0.85 {
            // Existing mint scarf to the guide's cooler mint/aqua, retaining its sculpted shading.
            color=(r*0.75,min(1,g*1.08),min(1,b*1.18))
        } else if r>0.3 && r>=g*0.98 && g>=b*0.98 && saturation<0.38 {
            // Neutralize cream rather than tinting the whole image, which would change props.
            color=(min(1,r*1.02),min(1,g*1.09),min(1,b*1.23))
        }
        for (j,value) in [color.0,color.1,color.2].enumerated() {p[at+j]=UInt8((max(0,min(1,value))*alpha*255).rounded())}
    }
    let dest=CGImageDestinationCreateWithURL(file as CFURL,"public.png" as CFString,1,nil)!
    CGImageDestinationAddImage(dest,c.makeImage()!,nil);precondition(CGImageDestinationFinalize(dest))
}
print("Rebranded all 16 Mochi poses; original robot and Spark artwork are unchanged.")
