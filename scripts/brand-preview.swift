import AppKit
import ImageIO
let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
let w=1440,h=1100
let c=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:c,flipped:false)
func rect(_ x:Double,_ y:Double,_ w:Double,_ h:Double)->CGRect{CGRect(x:x,y:y,width:w,height:h)}
func fill(_ color:NSColor,_ r:CGRect){color.setFill();r.fill()}
func label(_ text:String,_ x:Double,_ y:Double,_ color:NSColor = .darkGray){(text as NSString).draw(at:NSPoint(x:x,y:y),withAttributes:[.font:NSFont.systemFont(ofSize:17,weight:.medium),.foregroundColor:color])}
func art(_ path:String,_ box:CGRect){let im=NSImage(contentsOf:root.appendingPathComponent(path))!;let f=min(box.width/im.size.width,box.height/im.size.height);im.draw(in:rect(box.midX-im.size.width*f/2,box.midY-im.size.height*f/2,im.size.width*f,im.size.height*f))}
fill(NSColor(white:0.95,alpha:1),rect(0,0,1440,1100))
label("Sidefolk · production assets from the supplied reference",35,1060)
art("Resources/Icon/icon-source-2048.png",rect(25,665,390,390));label("Raw square icon source · flat, no tile effects",35,640)
fill(.white,rect(440,655,955,385));art("Resources/Brand/exports/logo-stacked-color.png",rect(465,675,425,350));art("Resources/Brand/exports/logo-horizontal-color.png",rect(910,735,455,230));label("Flat reference lettering · transparent PNG / vector wordmark",465,620)
fill(.white,rect(35,340,665,250));art("Resources/Brand/exports/logo-horizontal-navy.png",rect(65,380,605,170));label("Navy on light",55,350)
fill(NSColor(srgbRed:15/255,green:45/255,blue:91/255,alpha:1),rect(725,340,670,250));art("Resources/Brand/exports/logo-horizontal-white.png",rect(750,380,620,170));label("White on dark",745,350,.white)
label("Menu bar · actual 18 pt template, rendered from the bundled vector PDF",35,292)
let menu=NSImage(contentsOf:root.appendingPathComponent("Resources/MenuBar/SidefolkMenuBar.pdf"))!
menu.size=NSSize(width:18,height:18);menu.isTemplate=true
for (x,bg,fg) in [(35.0,NSColor.white,NSColor.black),(725.0,NSColor(white:0.14,alpha:1),NSColor.white)] {
 fill(bg,rect(x,165,670,95))
 // Mimic template tinting with the exact native PDF alpha mask, independent of system appearance.
 let tc=CGContext(data:nil,width:36,height:36,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
 NSGraphicsContext.current=NSGraphicsContext(cgContext:tc,flipped:false)
 menu.draw(in:rect(0,0,36,36));tc.setBlendMode(.sourceIn);tc.setFillColor(fg.cgColor);tc.fill(rect(0,0,36,36))
 NSGraphicsContext.current=NSGraphicsContext(cgContext:c,flipped:false)
 let im=NSImage(cgImage:tc.makeImage()!,size:NSSize(width:18,height:18))
 im.draw(in:rect(x+30,203,18,18));label("Sidefolk",x+64,199,fg)
 im.draw(in:rect(x+370,176,72,72));label("4× detail",x+475,199,fg)
}
label("App icon at 16 · 32 · 64 · 128 px",35,119)
for (i,size) in [16,32,64,128].enumerated(){art("Resources/Icon/icon-macos-1024.png",rect(375+Double(i)*145,0,Double(size),Double(size)))}
NSGraphicsContext.restoreGraphicsState()
let dest=root.appendingPathComponent("Resources/Brand/preview.png")
let d=CGImageDestinationCreateWithURL(dest as CFURL,"public.png" as CFString,1,nil)!
CGImageDestinationAddImage(d,c.makeImage()!,nil);precondition(CGImageDestinationFinalize(d))
