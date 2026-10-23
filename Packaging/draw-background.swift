import AppKit
let width = 500, height = 620
let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width*2,pixelsHigh:height*2,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
rep.size = NSSize(width:width,height:height)
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:rep)
let ctx = NSGraphicsContext.current!.cgContext
func c(_ r:CGFloat,_ g:CGFloat,_ b:CGFloat,_ a:CGFloat=1)->NSColor {NSColor(srgbRed:r,green:g,blue:b,alpha:a)}
c(0.968,0.957,0.994).setFill();NSRect(x:0,y:0,width:width,height:height).fill()
func glow(_ x:CGFloat,_ y:CGFloat,_ radius:CGFloat,_ tint:NSColor) {
 let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[tint.cgColor,tint.withAlphaComponent(0).cgColor] as CFArray,locations:[0,1])!
 ctx.drawRadialGradient(gradient,startCenter:CGPoint(x:x,y:y),startRadius:0,endCenter:CGPoint(x:x,y:y),endRadius:radius,options:[])
}
glow(240,315,230,c(0.46,0.22,0.94,0.65));glow(310,230,165,c(0.4,0.28,0.95,0.4));glow(140,420,190,c(0.7,0.55,1,0.35))
// A restrained dot field fades into the surrounding lavender paper.
for x in stride(from:76,through:424,by:8) {
 for y in stride(from:145,through:470,by:8) {
  let d=hypot(CGFloat(x)-250,(CGFloat(y)-310)*0.85)
  let a=max(0,1-d/175)*0.27
  c(1,1,1,a).setFill();NSBezierPath(ovalIn:NSRect(x:CGFloat(x),y:CGFloat(y),width:1.3,height:1.3)).fill()
 }
}
func text(_ s:String,_ y:CGFloat,_ size:CGFloat,_ color:NSColor,_ weight:NSFont.Weight = .regular) {
 let a:[NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:color]
 let w=(s as NSString).size(withAttributes:a).width
 (s as NSString).draw(at:NSPoint(x:(500-w)/2,y:y),withAttributes:a)
}
text("H I D E C E L L",560,10,c(0.45,0.36,0.61),.semibold)
text("A quieter Mac starts here.",528,22,c(0.19,0.12,0.3),.medium)
// The real icons are centered at Finder coordinates (250,175) and (250,420).
// A curved gesture trail leads downward, without crossing either icon or label.
let path=NSBezierPath();path.move(to:NSPoint(x:320,y:412));path.curve(to:NSPoint(x:326,y:218),controlPoint1:NSPoint(x:410,y:345),controlPoint2:NSPoint(x:400,y:275))
c(0.41,0.23,0.73,0.24).setStroke();path.lineWidth=1.5;path.setLineDash([2,7],count:2,phase:0);path.stroke()
for (x,y,a,angle):(CGFloat,CGFloat,CGFloat,CGFloat) in [(337,389,0.20,-12),(365,327,0.4,-5),(352,256,0.82,12)] {
 NSGraphicsContext.saveGraphicsState();ctx.translateBy(x:x,y:y)
 ctx.rotate(by:angle * .pi / 180)
 if let hand=NSImage(systemSymbolName:"hand.point.up.left.fill",accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:27,weight:.regular)) {
  let tinted=NSImage(size:hand.size);tinted.lockFocus();hand.draw(at:.zero,from:.zero,operation:.sourceOver,fraction:1);c(0.25,0.12,0.43).setFill();NSRect(origin:.zero,size:hand.size).fill(using:.sourceAtop);tinted.unlockFocus()
  tinted.draw(at:NSPoint(x:-14,y:-14),from:.zero,operation:.sourceOver,fraction:a)
 }
 NSGraphicsContext.restoreGraphicsState()
}
text("Drag Hidecell into Applications",72,15,c(0.28,0.15,0.48),.medium)
text("Then open it from your Applications folder.",49,11,c(0.48,0.43,0.57))
text("YOUR MENU BAR. ROOM TO BREATHE.",18,8,c(0.58,0.53,0.65),.medium)
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
