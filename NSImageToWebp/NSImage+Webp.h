//
//  NSImage+Webp.h
//  NSImageToWebp
//
//  Created by great Lock on 2018/6/10.
//  Copyright © 2018年 great Lock. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface NSImage (Webp)
- (NSData *)toWebpImageDataWithLossLess:(BOOL)lossLess quality:(CGFloat)quality;
@end

@interface NSData (Webp)
- (NSData *)toWebpImageDataWithLossLess:(BOOL)lossLess quality:(CGFloat)quality;
@end
