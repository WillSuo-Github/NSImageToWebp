//
//  NSImage+Webp.m
//  NSImageToWebp
//
//  Created by great Lock on 2018/6/10.
//  Copyright © 2018年 great Lock. All rights reserved.
//

#import "NSImage+Webp.h"
#import <webp/decode.h>
#import <webp/encode.h>
#import <webp/demux.h>
#import <webp/mux.h>
#import <Accelerate/Accelerate.h>
#import <ImageIO/ImageIO.h>

typedef NS_ENUM(NSUInteger, YYImagePreset) {
    YYImagePresetDefault = 0,  ///< default preset.
    YYImagePresetPicture,      ///< digital picture, like portrait, inner shot
    YYImagePresetPhoto,        ///< outdoor photograph, with natural lighting
    YYImagePresetDrawing,      ///< hand or line drawing, with high-contrast details
    YYImagePresetIcon,         ///< small-sized colorful images
    YYImagePresetText          ///< text-like
};

CGColorSpaceRef YYCGColorSpaceGetDeviceRGB() {
    static CGColorSpaceRef space;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        space = CGColorSpaceCreateDeviceRGB();
    });
    return space;
}


static BOOL YYCGImageDecodeToBitmapBufferWithAnyFormat(CGImageRef srcImage, vImage_Buffer *dest, vImage_CGImageFormat *destFormat) {
    if (!srcImage || (((long)vImageConvert_AnyToAny) + 1 == 1) || !destFormat || !dest) return NO;
    size_t width = CGImageGetWidth(srcImage);
    size_t height = CGImageGetHeight(srcImage);
    if (width == 0 || height == 0) return NO;
    dest->data = NULL;
    
    vImage_Error error = kvImageNoError;
    CFDataRef srcData = NULL;
    vImageConverterRef convertor = NULL;
    vImage_CGImageFormat srcFormat = {0};
    srcFormat.bitsPerComponent = (uint32_t)CGImageGetBitsPerComponent(srcImage);
    srcFormat.bitsPerPixel = (uint32_t)CGImageGetBitsPerPixel(srcImage);
    srcFormat.colorSpace = CGImageGetColorSpace(srcImage);
    srcFormat.bitmapInfo = CGImageGetBitmapInfo(srcImage) | CGImageGetAlphaInfo(srcImage);
    
    convertor = vImageConverter_CreateWithCGImageFormat(&srcFormat, destFormat, NULL, kvImageNoFlags, NULL);
    if (!convertor) goto fail;
    
    CGDataProviderRef srcProvider = CGImageGetDataProvider(srcImage);
    srcData = srcProvider ? CGDataProviderCopyData(srcProvider) : NULL; // decode
    size_t srcLength = srcData ? CFDataGetLength(srcData) : 0;
    const void *srcBytes = srcData ? CFDataGetBytePtr(srcData) : NULL;
    if (srcLength == 0 || !srcBytes) goto fail;
    
    vImage_Buffer src = {0};
    src.data = (void *)srcBytes;
    src.width = width;
    src.height = height;
    src.rowBytes = CGImageGetBytesPerRow(srcImage);
    
    error = vImageBuffer_Init(dest, height, width, 32, kvImageNoFlags);
    if (error != kvImageNoError) goto fail;
    
    error = vImageConvert_AnyToAny(convertor, &src, dest, NULL, kvImageNoFlags); // convert
    if (error != kvImageNoError) goto fail;
    
    CFRelease(convertor);
    CFRelease(srcData);
    return YES;
    
fail:
    if (convertor) CFRelease(convertor);
    if (srcData) CFRelease(srcData);
    if (dest->data) free(dest->data);
    dest->data = NULL;
    return NO;
}

static BOOL YYCGImageDecodeToBitmapBufferWith32BitFormat(CGImageRef srcImage, vImage_Buffer *dest, CGBitmapInfo bitmapInfo) {
    if (!srcImage || !dest) return NO;
    size_t width = CGImageGetWidth(srcImage);
    size_t height = CGImageGetHeight(srcImage);
    if (width == 0 || height == 0) return NO;
    
    BOOL hasAlpha = NO;
    BOOL alphaFirst = NO;
    BOOL alphaPremultiplied = NO;
    BOOL byteOrderNormal = NO;
    
    switch (bitmapInfo & kCGBitmapAlphaInfoMask) {
        case kCGImageAlphaPremultipliedLast: {
            hasAlpha = YES;
            alphaPremultiplied = YES;
        } break;
        case kCGImageAlphaPremultipliedFirst: {
            hasAlpha = YES;
            alphaPremultiplied = YES;
            alphaFirst = YES;
        } break;
        case kCGImageAlphaLast: {
            hasAlpha = YES;
        } break;
        case kCGImageAlphaFirst: {
            hasAlpha = YES;
            alphaFirst = YES;
        } break;
        case kCGImageAlphaNoneSkipLast: {
        } break;
        case kCGImageAlphaNoneSkipFirst: {
            alphaFirst = YES;
        } break;
        default: {
            return NO;
        } break;
    }
    
    switch (bitmapInfo & kCGBitmapByteOrderMask) {
        case kCGBitmapByteOrderDefault: {
            byteOrderNormal = YES;
        } break;
        case kCGBitmapByteOrder32Little: {
        } break;
        case kCGBitmapByteOrder32Big: {
            byteOrderNormal = YES;
        } break;
        default: {
            return NO;
        } break;
    }
    
    /*
     Try convert with vImageConvert_AnyToAny() (avaliable since iOS 7.0).
     If fail, try decode with CGContextDrawImage().
     CGBitmapContext use a premultiplied alpha format, unpremultiply may lose precision.
     */
    vImage_CGImageFormat destFormat = {0};
    destFormat.bitsPerComponent = 8;
    destFormat.bitsPerPixel = 32;
    destFormat.colorSpace = YYCGColorSpaceGetDeviceRGB();
    destFormat.bitmapInfo = bitmapInfo;
    dest->data = NULL;
    if (YYCGImageDecodeToBitmapBufferWithAnyFormat(srcImage, dest, &destFormat)) return YES;
    
    CGBitmapInfo contextBitmapInfo = bitmapInfo & kCGBitmapByteOrderMask;
    if (!hasAlpha || alphaPremultiplied) {
        contextBitmapInfo |= (bitmapInfo & kCGBitmapAlphaInfoMask);
    } else {
        contextBitmapInfo |= alphaFirst ? kCGImageAlphaPremultipliedFirst : kCGImageAlphaPremultipliedLast;
    }
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, YYCGColorSpaceGetDeviceRGB(), contextBitmapInfo);
    if (!context) goto fail;
    
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), srcImage); // decode and convert
    size_t bytesPerRow = CGBitmapContextGetBytesPerRow(context);
    size_t length = height * bytesPerRow;
    void *data = CGBitmapContextGetData(context);
    if (length == 0 || !data) goto fail;
    
    dest->data = malloc(length);
    dest->width = width;
    dest->height = height;
    dest->rowBytes = bytesPerRow;
    if (!dest->data) goto fail;
    
    if (hasAlpha && !alphaPremultiplied) {
        vImage_Buffer tmpSrc = {0};
        tmpSrc.data = data;
        tmpSrc.width = width;
        tmpSrc.height = height;
        tmpSrc.rowBytes = bytesPerRow;
        vImage_Error error;
        if (alphaFirst && byteOrderNormal) {
            error = vImageUnpremultiplyData_ARGB8888(&tmpSrc, dest, kvImageNoFlags);
        } else {
            error = vImageUnpremultiplyData_RGBA8888(&tmpSrc, dest, kvImageNoFlags);
        }
        if (error != kvImageNoError) goto fail;
    } else {
        memcpy(dest->data, data, length);
    }
    
    CFRelease(context);
    return YES;
    
fail:
    if (context) CFRelease(context);
    if (dest->data) free(dest->data);
    dest->data = NULL;
    return NO;
    return NO;
}

CFDataRef YYCGImageCreateEncodedWebPData(CGImageRef imageRef, BOOL lossless, CGFloat quality, int compressLevel, YYImagePreset preset) {
    if (!imageRef) return nil;
    size_t width = CGImageGetWidth(imageRef);
    size_t height = CGImageGetHeight(imageRef);
    if (width == 0 || width > WEBP_MAX_DIMENSION) return nil;
    if (height == 0 || height > WEBP_MAX_DIMENSION) return nil;
    
    vImage_Buffer buffer = {0};
    if(!YYCGImageDecodeToBitmapBufferWith32BitFormat(imageRef, &buffer, kCGImageAlphaLast | kCGBitmapByteOrderDefault)) return nil;
    
    WebPConfig config = {0};
    WebPPicture picture = {0};
    WebPMemoryWriter writer = {0};
    CFDataRef webpData = NULL;
    BOOL pictureNeedFree = NO;
    
    quality = quality < 0 ? 0 : quality > 1 ? 1 : quality;
    preset = preset > YYImagePresetText ? YYImagePresetDefault : preset;
    compressLevel = compressLevel < 0 ? 0 : compressLevel > 6 ? 6 : compressLevel;
    if (!WebPConfigPreset(&config, (WebPPreset)preset, quality)) goto fail;
    
    config.quality = round(quality * 100.0);
    config.lossless = lossless;
    config.method = compressLevel;
    switch ((WebPPreset)preset) {
        case WEBP_PRESET_DEFAULT: {
            config.image_hint = WEBP_HINT_DEFAULT;
        } break;
        case WEBP_PRESET_PICTURE: {
            config.image_hint = WEBP_HINT_PICTURE;
        } break;
        case WEBP_PRESET_PHOTO: {
            config.image_hint = WEBP_HINT_PHOTO;
        } break;
        case WEBP_PRESET_DRAWING:
        case WEBP_PRESET_ICON:
        case WEBP_PRESET_TEXT: {
            config.image_hint = WEBP_HINT_GRAPH;
        } break;
    }
    if (!WebPValidateConfig(&config)) goto fail;
    
    if (!WebPPictureInit(&picture)) goto fail;
    pictureNeedFree = YES;
    picture.width = (int)buffer.width;
    picture.height = (int)buffer.height;
    picture.use_argb = lossless;
    if(!WebPPictureImportRGBA(&picture, buffer.data, (int)buffer.rowBytes)) goto fail;
    
    WebPMemoryWriterInit(&writer);
    picture.writer = WebPMemoryWrite;
    picture.custom_ptr = &writer;
    if(!WebPEncode(&config, &picture)) goto fail;
    
    webpData = CFDataCreate(CFAllocatorGetDefault(), writer.mem, writer.size);
    free(writer.mem);
    WebPPictureFree(&picture);
    free(buffer.data);
    return webpData;
    
fail:
    if (buffer.data) free(buffer.data);
    if (pictureNeedFree) WebPPictureFree(&picture);
    return nil;
}

@implementation NSImage (Webp)

- (NSData *)toWebpImageDataWithLossLess:(BOOL)lossLess quality:(CGFloat)quality {
    // encode webp
    NSMutableArray *webpDatas = [NSMutableArray new];
    
    CGImageRef image = [self CGImage];
    if (!image) return nil;
    CFDataRef frameData = YYCGImageCreateEncodedWebPData(image, lossLess, quality, 4, YYImagePresetDefault);
    CFRelease(image);
    if (!frameData) return nil;
    [webpDatas addObject:(__bridge id)frameData];
    CFRelease(frameData);

    return webpDatas.firstObject;
}


- (CGImageRef)CGImage CF_RETURNS_RETAINED{
    NSData *imageData = self.TIFFRepresentation;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)imageData, NULL);
    CGImageRef maskRef = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    return maskRef;
}

@end

@implementation NSData (Webp)

- (NSData *)toWebpImageDataWithLossLess:(BOOL)lossLess quality:(CGFloat)quality {
    NSImage *image = [[NSImage alloc] initWithData:self];
    return [image toWebpImageDataWithLossLess:lossLess quality:quality];
}

@end
