#import <AppKit/AppKit.h>
int main(int argc, const char **argv) { @autoreleasepool {
    NSString *folder = [NSString stringWithUTF8String:argv[1]];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    for (NSNumber *size in @[@16,@32,@128,@256,@512]) {
        for (NSNumber *scale in @[@1,@2]) {
            NSInteger side = size.integerValue * scale.integerValue;
            NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:side pixelsHigh:side bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
            [NSGraphicsContext saveGraphicsState];
            [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
            CGFloat k = side / 1024.0;
            NSAffineTransform *t = [NSAffineTransform transform]; [t scaleBy:k]; [t concat];
            [[NSColor colorWithCalibratedRed:0.12 green:0.14 blue:0.18 alpha:1] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(50,50,924,924) xRadius:210 yRadius:210] fill];
            [[NSColor colorWithCalibratedRed:0.81 green:0.91 blue:0.88 alpha:1] setFill];
            for (NSValue *rect in @[[NSValue valueWithRect:NSMakeRect(280,280,110,464)], [NSValue valueWithRect:NSMakeRect(634,280,110,464)], [NSValue valueWithRect:NSMakeRect(360,457,304,110)]]) {
                [[NSBezierPath bezierPathWithRoundedRect:rect.rectValue xRadius:36 yRadius:36] fill];
            }
            [NSGraphicsContext restoreGraphicsState];
            NSString *filename = [NSString stringWithFormat:@"icon_%@x%@%@.png",size,size,scale.intValue==2?@"@2x":@""];
            [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[folder stringByAppendingPathComponent:filename] atomically:YES];
        }
    }
} return 0; }
