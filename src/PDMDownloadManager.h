// Copyright © 2026 PrismDM. All Rights Reserved. Proprietary and Confidential.

#import <UIKit/UIKit.h>
#import "PDMUI.h"
#import "PDMMediaSniffer.h"

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const PDMDownloadsDidUpdateNotification;

typedef NS_ENUM(NSInteger, PDMDownloadStatus) {
    PDMDownloadStatusQueued = 0,
    PDMDownloadStatusProbing = 1,
    PDMDownloadStatusDownloading = 2,
    PDMDownloadStatusMuxing = 3,
    PDMDownloadStatusConverting = 4,
    PDMDownloadStatusPaused = 5,
    PDMDownloadStatusCompleted = 6,
    PDMDownloadStatusFailed = 7,
    PDMDownloadStatusCanceled = 8
};

@interface PDMDownloadSegment : NSObject
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, assign) int64_t startOffset;
@property (nonatomic, assign) int64_t endOffset;
@property (nonatomic, assign) int64_t downloadedBytes;
@property (nonatomic, assign) BOOL completed;
- (double)progressFraction;
- (NSDictionary<NSString *, id> *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary<NSString *, id> *)dict;
@end

@interface PDMDownloadItem : NSObject
@property (nonatomic, copy) NSString *itemID;
@property (nonatomic, copy) NSString *urlString;
@property (nonatomic, copy, nullable) NSString *referer;
@property (nonatomic, copy, nullable) NSString *userAgent;
@property (nonatomic, copy, nullable) NSString *cookieHeader;
@property (nonatomic, copy) NSString *filename;
@property (nonatomic, copy, nullable) NSString *localFilePath;
@property (nonatomic, copy, nullable) NSString *partFilePath;
@property (nonatomic, copy) NSString *category;
@property (nonatomic, assign) BOOL isPrivateVault;
@property (nonatomic, assign) PDMDownloadStatus status;
@property (nonatomic, assign) int64_t totalBytes;
@property (nonatomic, assign) int64_t downloadedBytes;
@property (nonatomic, assign) double speedBytesPerSec;
@property (nonatomic, assign) double etaSeconds;
@property (nonatomic, assign) double conversionProgress;
@property (nonatomic, copy, nullable) NSString *errorMessage;
@property (nonatomic, assign) BOOL supportsRange;
@property (nonatomic, assign) NSInteger segmentCount;
@property (nonatomic, strong) NSMutableArray<PDMDownloadSegment *> *segments;
@property (nonatomic, assign) BOOL isHLS;
@property (nonatomic, copy, nullable) NSString *hlsVideoVariantURL;
@property (nonatomic, copy, nullable) NSString *hlsAudioTrackURL;
@property (nonatomic, copy, nullable) NSString *qualityLabel;
@property (nonatomic, copy, nullable) NSString *audioTrackLabel;
@property (nonatomic, strong) PDMMediaFormatConfig *formatConfig;
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, strong, nullable) NSDate *completedAt;

- (double)overallProgress;
- (NSArray<NSNumber *> *)segmentProgressFractions;
- (BOOL)isActiveTransfer;
- (NSDictionary<NSString *, id> *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary<NSString *, id> *)dict;
@end

@interface PDMDownloadManager : NSObject

+ (instancetype)sharedManager;

@property (nonatomic, copy, readonly) NSArray<PDMDownloadItem *> *items;
@property (atomic, assign, readonly) double aggregateSpeedBytesPerSec;
@property (atomic, assign, readonly) NSInteger activeCount;
@property (atomic, assign, readonly) NSInteger queuedCount;

+ (NSURL *)downloadsBaseDirectory;
+ (NSURL *)directoryForCategory:(NSString *)category isPrivateVault:(BOOL)isPrivateVault;
+ (BOOL)isWiFiConnected;

- (PDMDownloadItem *)enqueueDownloadWithURL:(NSString *)urlString
                                   filename:(nullable NSString *)filename
                                    referer:(nullable NSString *)referer
                                  userAgent:(nullable NSString *)userAgent
                               cookieHeader:(nullable NSString *)cookieHeader
                               formatConfig:(nullable PDMMediaFormatConfig *)config
                               qualityLabel:(nullable NSString *)qualityLabel
                            audioTrackLabel:(nullable NSString *)audioTrackLabel
                                      isHLS:(BOOL)isHLS
                           hlsAudioTrackURL:(nullable NSString *)hlsAudioURL
                           startImmediately:(BOOL)startImmediately;

- (PDMDownloadItem *)enqueueLocalConversionForFileURL:(NSURL *)sourceURL
                                               config:(PDMMediaFormatConfig *)config
                                       outputFilename:(NSString *)outputFilename
                                       isPrivateVault:(BOOL)isPrivateVault;

- (void)startItemWithID:(NSString *)itemID;
- (void)pauseItemWithID:(NSString *)itemID;
- (void)resumeItemWithID:(NSString *)itemID;
- (void)retryItemWithID:(NSString *)itemID;
- (void)cancelItemWithID:(NSString *)itemID;
- (void)deleteItemWithID:(NSString *)itemID removeLocalFile:(BOOL)removeLocalFile;
- (void)refreshDownloadAddressForItemID:(NSString *)itemID
                              newURLStr:(NSString *)newURLString
                                referer:(nullable NSString *)referer
                           cookieHeader:(nullable NSString *)cookieHeader;
- (void)saveState;

@end

@interface PDMDownloadManagerViewController : UIViewController
@property (nonatomic, copy, nullable) dispatch_block_t onOpenLibraryRequested;
@property (nonatomic, copy, nullable) dispatch_block_t onOpenSettingsRequested;
@end

@interface PDMAddURLSheetViewController : PDMGlassSheetViewController
@property (nonatomic, copy, nullable) NSString *initialURL;
@end

NS_ASSUME_NONNULL_END
