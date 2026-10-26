#!/usr/bin/env swift
// Generates labeled review sheets from individual companion concept PNGs; no model calls.
import AppKit
import ImageIO
import CoreImage
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("folk-family")
let data = try Data(contentsOf: root.appendingPathComponent("prompts.json"))
let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
let entries = json["concepts"] as! [[String: Any]]
let prepareOnly = CommandLine.arguments.contains("--prepare-only")
struct Concept {
    let slug: String, name: String, detail: String
    let image: CGImage
}
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
var concepts:[Concept]=[]
for entry in entries {
    let id=entry["id"] as! String, name=entry["name"] as! String, detail=entry["description"] as! String
    let slug=String(id.dropFirst(3)), folder=root.appendingPathComponent(slug)
    let source=folder.appendingPathComponent("source.png")
    guard FileManager.default.fileExists(atPath:source.path) else {
        if prepareOnly { continue }
        fatalError("Missing \(source.path)")
    }
    let image=cleaned(read(source))
    save(image,folder.appendingPathComponent(slug+".png"))
    let metadata:[String:Any] = ["name":name,"description":detail,"image":slug+".png",
                                "source":"source.png","width":image.width,"height":image.height,
                                "status":"static companion concept"]
    try JSONSerialization.data(withJSONObject:metadata,options:[.prettyPrinted,.sortedKeys])
        .write(to:folder.appendingPathComponent("character.json"))
    concepts.append(Concept(slug:slug,name:name,detail:detail,image:image))
}
if prepareOnly { print("Prepared \(concepts.count) available concept PNGs"); exit(0) }
let navy=NSColor(srgbRed:15/255,green:45/255,blue:91/255,alpha:1)
let secondary=NSColor(srgbRed:94/255,green:115/255,blue:144/255,alpha:1)
func label(_ text:String,_ rect:CGRect,_ size:CGFloat,_ weight:NSFont.Weight,_ color:NSColor=navy) {
    let paragraph=NSMutableParagraphStyle(); paragraph.alignment = .center
    (text as NSString).draw(in:rect,withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:color,.paragraphStyle:paragraph])
}
func visibleBounds(_ im:CGImage)->CGRect {
    let w=im.width,h=im.height,c=bitmap(w,h)
    c.draw(im,in:CGRect(x:0,y:0,width:w,height:h))
    let p=c.data!.assumingMemoryBound(to:UInt8.self)
    var left=w,right=0,top=h,bottom=0
    for y in 0..<h {for x in 0..<w where p[(y*w+x)*4+3]>32 {left=min(left,x);right=max(right,x);top=min(top,y);bottom=max(bottom,y)}}
    return CGRect(x:left,y:top,width:right-left+1,height:bottom-top+1)
}
let framed=concepts.map{ $0.image.cropping(to:visibleBounds($0.image))! }
func drawCard(_ index:Int,_ rect:CGRect,_ context:CGContext,_ large:Bool) {
    NSColor.white.setFill();NSBezierPath(roundedRect:rect,xRadius:24,yRadius:24).fill()
    let art=framed[index], available=CGRect(x:rect.minX+28,y:rect.minY+106,width:rect.width-56,height:rect.height-138)
    let fit=min(available.width/CGFloat(art.width),available.height/CGFloat(art.height))
    let box=CGRect(x:available.midX-CGFloat(art.width)*fit/2,y:available.minY,width:CGFloat(art.width)*fit,height:CGFloat(art.height)*fit)
    context.interpolationQuality = .high;context.draw(art,in:box)
    label(String(format:"%02d  %@",index+1,concepts[index].name),CGRect(x:rect.minX+8,y:rect.minY+55,width:rect.width-16,height:38),large ? 30:26,.bold)
    label(concepts[index].detail,CGRect(x:rect.minX+8,y:rect.minY+20,width:rect.width-16,height:28),large ? 20:18,.regular,secondary)
}
func sheet(_ filename:String,_ indices:[Int],columns:Int,title:String,subtitle:String,cell:CGSize) {
    let rows=(indices.count+columns-1)/columns,margin:CGFloat=32,gap:CGFloat=24,header:CGFloat=140
    let width=Int(margin*2+CGFloat(columns)*cell.width+CGFloat(columns-1)*gap)
    let height=Int(margin*2+CGFloat(rows)*cell.height+CGFloat(rows-1)*gap+header)
    let c=bitmap(width,height)
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:c,flipped:false)
    NSColor(srgbRed:0.946,green:0.961,blue:0.979,alpha:1).setFill();CGRect(x:0,y:0,width:width,height:height).fill()
    label(title,CGRect(x:20,y:CGFloat(height)-72,width:CGFloat(width)-40,height:48),38,.bold)
    label(subtitle,CGRect(x:20,y:CGFloat(height)-112,width:CGFloat(width)-40,height:30),21,.regular,secondary)
    for (n,index) in indices.enumerated() {
        let x=margin+CGFloat(n%columns)*(cell.width+gap)
        let y=CGFloat(height)-header-margin-CGFloat(n/columns+1)*cell.height-CGFloat(n/columns)*gap
        drawCard(index,CGRect(x:x,y:y,width:cell.width,height:cell.height),c,columns<=3)
    }
    NSGraphicsContext.restoreGraphicsState()
    save(c.makeImage()!,root.appendingPathComponent(filename))
}
func completeFamilySheet() {
    let width=2400, height=2300, c=bitmap(width,height)
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:c,flipped:false)
    NSColor(srgbRed:0.946,green:0.961,blue:0.979,alpha:1).setFill()
    CGRect(x:0,y:0,width:width,height:height).fill()
    label("Sidefolk · Choose your companion",CGRect(x:32,y:2220,width:2336,height:55),44,.bold)
    label("The main companion, two legacy redesigns, and the ten Folks",CGRect(x:32,y:2174,width:2336,height:36),25,.regular,secondary)
    for index in 0..<3 {drawCard(index,CGRect(x:36+CGFloat(index)*784,y:1340,width:760,height:800),c,true)}
    label("The Folk Family",CGRect(x:32,y:1260,width:2336,height:50),34,.bold)
    for offset in 0..<10 {
        let x=36+CGFloat(offset%5)*470.4, y=offset<5 ? 700.0 : 136.0
        drawCard(offset+3,CGRect(x:x,y:y,width:446.4,height:540),c,false)
    }
    label("Character concepts · individual transparent PNGs are in each named folder",CGRect(x:32,y:56,width:2336,height:36),23,.regular,secondary)
    NSGraphicsContext.restoreGraphicsState()
    save(c.makeImage()!,root.appendingPathComponent("character-sheet.png"))
}
completeFamilySheet()
sheet("main-companions.png",[0,1,2],columns:3,title:"Main companion directions",subtitle:"01 Sidefolk · 02 Mochi · 03 Spark",cell:CGSize(width:600,height:760))
sheet("folk-family-sheet.png",Array(3..<concepts.count),columns:5,title:"The Folk Family",subtitle:"Faithful character studies based on the supplied identity sheet",cell:CGSize(width:440,height:540))
print("Saved 13 named transparent PNGs and three labeled character sheets to \(root.path)")
