// Copyright © 2026 PrismDM. All Rights Reserved. Proprietary and Confidential.

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import "PDMUI.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PDMOutputMode) {
    PDMOutputModeOriginal = 0,
    PDMOutputModeVideo = 1,
    PDMOutputModeAudioOnly = 2
};

typedef NS_ENUM(NSInteger, PDMVideoFormat) {
    PDMVideoFormatMP4H264 = 0,
    PDMVideoFormatMP4HEVC = 1,
    PDMVideoFormatMOVH264 = 2,
    PDMVideoFormatMOVHEVC = 3,
    PDMVideoFormatM4VH264 = 4
};

typedef NS_ENUM(NSInteger, PDMTargetResolution) {
    PDMTargetResolutionOriginal = 0,
    PDMTargetResolution1080p = 1,
    PDMTargetResolution720p = 2,
    PDMTargetResolution480p = 3
};

typedef NS_ENUM(NSInteger, PDMVideoQualityPreset) {
    PDMVideoQualityPresetHigh = 0,
    PDMVideoQualityPresetBalanced = 1,
    PDMVideoQualityPresetCompact = 2
};

typedef NS_ENUM(NSInteger, PDMAudioFormat) {
    PDMAudioFormatMP3 = 0,
    PDMAudioFormatM4AAAC = 1,
    PDMAudioFormatM4AALAC = 2,
    PDMAudioFormatFLAC = 3,
    PDMAudioFormatWAV = 4
};

@interface PDMWeakScriptMessageHandler : NSObject <WKScriptMessageHandler>
@property (nonatomic, weak) id<WKScriptMessageHandler> delegate;
- (instancetype)initWithDelegate:(id<WKScriptMessageHandler>)delegate;
@end

@interface PDMMediaAudioTrack : NSObject
@property (nonatomic, copy) NSString *trackID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *language;
@property (nonatomic, copy) NSString *groupID;
@property (nonatomic, copy) NSString *channels;
@property (nonatomic, assign) NSInteger bitrateKbps;
@property (nonatomic, assign) BOOL isDefault;
@property (nonatomic, assign) BOOL isAutoSelect;
@property (nonatomic, copy, nullable) NSString *uri;
@property (nonatomic, assign) NSInteger trackIndex;
- (NSString *)displayLabel;
@end

@interface PDMMediaVideoVariant : NSObject
@property (nonatomic, copy) NSString *variantID;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, assign) NSInteger width;
@property (nonatomic, assign) NSInteger height;
@property (nonatomic, assign) double fps;
@property (nonatomic, assign) int64_t bandwidthBps;
@property (nonatomic, assign) int64_t estimatedBytes;
@property (nonatomic, copy, nullable) NSString *audioGroupID;
@property (nonatomic, copy, nullable) NSString *codecs;
@property (nonatomic, copy) NSString *uri;
@property (nonatomic, assign) BOOL isAudioOnly;
- (NSString *)specSubtitle;
@end

@interface PDMMediaFormatConfig : NSObject <NSCopying>
@property (nonatomic, assign) PDMOutputMode outputMode;
@property (nonatomic, assign) PDMVideoFormat videoFormat;
@property (nonatomic, assign) PDMTargetResolution targetResolution;
@property (nonatomic, assign) PDMVideoQualityPreset qualityPreset;
@property (nonatomic, assign) PDMAudioFormat audioFormat;
@property (nonatomic, assign) NSInteger audioBitrateKbps; // 320, 256, 192, 128, 96, 64
@property (nonatomic, assign) NSInteger selectedAudioTrackIndex;
@property (nonatomic, copy) NSString *destinationCategory; // @"Auto", @"Videos", @"Audio", @"Documents", @"Private Vault"
@property (nonatomic, assign) NSInteger segmentCount; // 2, 4, 8, 16

+ (instancetype)defaultConfig;
- (NSString *)targetFileExtension;
- (NSString *)summaryBadgeText;
- (NSDictionary<NSString *, id> *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary<NSString *, id> *)dict;
@end

@interface PDMDetectedMedia : NSObject
@property (nonatomic, copy) NSString *mediaID;
@property (nonatomic, copy) NSString *urlString;
@property (nonatomic, copy, nullable) NSString *pageURLString;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *filename;
@property (nonatomic, copy) NSString *sourceBadge;
@property (nonatomic, copy, nullable) NSString *mimeType;
@property (nonatomic, assign) int64_t contentLength;
@property (nonatomic, assign) double durationSeconds;
@property (nonatomic, copy, nullable) NSString *referer;
@property (nonatomic, copy, nullable) NSString *userAgent;
@property (nonatomic, copy, nullable) NSString *cookieHeader;
@property (nonatomic, assign) BOOL isHLS;
@property (nonatomic, assign) BOOL isDASH;
@property (nonatomic, assign) BOOL isDRMProtected;
@property (nonatomic, assign) BOOL isAES128Encrypted;
@property (nonatomic, assign) BOOL isInspected;
@property (nonatomic, strong) NSMutableArray<PDMMediaVideoVariant *> *variants;
@property (nonatomic, strong) NSMutableArray<PDMMediaAudioTrack *> *audioTracks;
@property (nonatomic, strong) NSDate *detectedAt;
@end

@interface PDMPageResource : NSObject
@property (nonatomic, copy) NSString *urlString;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *category; // Video, Audio, Images, Archives, Documents
@property (nonatomic, copy) NSString *fileExtension;
@property (nonatomic, assign) BOOL selected;
@end

@interface PDMMediaSniffer : NSObject

+ (WKUserScript *)mediaSnifferUserScript;
+ (NSString *)pageResourceExtractionJavaScript;
+ (BOOL)isMediaURLString:(NSString *)urlString;
+ (BOOL)isDownloadableResponse:(NSURLResponse *)response;
+ (NSString *)sourceBadgeForURLString:(NSString *)urlString mimeType:(nullable NSString *)mimeType;
+ (nullable PDMDetectedMedia *)mediaFromMessageBody:(id)body
                                           pageURL:(nullable NSString *)pageURL
                                         pageTitle:(nullable NSString *)pageTitle
                                         userAgent:(nullable NSString *)userAgent
                                      cookieHeader:(nullable NSString *)cookieHeader;

+ (void)inspectMedia:(PDMDetectedMedia *)media completion:(void (^)(PDMDetectedMedia *inspected))completion;
+ (void)parseHLSPlaylistText:(NSString *)playlistText
                     baseURL:(NSURL *)baseURL
                   intoMedia:(PDMDetectedMedia *)media;

@end

@interface PDMMediaPickerSheetViewController : PDMGlassSheetViewController
@property (nonatomic, strong) PDMDetectedMedia *media;
@property (nonatomic, assign) BOOL studioOnlyMode; // Used from Library/Player for Convert & Extract Audio
@property (nonatomic, copy, nullable) NSString *localFilePathForStudio;
@property (nonatomic, copy, nullable) void (^onDownloadRequested)(PDMDetectedMedia *media,
                                                                  PDMMediaVideoVariant * _Nullable selectedVariant,
                                                                  PDMMediaAudioTrack * _Nullable selectedAudio,
                                                                  PDMMediaFormatConfig *config,
                                                                  NSString *finalFilename,
                                                                  BOOL startImmediately);
@property (nonatomic, copy, nullable) void (^onStreamPreviewRequested)(NSURL *streamURL,
                                                                       NSString *title,
                                                                       NSDictionary<NSString *, NSString *> * _Nullable headers);
@end

@interface PDMResourceGrabberSheetViewController : PDMGlassSheetViewController
@property (nonatomic, copy) NSArray<PDMPageResource *> *resources;
@property (nonatomic, copy, nullable) NSString *referer;
@property (nonatomic, copy, nullable) NSString *userAgent;
@property (nonatomic, copy, nullable) NSString *cookieHeader;
@property (nonatomic, copy, nullable) void (^onBatchDownload)(NSArray<PDMPageResource *> *selectedResources);
@end

NS_ASSUME_NONNULL_END
