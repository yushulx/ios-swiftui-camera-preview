#ifndef DCV_H
#define DCV_H

#import <Foundation/Foundation.h>

//! Project version number for DCV.
FOUNDATION_EXPORT double DCVVersionNumber;

//! Project version string for DCV.
FOUNDATION_EXPORT const unsigned char DCVVersionString[];

typedef NS_ENUM(NSInteger, PixelFormat) {
    PixelFormatBinary = 0,
    PixelFormatBinaryInverted = 1,
    PixelFormatGrayscale = 2,
    PixelFormatNV21 = 3,
    PixelFormatRGB565 = 4,
    PixelFormatRGB555 = 5,
    PixelFormatRGB888 = 6,
    PixelFormatARGB8888 = 7,
    PixelFormatRGB161616 = 8,
    PixelFormatARGB16161616 = 9,
    PixelFormatABGR8888 = 10,
    PixelFormatABGR16161616 = 11,
    PixelFormatBGR888 = 12,
    PixelFormatBinary8 = 13,
    PixelFormatNV12 = 14,
    PixelFormatBinary8Inverted = 15
};
typedef NS_ENUM(unsigned long long, BarcodeType) {
    NO_CODE = 0x00,

    ALL = 0xFFFFFFFEFFFFFFFF,

    DEFAULT = 0xFE3BFFFF,

    ONED = 0x003007FF,

    GS1_DATABAR = 0x0003F800,

    CODE_39 = 0x1,

    CODE_128 = 0x2,

    CODE_93 = 0x4,

    CODABAR = 0x8,

    ITF = 0x10,

    EAN_13 = 0x20,

    EAN_8 = 0x40,

    UPC_A = 0x80,

    UPC_E = 0x100,

    INDUSTRIAL_25 = 0x200,

    CODE_39_EXTENDED = 0x400,

    GS1_DATABAR_OMNIDIRECTIONAL = 0x800,

    GS1_DATABAR_TRUNCATED = 0x1000,

    GS1_DATABAR_STACKED = 0x2000,

    GS1_DATABAR_STACKED_OMNIDIRECTIONAL = 0x4000,

    GS1_DATABAR_EXPANDED = 0x8000,

    GS1_DATABAR_EXPANDED_STACKED = 0x10000,

    GS1_DATABAR_LIMITED = 0x20000,

    PATCHCODE = 0x00040000,

    CODE_32 = 0x1000000,

    PDF417 = 0x02000000,

    QR_CODE = 0x04000000,

    DATAMATRIX = 0x08000000,

    AZTEC = 0x10000000,

    MAXICODE = 0x20000000,

    MICRO_QR = 0x40000000,

    MICRO_PDF417 = 0x00080000,

    GS1_COMPOSITE = 0x80000000,

    MSI_CODE = 0x100000,

    CODE_11 = 0x200000,

    TWO_DIGIT_ADD_ON = 0x400000,

    FIVE_DIGIT_ADD_ON = 0x800000,

    MATRIX_25 = 0x1000000000,

    POSTALCODE = 0x3F0000000000000,

    NONSTANDARD_BARCODE = 0x100000000,

    USPSINTELLIGENTMAIL = 0x10000000000000,

    POSTNET = 0x20000000000000,

    PLANET = 0x40000000000000,

    AUSTRALIANPOST = 0x80000000000000,

    RM4SCC = 0x100000000000000,

    KIX = 0x200000000000000,

    DOTCODE = 0x200000000,

    PHARMACODE_ONE_TRACK = 0x400000000,

    PHARMACODE_TWO_TRACK = 0x800000000,

    PHARMACODE = 0xC00000000

};

// Objective-C interface
@interface CaptureVisionWrapper : NSObject
+ (int)initializeLicense:(NSString *)licenseKey;

- (NSArray *)decodeBufferWithData:(void *)baseAddress
                            width:(int)width
                           height:(int)height
                           stride:(int)stride
                      pixelFormat:(PixelFormat)pixelFormat;

- (NSArray *)decodeFileWithPath:(NSString *)filePath;
- (NSString *)getSettings;
- (int)setSettings:(NSString *)jsonString;
- (int)setBarcodeFormats:(unsigned long long)formats;
@end

#endif
