// Copyright © 2026 PrismDM. All Rights Reserved. Proprietary and Confidential.

#import "PDMDownloadManager.h"
#import "PDMTranscoder.h"
#import "PDMMediaPlayer.h"
#import "PDMPrivacyShield.h"
#import <fcntl.h>
#import <unistd.h>
#import <sys/stat.h>
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <net/if.h>

NSNotificationName const PDMDownloadsDidUpdateNotification = @"PDMDownloadsDidUpdateNotification";

static const int64_t kPDMMultiSegmentThresholdBytes = 2LL * 1024LL * 1024LL; // 2 MB

#pragma mark - PDMDownloadSegment

@implementation PDMDownloadSegment

- (double)progressFraction {
    int64_t len = (self.endOffset >= self.startOffset) ? (self.endOffset - self.startOffset + 1) : 0;
    if (self.completed) return 1.0;
    if (len <= 0) return 0.0;
    return MIN(1.0, MAX(0.0, (double)self.downloadedBytes / (double)len));
}

- (NSDictionary<NSString *, id> *)toDictionary {
    return @{
        @"index": @(self.index),
        @"startOffset": @(self.startOffset),
        @"endOffset": @(self.endOffset),
        @"downloadedBytes": @(self.downloadedBytes),
        @"completed": @(self.completed)
    };
}

+ (instancetype)fromDictionary:(NSDictionary<NSString *, id> *)dict {
    PDMDownloadSegment *s = [[PDMDownloadSegment alloc] init];
    s.index = [dict[@"index"] integerValue];
    s.startOffset = [dict[@"startOffset"] longLongValue];
    s.endOffset = [dict[@"endOffset"] longLongValue];
    s.downloadedBytes = [dict[@"downloadedBytes"] longLongValue];
    s.completed = [dict[@"completed"] boolValue];
    return s;
}

- (id)copyWithZone:(nullable NSZone *)zone {
    PDMDownloadSegment *c = [[[self class] allocWithZone:zone] init];
    c.index = self.index;
    c.startOffset = self.startOffset;
    c.endOffset = self.endOffset;
    c.downloadedBytes = self.downloadedBytes;
    c.completed = self.completed;
    return c;
}

@end

#pragma mark - PDMDownloadItem

@implementation PDMDownloadItem

- (instancetype)init {
    self = [super init];
    if (self) {
        _itemID = [NSUUID UUID].UUIDString;
        _filename = @"PrismDM_File";
        _category = @"Documents";
        _status = PDMDownloadStatusQueued;
        _segmentCount = [PDMThemeManager sharedManager].defaultSegmentCount;
        _segments = [NSMutableArray array];
        _formatConfig = [PDMMediaFormatConfig defaultConfig];
        _createdAt = [NSDate date];
    }
    return self;
}

- (id)copyWithZone:(nullable NSZone *)zone {
    PDMDownloadItem *c = [[[self class] allocWithZone:zone] init];
    c.itemID = self.itemID;
    c.urlString = self.urlString;
    c.referer = self.referer;
    c.userAgent = self.userAgent;
    c.cookieHeader = self.cookieHeader;
    c.filename = self.filename;
    c.localFilePath = self.localFilePath;
    c.partFilePath = self.partFilePath;
    c.category = self.category;
    c.isPrivateVault = self.isPrivateVault;
    c.status = self.status;
    c.totalBytes = self.totalBytes;
    c.downloadedBytes = self.downloadedBytes;
    c.speedBytesPerSec = self.speedBytesPerSec;
    c.etaSeconds = self.etaSeconds;
    c.conversionProgress = self.conversionProgress;
    c.errorMessage = self.errorMessage;
    c.supportsRange = self.supportsRange;
    c.segmentCount = self.segmentCount;
    NSMutableArray<PDMDownloadSegment *> *segCopies = [NSMutableArray arrayWithCapacity:self.segments.count];
    for (PDMDownloadSegment *seg in self.segments) {
        [segCopies addObject:[seg copy]];
    }
    c.segments = segCopies;
    c.isHLS = self.isHLS;
    c.hlsVideoVariantURL = self.hlsVideoVariantURL;
    c.hlsAudioTrackURL = self.hlsAudioTrackURL;
    c.qualityLabel = self.qualityLabel;
    c.audioTrackLabel = self.audioTrackLabel;
    c.formatConfig = [self.formatConfig copy];
    c.createdAt = self.createdAt;
    c.completedAt = self.completedAt;
    return c;
}

- (double)overallProgress {
    if (self.status == PDMDownloadStatusCompleted) return 1.0;
    if (self.status == PDMDownloadStatusConverting || self.status == PDMDownloadStatusMuxing) {
        return MAX(0.0, MIN(1.0, self.conversionProgress));
    }
    if (self.totalBytes > 0) {
        return MAX(0.0, MIN(1.0, (double)self.downloadedBytes / (double)self.totalBytes));
    }
    if (self.segments.count > 0) {
        double sum = 0.0;
        for (PDMDownloadSegment *seg in self.segments) {
            sum += [seg progressFraction];
        }
        return sum / (double)self.segments.count;
    }
    return 0.0;
}

- (NSArray<NSNumber *> *)segmentProgressFractions {
    if (self.segments.count > 0) {
        NSMutableArray<NSNumber *> *arr = [NSMutableArray arrayWithCapacity:self.segments.count];
        for (PDMDownloadSegment *seg in self.segments) {
            [arr addObject:@([seg progressFraction])];
        }
        return arr;
    }
    return @[@([self overallProgress])];
}

- (BOOL)isActiveTransfer {
    return (self.status == PDMDownloadStatusProbing ||
            self.status == PDMDownloadStatusDownloading ||
            self.status == PDMDownloadStatusMuxing ||
            self.status == PDMDownloadStatusConverting);
}

- (NSDictionary<NSString *, id> *)toDictionary {
    NSMutableArray<NSDictionary<NSString *, id> *> *segDicts = [NSMutableArray arrayWithCapacity:self.segments.count];
    for (PDMDownloadSegment *s in self.segments) {
        [segDicts addObject:[s toDictionary]];
    }
    return @{
        @"itemID": self.itemID ?: @"",
        @"urlString": self.urlString ?: @"",
        @"referer": self.referer ?: @"",
        @"userAgent": self.userAgent ?: @"",
        @"cookieHeader": self.cookieHeader ?: @"",
        @"filename": self.filename ?: @"PrismDM_File",
        @"localFilePath": self.localFilePath ?: @"",
        @"partFilePath": self.partFilePath ?: @"",
        @"category": self.category ?: @"Documents",
        @"isPrivateVault": @(self.isPrivateVault),
        @"status": @(self.status),
        @"totalBytes": @(self.totalBytes),
        @"downloadedBytes": @(self.downloadedBytes),
        @"supportsRange": @(self.supportsRange),
        @"segmentCount": @(self.segmentCount),
        @"segments": segDicts,
        @"isHLS": @(self.isHLS),
        @"hlsVideoVariantURL": self.hlsVideoVariantURL ?: @"",
        @"hlsAudioTrackURL": self.hlsAudioTrackURL ?: @"",
        @"qualityLabel": self.qualityLabel ?: @"",
        @"audioTrackLabel": self.audioTrackLabel ?: @"",
        @"formatConfig": [self.formatConfig toDictionary],
        @"createdAt": @(self.createdAt.timeIntervalSince1970),
        @"completedAt": @(self.completedAt ? self.completedAt.timeIntervalSince1970 : 0.0)
    };
}

+ (instancetype)fromDictionary:(NSDictionary<NSString *, id> *)dict {
    PDMDownloadItem *item = [[PDMDownloadItem alloc] init];
    if ([dict[@"itemID"] isKindOfClass:[NSString class]]) item.itemID = dict[@"itemID"];
    if ([dict[@"urlString"] isKindOfClass:[NSString class]]) item.urlString = dict[@"urlString"];
    NSString *ref = dict[@"referer"];
    if ([ref isKindOfClass:[NSString class]] && ref.length > 0) item.referer = ref;
    NSString *ua = dict[@"userAgent"];
    if ([ua isKindOfClass:[NSString class]] && ua.length > 0) item.userAgent = ua;
    NSString *ck = dict[@"cookieHeader"];
    if ([ck isKindOfClass:[NSString class]] && ck.length > 0) item.cookieHeader = ck;
    if ([dict[@"filename"] isKindOfClass:[NSString class]]) item.filename = dict[@"filename"];
    NSString *lp = dict[@"localFilePath"];
    if ([lp isKindOfClass:[NSString class]] && lp.length > 0) item.localFilePath = lp;
    NSString *pp = dict[@"partFilePath"];
    if ([pp isKindOfClass:[NSString class]] && pp.length > 0) item.partFilePath = pp;
    if ([dict[@"category"] isKindOfClass:[NSString class]]) item.category = dict[@"category"];
    item.isPrivateVault = [dict[@"isPrivateVault"] boolValue];
    PDMDownloadStatus st = (PDMDownloadStatus)[dict[@"status"] integerValue];
    // Any in-flight transfer from a previous app session resumes cleanly as Paused
    if (st == PDMDownloadStatusProbing || st == PDMDownloadStatusDownloading || st == PDMDownloadStatusMuxing || st == PDMDownloadStatusConverting) {
        st = PDMDownloadStatusPaused;
    }
    item.status = st;
    item.totalBytes = [dict[@"totalBytes"] longLongValue];
    item.downloadedBytes = [dict[@"downloadedBytes"] longLongValue];
    item.supportsRange = [dict[@"supportsRange"] boolValue];
    item.segmentCount = MAX(1, [dict[@"segmentCount"] integerValue]);
    if ([dict[@"segments"] isKindOfClass:[NSArray class]]) {
        for (NSDictionary *sd in (NSArray *)dict[@"segments"]) {
            if ([sd isKindOfClass:[NSDictionary class]]) {
                [item.segments addObject:[PDMDownloadSegment fromDictionary:sd]];
            }
        }
    }
    item.isHLS = [dict[@"isHLS"] boolValue];
    NSString *hv = dict[@"hlsVideoVariantURL"];
    if ([hv isKindOfClass:[NSString class]] && hv.length > 0) item.hlsVideoVariantURL = hv;
    NSString *ha = dict[@"hlsAudioTrackURL"];
    if ([ha isKindOfClass:[NSString class]] && ha.length > 0) item.hlsAudioTrackURL = ha;
    NSString *ql = dict[@"qualityLabel"];
    if ([ql isKindOfClass:[NSString class]] && ql.length > 0) item.qualityLabel = ql;
    NSString *al = dict[@"audioTrackLabel"];
    if ([al isKindOfClass:[NSString class]] && al.length > 0) item.audioTrackLabel = al;
    if ([dict[@"formatConfig"] isKindOfClass:[NSDictionary class]]) {
        item.formatConfig = [PDMMediaFormatConfig fromDictionary:dict[@"formatConfig"]];
    }
    double ct = [dict[@"createdAt"] doubleValue];
    if (ct > 0.0) item.createdAt = [NSDate dateWithTimeIntervalSince1970:ct];
    double comp = [dict[@"completedAt"] doubleValue];
    if (comp > 0.0) item.completedAt = [NSDate dateWithTimeIntervalSince1970:comp];
    return item;
}

@end

#pragma mark - Active Task Context

@interface PDMActiveDownloadContext : NSObject
@property (nonatomic, copy) NSString *itemID;
@property (nonatomic, assign) int fd;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *taskIDToSegmentIndex;
@property (nonatomic, strong) NSMutableArray<NSURLSessionTask *> *tasks;
@property (nonatomic, strong, nullable) PDMTranscodeJob *transcodeJob;
@property (nonatomic, assign) int64_t bytesInWindow;
@property (nonatomic, assign) CFTimeInterval lastSampleTime;
@property (nonatomic, assign) BOOL cancelledOrPaused;
@property (nonatomic, assign) BOOL finalizing;
@property (nonatomic, assign) BOOL fellBackToSingle;
@end

@implementation PDMActiveDownloadContext

- (instancetype)initWithItemID:(NSString *)itemID {
    self = [super init];
    if (self) {
        _itemID = [itemID copy];
        _fd = -1;
        _taskIDToSegmentIndex = [NSMutableDictionary dictionary];
        _tasks = [NSMutableArray array];
        _lastSampleTime = CFAbsoluteTimeGetCurrent();
    }
    return self;
}

- (void)closeFileDescriptor {
    if (self.fd >= 0) {
        fsync(self.fd);
        close(self.fd);
        self.fd = -1;
    }
}

- (void)dealloc {
    [self closeFileDescriptor];
}

@end

#pragma mark - PDMDownloadManager

@interface PDMDownloadManager () <NSURLSessionDataDelegate, NSURLSessionDownloadDelegate>
@property (nonatomic, strong) NSMutableArray<PDMDownloadItem *> *mutableItems;
@property (nonatomic, strong) NSMutableDictionary<NSString *, PDMActiveDownloadContext *> *activeContexts;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *taskIDToItemID;
@property (nonatomic, strong) NSURLSession *transferSession;
@property (nonatomic, strong) dispatch_queue_t engineQueue;
@property (nonatomic, strong, nullable) NSTimer *telemetryTimer;
@property (atomic, assign, readwrite) double aggregateSpeedBytesPerSec;
@property (atomic, assign, readwrite) NSInteger activeCount;
@property (atomic, assign, readwrite) NSInteger queuedCount;
@property (nonatomic, assign) int64_t throttleBytesThisSecond;
@property (nonatomic, assign) CFTimeInterval throttleWindowStart;
@end

@implementation PDMDownloadManager

+ (instancetype)sharedManager {
    static PDMDownloadManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[PDMDownloadManager alloc] init];
    });
    return instance;
}

+ (NSURL *)downloadsBaseDirectory {
    NSURL *docs = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];
    NSURL *base = [docs URLByAppendingPathComponent:@"PrismDM_Downloads" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:base withIntermediateDirectories:YES attributes:nil error:nil];
    return base;
}

+ (NSURL *)directoryForCategory:(NSString *)category isPrivateVault:(BOOL)isPrivateVault {
    NSURL *base = [self downloadsBaseDirectory];
    NSString *folder = isPrivateVault ? @".PrivateVault" : (category.length > 0 ? category : @"Documents");
    NSURL *dir = [base URLByAppendingPathComponent:folder isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

+ (NSURL *)persistenceFileURL {
    NSURL *appSup = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] firstObject];
    [[NSFileManager defaultManager] createDirectoryAtURL:appSup withIntermediateDirectories:YES attributes:nil error:nil];
    return [appSup URLByAppendingPathComponent:@"PDMDownloads.json"];
}

+ (BOOL)isWiFiConnected {
    struct ifaddrs *interfaces = NULL;
    BOOL wifiUp = NO;
    if (getifaddrs(&interfaces) == 0 && interfaces != NULL) {
        for (struct ifaddrs *cur = interfaces; cur != NULL; cur = cur->ifa_next) {
            if (!cur->ifa_addr || !cur->ifa_name) continue;
            sa_family_t fam = cur->ifa_addr->sa_family;
            if (fam != AF_INET && fam != AF_INET6) continue;
            unsigned int flags = cur->ifa_flags;
            BOOL isUp = ((flags & IFF_UP) != 0) && ((flags & IFF_RUNNING) != 0);
            if (isUp && strncmp(cur->ifa_name, "en", 2) == 0) {
                wifiUp = YES;
                break;
            }
        }
        freeifaddrs(interfaces);
    }
    return wifiUp;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableItems = [NSMutableArray array];
        _activeContexts = [NSMutableDictionary dictionary];
        _taskIDToItemID = [NSMutableDictionary dictionary];
        _engineQueue = dispatch_queue_create("com.prismdm.browser.dl.engine", DISPATCH_QUEUE_SERIAL);
        _throttleWindowStart = CFAbsoluteTimeGetCurrent();

        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.HTTPMaximumConnectionsPerHost = 16;
        cfg.timeoutIntervalForRequest = 30.0;
        cfg.timeoutIntervalForResource = 3600.0;
        cfg.waitsForConnectivity = YES;
        NSOperationQueue *delQueue = [[NSOperationQueue alloc] init];
        delQueue.maxConcurrentOperationCount = 1;
        delQueue.underlyingQueue = _engineQueue;
        _transferSession = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:delQueue];

        [self loadState];
    }
    return self;
}

- (NSArray<PDMDownloadItem *> *)items {
    __block NSArray<PDMDownloadItem *> *snap = nil;
    dispatch_sync(self.engineQueue, ^{
        NSMutableArray<PDMDownloadItem *> *copies = [NSMutableArray arrayWithCapacity:self.mutableItems.count];
        for (PDMDownloadItem *it in self.mutableItems) {
            [copies addObject:[it copy]];
        }
        snap = [copies copy];
    });
    return snap ?: @[];
}

- (void)loadState {
    NSURL *url = [[self class] persistenceFileURL];
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (!data) return;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSArray class]]) return;
    for (id entry in (NSArray *)json) {
        if ([entry isKindOfClass:[NSDictionary class]]) {
            [self.mutableItems addObject:[PDMDownloadItem fromDictionary:entry]];
        }
    }
}

- (void)saveState {
    dispatch_async(self.engineQueue, ^{
        [self saveStateLocked];
    });
}

- (void)saveStateLocked {
    NSMutableArray<NSDictionary<NSString *, id> *> *arr = [NSMutableArray arrayWithCapacity:self.mutableItems.count];
    for (PDMDownloadItem *it in self.mutableItems) {
        [arr addObject:[it toDictionary]];
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:arr options:NSJSONWritingPrettyPrinted error:nil];
    if (data) {
        [data writeToURL:[[self class] persistenceFileURL] atomically:YES];
    }
}

- (nullable PDMDownloadItem *)itemForIDLocked:(NSString *)itemID {
    for (PDMDownloadItem *it in self.mutableItems) {
        if ([it.itemID isEqualToString:itemID]) return it;
    }
    return nil;
}

- (NSURL *)uniqueDestinationURLForFilename:(NSString *)filename category:(NSString *)category isPrivateVault:(BOOL)isPrivateVault {
    NSURL *dir = [[self class] directoryForCategory:category isPrivateVault:isPrivateVault];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *candidate = [dir URLByAppendingPathComponent:filename];
    if (![fm fileExistsAtPath:candidate.path]) {
        return candidate;
    }
    NSString *base = [filename stringByDeletingPathExtension];
    NSString *ext = filename.pathExtension;
    for (NSInteger i = 1; i < 9999; i++) {
        NSString *alt = (ext.length > 0)
            ? [NSString stringWithFormat:@"%@ (%ld).%@", base, (long)i, ext]
            : [NSString stringWithFormat:@"%@ (%ld)", base, (long)i];
        NSURL *u = [dir URLByAppendingPathComponent:alt];
        if (![fm fileExistsAtPath:u.path]) {
            return u;
        }
    }
    return [dir URLByAppendingPathComponent:[NSString stringWithFormat:@"%@_%@", [NSUUID UUID].UUIDString, filename]];
}

#pragma mark - Enqueue & Queue Scheduling

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
                           startImmediately:(BOOL)startImmediately {
    PDMDownloadItem *item = [[PDMDownloadItem alloc] init];
    item.urlString = urlString;
    item.referer = referer;
    item.userAgent = userAgent;
    item.cookieHeader = cookieHeader;
    item.formatConfig = config ? [config copy] : [PDMMediaFormatConfig defaultConfig];
    item.segmentCount = MAX(1, MIN(16, item.formatConfig.segmentCount));
    item.qualityLabel = qualityLabel;
    item.audioTrackLabel = audioTrackLabel;
    item.isHLS = isHLS;
    item.hlsVideoVariantURL = isHLS ? urlString : nil;
    item.hlsAudioTrackURL = hlsAudioURL;

    NSURL *u = [NSURL URLWithString:urlString];
    NSString *fallbackExt = isHLS ? @"mp4" : (u.pathExtension.length > 0 ? u.pathExtension.lowercaseString : @"bin");
    NSString *rawName = (filename.length > 0) ? filename : (u.lastPathComponent.length > 0 ? u.lastPathComponent : @"PrismDM_Download");
    item.filename = [PDMThemeManager sanitizeFilename:rawName fallbackExtension:fallbackExt];

    if ([item.formatConfig.destinationCategory isEqualToString:@"Private Vault"]) {
        item.isPrivateVault = YES;
        item.category = @"Private Vault";
    } else if (![item.formatConfig.destinationCategory isEqualToString:@"Auto"] && item.formatConfig.destinationCategory.length > 0) {
        item.category = item.formatConfig.destinationCategory;
    } else {
        item.category = [PDMThemeManager categoryForFilename:item.filename mimeType:nil];
    }

    NSURL *partDir = [[[self class] downloadsBaseDirectory] URLByAppendingPathComponent:@".parts" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:partDir withIntermediateDirectories:YES attributes:nil error:nil];
    item.partFilePath = [partDir URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.pdmpart", item.itemID]].path;
    item.status = startImmediately ? PDMDownloadStatusQueued : PDMDownloadStatusPaused;

    dispatch_async(self.engineQueue, ^{
        [self.mutableItems insertObject:item atIndex:0];
        [self saveStateLocked];
        [self pumpQueueLocked];
        [self notifyUpdateLocked];
    });
    return item;
}

- (PDMDownloadItem *)enqueueLocalConversionForFileURL:(NSURL *)sourceURL
                                               config:(PDMMediaFormatConfig *)config
                                       outputFilename:(NSString *)outputFilename
                                       isPrivateVault:(BOOL)isPrivateVault {
    PDMDownloadItem *item = [[PDMDownloadItem alloc] init];
    item.urlString = sourceURL.absoluteString;
    item.formatConfig = [config copy];
    item.filename = [PDMThemeManager sanitizeFilename:outputFilename fallbackExtension:[config targetFileExtension]];
    item.isPrivateVault = isPrivateVault;
    item.category = isPrivateVault ? @"Private Vault" : [PDMThemeManager categoryForFilename:item.filename mimeType:nil];
    item.status = PDMDownloadStatusConverting;
    item.conversionProgress = 0.0;
    item.segmentCount = 1;

    dispatch_async(self.engineQueue, ^{
        [self.mutableItems insertObject:item atIndex:0];
        PDMActiveDownloadContext *ctx = [[PDMActiveDownloadContext alloc] initWithItemID:item.itemID];
        self.activeContexts[item.itemID] = ctx;
        [self ensureTelemetryTimerRunning];
        [self notifyUpdateLocked];

        NSURL *destURL = [self uniqueDestinationURLForFilename:item.filename category:item.category isPrivateVault:item.isPrivateVault];
        __weak typeof(self) weakSelf = self;
        ctx.transcodeJob = [[PDMTranscoder sharedTranscoder] transcodeFileAtURL:sourceURL
                                                                    toOutputURL:destURL
                                                                         config:item.formatConfig
                                                                       progress:^(double fraction) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            dispatch_async(strongSelf.engineQueue, ^{
                item.conversionProgress = fraction;
            });
        } completion:^(BOOL success, NSURL * _Nullable finalURL, NSError * _Nullable error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            dispatch_async(strongSelf.engineQueue, ^{
                [strongSelf.activeContexts removeObjectForKey:item.itemID];
                if (success && finalURL) {
                    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:finalURL.path error:nil];
                    item.totalBytes = [attrs[NSFileSize] longLongValue];
                    item.downloadedBytes = item.totalBytes;
                    item.localFilePath = finalURL.path;
                    item.filename = finalURL.lastPathComponent;
                    item.status = PDMDownloadStatusCompleted;
                    item.conversionProgress = 1.0;
                    item.completedAt = [NSDate date];
                } else {
                    item.status = PDMDownloadStatusFailed;
                    item.errorMessage = error.localizedDescription ?: @"Conversion failed";
                }
                [strongSelf saveStateLocked];
                [strongSelf updateCountersAndTimerLocked];
                [strongSelf notifyUpdateLocked];
            });
        }];
    });
    return item;
}

- (void)pumpQueueLocked {
    NSInteger maxConc = [PDMThemeManager sharedManager].maxConcurrentDownloads;
    NSInteger running = 0;
    for (PDMDownloadItem *it in self.mutableItems) {
        if ([it isActiveTransfer]) running++;
    }
    if (running >= maxConc) {
        [self updateCountersAndTimerLocked];
        return;
    }

    BOOL wifiOnly = [PDMThemeManager sharedManager].wifiOnlyDownloads;
    if (wifiOnly && ![[self class] isWiFiConnected]) {
        [self updateCountersAndTimerLocked];
        return;
    }

    for (PDMDownloadItem *it in self.mutableItems) {
        if (running >= maxConc) break;
        if (it.status == PDMDownloadStatusQueued) {
            [self beginDownloadItemLocked:it];
            running++;
        }
    }
    [self updateCountersAndTimerLocked];
}

- (void)applyHeadersFromItem:(PDMDownloadItem *)item toRequest:(NSMutableURLRequest *)req {
    if (item.referer.length > 0) [req setValue:item.referer forHTTPHeaderField:@"Referer"];
    if (item.userAgent.length > 0) [req setValue:item.userAgent forHTTPHeaderField:@"User-Agent"];
    if (item.cookieHeader.length > 0) [req setValue:item.cookieHeader forHTTPHeaderField:@"Cookie"];
}

- (void)beginDownloadItemLocked:(PDMDownloadItem *)item {
    if (self.activeContexts[item.itemID]) {
        return;
    }
    NSURL *url = [NSURL URLWithString:item.urlString];
    if (!url) {
        item.status = PDMDownloadStatusFailed;
        item.errorMessage = @"Invalid URL";
        [self saveStateLocked];
        return;
    }

    PDMActiveDownloadContext *ctx = [[PDMActiveDownloadContext alloc] initWithItemID:item.itemID];
    self.activeContexts[item.itemID] = ctx;
    [self ensureTelemetryTimerRunning];

    if (item.isHLS) {
        item.status = PDMDownloadStatusDownloading;
        [self startHLSDownloadLocked:item context:ctx];
        return;
    }

    // If segments already exist & part file exists -> Resume directly!
    if (item.supportsRange && item.segments.count > 0 && item.partFilePath.length > 0 &&
        [[NSFileManager defaultManager] fileExistsAtPath:item.partFilePath]) {
        item.status = PDMDownloadStatusDownloading;
        [self launchSegmentTasksLocked:item context:ctx];
        return;
    }

    // Probe URL with HEAD (and 1-byte Range fallback)
    item.status = PDMDownloadStatusProbing;
    item.errorMessage = nil;
    [self notifyUpdateLocked];

    NSMutableURLRequest *headReq = [NSMutableURLRequest requestWithURL:url];
    headReq.HTTPMethod = @"HEAD";
    headReq.timeoutInterval = 15.0;
    [self applyHeadersFromItem:item toRequest:headReq];

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *probeTask = [[NSURLSession sharedSession] dataTaskWithRequest:headReq
                                                                      completionHandler:^(NSData * _Nullable __unused data,
                                                                                          NSURLResponse * _Nullable response,
                                                                                          NSError * _Nullable __unused error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        dispatch_async(strongSelf.engineQueue, ^{
            if (ctx.cancelledOrPaused) return;
            int64_t contentLen = -1;
            BOOL acceptRanges = NO;
            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
                contentLen = http.expectedContentLength;
                for (NSString *k in http.allHeaderFields) {
                    NSString *lk = k.lowercaseString;
                    NSString *val = [http.allHeaderFields[k] description];
                    if ([lk isEqualToString:@"accept-ranges"] && [val.lowercaseString containsString:@"bytes"]) {
                        acceptRanges = YES;
                    } else if ([lk isEqualToString:@"content-disposition"]) {
                        NSRange fnRange = [val rangeOfString:@"filename=" options:NSCaseInsensitiveSearch];
                        if (fnRange.location != NSNotFound) {
                            NSString *raw = [[val substringFromIndex:NSMaxRange(fnRange)] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\"' ;"]];
                            if (raw.length > 0) {
                                item.filename = [PDMThemeManager sanitizeFilename:raw fallbackExtension:nil];
                            }
                        }
                    }
                }
            }

            if (contentLen > 0 && acceptRanges) {
                [strongSelf finalizeProbeForItemLocked:item context:ctx totalLength:contentLen supportsRange:YES];
                return;
            }

            // 1-byte Range fallback probe
            NSMutableURLRequest *rangeProbe = [NSMutableURLRequest requestWithURL:url];
            rangeProbe.HTTPMethod = @"GET";
            [rangeProbe setValue:@"bytes=0-0" forHTTPHeaderField:@"Range"];
            [strongSelf applyHeadersFromItem:item toRequest:rangeProbe];
            [[[NSURLSession sharedSession] dataTaskWithRequest:rangeProbe
                                             completionHandler:^(NSData * _Nullable __unused d2,
                                                                 NSURLResponse * _Nullable resp2,
                                                                 NSError * _Nullable __unused err2) {
                dispatch_async(strongSelf.engineQueue, ^{
                    if (ctx.cancelledOrPaused) return;
                    int64_t probedLen = contentLen;
                    BOOL rangeOK = NO;
                    if ([resp2 isKindOfClass:[NSHTTPURLResponse class]]) {
                        NSHTTPURLResponse *h2 = (NSHTTPURLResponse *)resp2;
                        if (h2.statusCode == 206) {
                            rangeOK = YES;
                            for (NSString *k in h2.allHeaderFields) {
                                if ([k.lowercaseString isEqualToString:@"content-range"]) {
                                    NSString *cr = [h2.allHeaderFields[k] description];
                                    NSRange slash = [cr rangeOfString:@"/"];
                                    if (slash.location != NSNotFound) {
                                        int64_t parsed = [[cr substringFromIndex:slash.location + 1] longLongValue];
                                        if (parsed > 0) probedLen = parsed;
                                    }
                                }
                            }
                        } else if (probedLen <= 0 && h2.expectedContentLength > 0) {
                            probedLen = h2.expectedContentLength;
                        }
                    }
                    [strongSelf finalizeProbeForItemLocked:item context:ctx totalLength:probedLen supportsRange:rangeOK];
                });
            }] resume];
        });
    }];
    [probeTask resume];
}

- (void)finalizeProbeForItemLocked:(PDMDownloadItem *)item
                           context:(PDMActiveDownloadContext *)ctx
                       totalLength:(int64_t)totalLen
                     supportsRange:(BOOL)supportsRange {
    if (ctx.cancelledOrPaused) return;
    item.totalBytes = totalLen;
    item.supportsRange = supportsRange;
    item.status = PDMDownloadStatusDownloading;

    if (supportsRange && totalLen >= kPDMMultiSegmentThresholdBytes && item.segmentCount > 1) {
        // Prepare .pdmpart file with POSIX open + ftruncate
        int fd = open(item.partFilePath.fileSystemRepresentation, O_CREAT | O_RDWR, 0644);
        if (fd < 0 || ftruncate(fd, (off_t)totalLen) != 0) {
            if (fd >= 0) close(fd);
            [self launchSingleFallbackDownloadLocked:item context:ctx];
            return;
        }
        ctx.fd = fd;

        [item.segments removeAllObjects];
        NSInteger parts = MAX(2, MIN(16, item.segmentCount));
        int64_t chunk = totalLen / parts;
        for (NSInteger i = 0; i < parts; i++) {
            PDMDownloadSegment *seg = [[PDMDownloadSegment alloc] init];
            seg.index = i;
            seg.startOffset = i * chunk;
            seg.endOffset = (i == parts - 1) ? (totalLen - 1) : ((i + 1) * chunk - 1);
            seg.downloadedBytes = 0;
            seg.completed = NO;
            [item.segments addObject:seg];
        }
        [self saveStateLocked];
        [self launchSegmentTasksLocked:item context:ctx];
    } else {
        item.segmentCount = 1;
        [self launchSingleFallbackDownloadLocked:item context:ctx];
    }
}

- (void)launchSegmentTasksLocked:(PDMDownloadItem *)item context:(PDMActiveDownloadContext *)ctx {
    if (ctx.fd < 0) {
        int fd = open(item.partFilePath.fileSystemRepresentation, O_CREAT | O_RDWR, 0644);
        if (fd < 0) {
            [self failItemLocked:item message:@"Unable to open partial file for resume"];
            return;
        }
        ctx.fd = fd;
    }

    NSURL *url = [NSURL URLWithString:item.urlString];
    if (!url) {
        [self failItemLocked:item message:@"Invalid URL"];
        return;
    }

    NSInteger pendingSegments = 0;
    for (PDMDownloadSegment *seg in item.segments) {
        if (seg.completed) continue;
        int64_t nextStart = seg.startOffset + seg.downloadedBytes;
        if (nextStart > seg.endOffset) {
            seg.completed = YES;
            continue;
        }
        pendingSegments++;
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
        [req setValue:[NSString stringWithFormat:@"bytes=%lld-%lld", (long long)nextStart, (long long)seg.endOffset]
   forHTTPHeaderField:@"Range"];
        [self applyHeadersFromItem:item toRequest:req];

        NSURLSessionDataTask *task = [self.transferSession dataTaskWithRequest:req];
        NSNumber *tid = @(task.taskIdentifier);
        self.taskIDToItemID[tid] = item.itemID;
        ctx.taskIDToSegmentIndex[tid] = @(seg.index);
        [ctx.tasks addObject:task];
        [task resume];
    }

    if (pendingSegments == 0) {
        [self completeDownloadedPartFileLocked:item context:ctx];
    }
    [self notifyUpdateLocked];
}

- (void)launchSingleFallbackDownloadLocked:(PDMDownloadItem *)item context:(PDMActiveDownloadContext *)ctx {
    NSURL *url = [NSURL URLWithString:item.urlString];
    if (!url) {
        [self failItemLocked:item message:@"Invalid URL"];
        return;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [self applyHeadersFromItem:item toRequest:req];
    NSURLSessionDownloadTask *task = [self.transferSession downloadTaskWithRequest:req];
    NSNumber *tid = @(task.taskIdentifier);
    self.taskIDToItemID[tid] = item.itemID;
    [ctx.tasks addObject:task];
    [task resume];
    [self notifyUpdateLocked];
}

#pragma mark - HLS Multi-Audio Segment Downloader

- (void)startHLSDownloadLocked:(PDMDownloadItem *)item context:(PDMActiveDownloadContext *)ctx {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSURL *videoPlaylistURL = [NSURL URLWithString:(item.hlsVideoVariantURL ?: item.urlString)];
        NSURL *audioPlaylistURL = (item.hlsAudioTrackURL.length > 0 && ![item.hlsAudioTrackURL isEqualToString:videoPlaylistURL.absoluteString])
            ? [NSURL URLWithString:item.hlsAudioTrackURL] : nil;

        NSURL *tmpDir = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"pdm_hls_%@", item.itemID]] isDirectory:YES];
        [[NSFileManager defaultManager] createDirectoryAtURL:tmpDir withIntermediateDirectories:YES attributes:nil error:nil];

        NSURL *rawVideoFile = [tmpDir URLByAppendingPathComponent:@"video_stream.mp4"];
        NSURL *rawAudioFile = audioPlaylistURL ? [tmpDir URLByAppendingPathComponent:@"audio_stream.m4a"] : nil;

        NSError *hlsErr = nil;
        BOOL videoIsFMP4 = NO;
        BOOL vOK = [self downloadHLSStreamFromPlaylist:videoPlaylistURL
                                             toFileURL:rawVideoFile
                                                  item:item
                                               context:ctx
                                             outIsFMP4:&videoIsFMP4
                                                 error:&hlsErr];
        if (!vOK || ctx.cancelledOrPaused) {
            [[NSFileManager defaultManager] removeItemAtURL:tmpDir error:nil];
            dispatch_async(self.engineQueue, ^{
                if (!ctx.cancelledOrPaused) {
                    [self failItemLocked:item message:(hlsErr.localizedDescription ?: @"HLS video download failed")];
                }
            });
            return;
        }
        if (!videoIsFMP4) {
            NSURL *tsURL = [tmpDir URLByAppendingPathComponent:@"video_stream.ts"];
            [[NSFileManager defaultManager] removeItemAtURL:tsURL error:nil];
            if ([[NSFileManager defaultManager] moveItemAtURL:rawVideoFile toURL:tsURL error:nil]) {
                rawVideoFile = tsURL;
            }
        }

        if (audioPlaylistURL && rawAudioFile) {
            BOOL audioIsFMP4 = NO;
            BOOL aOK = [self downloadHLSStreamFromPlaylist:audioPlaylistURL
                                                 toFileURL:rawAudioFile
                                                      item:item
                                                   context:ctx
                                                 outIsFMP4:&audioIsFMP4
                                                     error:&hlsErr];
            if (!aOK || ctx.cancelledOrPaused) {
                [[NSFileManager defaultManager] removeItemAtURL:tmpDir error:nil];
                dispatch_async(self.engineQueue, ^{
                    if (!ctx.cancelledOrPaused) {
                        [self failItemLocked:item message:(hlsErr.localizedDescription ?: @"HLS audio download failed")];
                    }
                });
                return;
            }
            if (!audioIsFMP4) {
                NSURL *aacURL = [tmpDir URLByAppendingPathComponent:@"audio_stream.aac"];
                [[NSFileManager defaultManager] removeItemAtURL:aacURL error:nil];
                if ([[NSFileManager defaultManager] moveItemAtURL:rawAudioFile toURL:aacURL error:nil]) {
                    rawAudioFile = aacURL;
                }
            }
        }

        // Mux video + audio via AVAssetExportSession
        dispatch_async(self.engineQueue, ^{
            item.status = PDMDownloadStatusMuxing;
            item.conversionProgress = 0.0;
            [self notifyUpdateLocked];
        });

        NSURL *muxedURL = [tmpDir URLByAppendingPathComponent:@"muxed.mp4"];
        dispatch_semaphore_t muxSem = dispatch_semaphore_create(0);
        __block BOOL muxSuccess = NO;
        __block NSError *muxError = nil;

        ctx.transcodeJob = [[PDMTranscoder sharedTranscoder] muxVideoURL:rawVideoFile
                                                                audioURL:rawAudioFile
                                                             toOutputURL:muxedURL
                                                                progress:^(double fraction) {
            dispatch_async(self.engineQueue, ^{
                item.conversionProgress = fraction;
            });
        } completion:^(BOOL success, NSURL * _Nullable __unused finalURL, NSError * _Nullable error) {
            muxSuccess = success;
            muxError = error;
            dispatch_semaphore_signal(muxSem);
        }];
        dispatch_semaphore_wait(muxSem, DISPATCH_TIME_FOREVER);

        NSURL *assembledSource = muxSuccess ? muxedURL : rawVideoFile;
        dispatch_async(self.engineQueue, ^{
            if (ctx.cancelledOrPaused || ctx.finalizing) {
                [[NSFileManager defaultManager] removeItemAtURL:tmpDir error:nil];
                return;
            }
            ctx.finalizing = YES;
            if (!muxSuccess && ![[NSFileManager defaultManager] fileExistsAtPath:assembledSource.path]) {
                [[NSFileManager defaultManager] removeItemAtURL:tmpDir error:nil];
                [self failItemLocked:item message:(muxError.localizedDescription ?: @"HLS muxing failed")];
                return;
            }
            [self finalizeOrAutoConvertFileAtURL:assembledSource cleanupDirectory:tmpDir forItemLocked:item context:ctx];
        });
    });
}

- (nullable NSData *)syncFetchURL:(NSURL *)url item:(PDMDownloadItem *)item {
    if (!url) return nil;
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 25.0;
    [self applyHeadersFromItem:item toRequest:req];
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSData *outData = nil;
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable __unused response, NSError * _Nullable __unused error) {
        outData = data;
        dispatch_semaphore_signal(sem);
    }] resume];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    return outData;
}

- (BOOL)downloadHLSStreamFromPlaylist:(NSURL *)playlistURL
                            toFileURL:(NSURL *)outFileURL
                                 item:(PDMDownloadItem *)item
                              context:(PDMActiveDownloadContext *)ctx
                            outIsFMP4:(BOOL *)outIsFMP4
                                error:(NSError **)outError {
    if (outIsFMP4) *outIsFMP4 = NO;
    NSData *plData = [self syncFetchURL:playlistURL item:item];
    if (plData.length == 0) {
        if (outError) *outError = [NSError errorWithDomain:@"com.prismdm.hls" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Could not fetch HLS playlist."}];
        return NO;
    }
    NSString *text = [[NSString alloc] initWithData:plData encoding:NSUTF8StringEncoding];
    NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];

    // If this is a master playlist, follow the highest-bandwidth media playlist automatically
    if ([text containsString:@"#EXT-X-STREAM-INF:"]) {
        NSURL *bestVariantURL = nil;
        int64_t bestBW = -1;
        int64_t pendingBW = 0;
        BOOL nextIsVariant = NO;
        for (NSString *rawLine in lines) {
            NSString *line = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (line.length == 0) continue;
            if ([line hasPrefix:@"#EXT-X-STREAM-INF:"]) {
                pendingBW = 0;
                NSRange bwRange = [line rangeOfString:@"BANDWIDTH="];
                if (bwRange.location != NSNotFound) {
                    pendingBW = [[line substringFromIndex:NSMaxRange(bwRange)] longLongValue];
                }
                nextIsVariant = YES;
            } else if (nextIsVariant && ![line hasPrefix:@"#"]) {
                NSURL *vU = [NSURL URLWithString:line relativeToURL:playlistURL].absoluteURL;
                if (vU && pendingBW >= bestBW) {
                    bestBW = pendingBW;
                    bestVariantURL = vU;
                }
                nextIsVariant = NO;
            }
        }
        if (bestVariantURL && ![bestVariantURL.absoluteString isEqualToString:playlistURL.absoluteString]) {
            return [self downloadHLSStreamFromPlaylist:bestVariantURL toFileURL:outFileURL item:item context:ctx outIsFMP4:outIsFMP4 error:outError];
        }
    }

    NSMutableArray<NSURL *> *segURLs = [NSMutableArray array];
    NSURL *mapInitURL = nil;
    NSData *aesKey = nil;
    NSData *explicitIV = nil;
    int64_t mediaSeq = 0;

    for (NSString *rawLine in lines) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (line.length == 0) continue;
        if ([line hasPrefix:@"#EXT-X-MEDIA-SEQUENCE:"]) {
            mediaSeq = [[line substringFromIndex:22] longLongValue];
        } else if ([line hasPrefix:@"#EXT-X-MAP:"]) {
            NSRange uriRange = [line rangeOfString:@"URI=\""];
            if (uriRange.location != NSNotFound) {
                NSString *rest = [line substringFromIndex:NSMaxRange(uriRange)];
                NSRange endQ = [rest rangeOfString:@"\""];
                if (endQ.location != NSNotFound) {
                    NSString *mapStr = [rest substringToIndex:endQ.location];
                    mapInitURL = [NSURL URLWithString:mapStr relativeToURL:playlistURL].absoluteURL;
                }
            }
        } else if ([line hasPrefix:@"#EXT-X-KEY:"]) {
            if ([line containsString:@"METHOD=AES-128"]) {
                NSRange uriRange = [line rangeOfString:@"URI=\""];
                if (uriRange.location != NSNotFound) {
                    NSString *rest = [line substringFromIndex:NSMaxRange(uriRange)];
                    NSRange endQ = [rest rangeOfString:@"\""];
                    if (endQ.location != NSNotFound) {
                        NSString *keyStr = [rest substringToIndex:endQ.location];
                        NSURL *keyURL = [NSURL URLWithString:keyStr relativeToURL:playlistURL].absoluteURL;
                        if (keyURL) {
                            aesKey = [self syncFetchURL:keyURL item:item];
                        }
                    }
                }
                NSRange ivRange = [line rangeOfString:@"IV=0x" options:NSCaseInsensitiveSearch];
                if (ivRange.location != NSNotFound) {
                    NSString *hex = [[line substringFromIndex:NSMaxRange(ivRange)] componentsSeparatedByString:@","].firstObject;
                    NSMutableData *ivBytes = [NSMutableData dataWithCapacity:16];
                    for (NSUInteger c = 0; c + 1 < hex.length && ivBytes.length < 16; c += 2) {
                        unsigned int bVal = 0;
                        NSScanner *sc = [NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(c, 2)]];
                        [sc scanHexInt:&bVal];
                        uint8_t byte = (uint8_t)bVal;
                        [ivBytes appendBytes:&byte length:1];
                    }
                    explicitIV = ivBytes;
                }
            }
        } else if (![line hasPrefix:@"#"]) {
            NSURL *segU = [NSURL URLWithString:line relativeToURL:playlistURL].absoluteURL;
            if (segU) [segURLs addObject:segU];
        }
    }

    if (segURLs.count == 0) {
        if (outError) *outError = [NSError errorWithDomain:@"com.prismdm.hls" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"No media segments found in HLS playlist."}];
        return NO;
    }

    int fd = open(outFileURL.fileSystemRepresentation, O_CREAT | O_WRONLY | O_TRUNC, 0644);
    if (fd < 0) {
        if (outError) *outError = [NSError errorWithDomain:@"com.prismdm.hls" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"Unable to create temporary HLS output file."}];
        return NO;
    }

    BOOL detectedFMP4 = (mapInitURL != nil);
    if (mapInitURL) {
        NSData *initData = [self syncFetchURL:mapInitURL item:item];
        if (initData.length > 0) {
            ssize_t wr = write(fd, initData.bytes, initData.length);
            (void)wr;
        }
    }

    NSUInteger totalSegs = segURLs.count;
    for (NSUInteger i = 0; i < totalSegs; i++) {
        if (ctx.cancelledOrPaused) {
            close(fd);
            return NO;
        }
        NSData *segData = [self syncFetchURL:segURLs[i] item:item];
        if (!segData) continue;
        if (aesKey.length == 16) {
            NSData *ivToUse = explicitIV;
            if (!ivToUse) {
                uint8_t seqIV[16];
                memset(seqIV, 0, sizeof(seqIV));
                uint64_t seqVal = (uint64_t)(mediaSeq + (int64_t)i);
                for (int b = 0; b < 8; b++) {
                    seqIV[15 - b] = (uint8_t)((seqVal >> (b * 8)) & 0xFFU);
                }
                ivToUse = [NSData dataWithBytes:seqIV length:16];
            }
            NSData *dec = [PDMTranscoder decryptAES128Data:segData key:aesKey iv:ivToUse];
            if (dec) segData = dec;
        }
        if (i == 0 && !detectedFMP4 && segData.length >= 8) {
            const uint8_t *b = (const uint8_t *)segData.bytes;
            if ((b[4] == 'f' && b[5] == 't' && b[6] == 'y' && b[7] == 'p') ||
                (b[4] == 's' && b[5] == 't' && b[6] == 'y' && b[7] == 'p')) {
                detectedFMP4 = YES;
            }
        }
        if (segData.length > 0) {
            ssize_t wr = write(fd, segData.bytes, segData.length);
            (void)wr;
            int64_t addBytes = (int64_t)segData.length;
            dispatch_async(self.engineQueue, ^{
                item.downloadedBytes += addBytes;
                item.totalBytes = MAX(item.downloadedBytes, (int64_t)((double)item.downloadedBytes * (double)totalSegs / (double)(i + 1)));
                ctx.bytesInWindow += addBytes;
            });
        }
    }

    fsync(fd);
    close(fd);
    if (outIsFMP4) *outIsFMP4 = detectedFMP4;
    return YES;
}

#pragma mark - NSURLSession Delegates

- (void)URLSession:(NSURLSession *__unused)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    NSNumber *tid = @(dataTask.taskIdentifier);
    NSString *itemID = self.taskIDToItemID[tid];
    PDMActiveDownloadContext *ctx = itemID ? self.activeContexts[itemID] : nil;
    PDMDownloadItem *item = itemID ? [self itemForIDLocked:itemID] : nil;

    if (!ctx || !item || ctx.cancelledOrPaused) {
        completionHandler(NSURLSessionResponseCancel);
        return;
    }

    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSInteger statusCode = ((NSHTTPURLResponse *)response).statusCode;
        if (statusCode >= 400) {
            completionHandler(NSURLSessionResponseCancel);
            [self failItemLocked:item message:[NSString stringWithFormat:@"Server returned HTTP %ld", (long)statusCode]];
            return;
        }
        // If server ignored Range header and sent HTTP 200 for a multi-segment part, switch cleanly to single stream
        if (ctx.taskIDToSegmentIndex[tid] != nil && statusCode != 206) {
            completionHandler(NSURLSessionResponseCancel);
            if (!ctx.fellBackToSingle) {
                ctx.fellBackToSingle = YES;
                NSArray<NSURLSessionTask *> *oldTasks = [ctx.tasks copy];
                [ctx.tasks removeAllObjects];
                [ctx.taskIDToSegmentIndex removeAllObjects];
                for (NSURLSessionTask *t in oldTasks) {
                    [self.taskIDToItemID removeObjectForKey:@(t.taskIdentifier)];
                    if (t != dataTask) {
                        [t cancel];
                    }
                }
                [ctx closeFileDescriptor];
                [item.segments removeAllObjects];
                item.supportsRange = NO;
                item.segmentCount = 1;
                item.downloadedBytes = 0;
                [self launchSingleFallbackDownloadLocked:item context:ctx];
            }
            return;
        }
    }

    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *__unused)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    NSNumber *tid = @(dataTask.taskIdentifier);
    NSString *itemID = self.taskIDToItemID[tid];
    if (!itemID) return;

    PDMActiveDownloadContext *ctx = self.activeContexts[itemID];
    PDMDownloadItem *item = [self itemForIDLocked:itemID];
    if (!ctx || !item || ctx.cancelledOrPaused || ctx.finalizing) return;

    NSNumber *segIdxNum = ctx.taskIDToSegmentIndex[tid];
    if (!segIdxNum) return;
    NSInteger segIdx = segIdxNum.integerValue;
    if (segIdx < 0 || segIdx >= (NSInteger)item.segments.count) return;
    PDMDownloadSegment *seg = item.segments[(NSUInteger)segIdx];

    int64_t writeOffset = seg.startOffset + seg.downloadedBytes;
    const void *bytes = data.bytes;
    size_t len = data.length;

    if (ctx.fd >= 0 && len > 0) {
        size_t writtenTotal = 0;
        while (writtenTotal < len) {
            ssize_t w = pwrite(ctx.fd, (const uint8_t *)bytes + writtenTotal, len - writtenTotal, (off_t)(writeOffset + (int64_t)writtenTotal));
            if (w <= 0) break;
            writtenTotal += (size_t)w;
        }
        seg.downloadedBytes += (int64_t)writtenTotal;
        item.downloadedBytes += (int64_t)writtenTotal;
        ctx.bytesInWindow += (int64_t)writtenTotal;
    }

    // Optional Speed Limiter (Unlimited by default when speedLimitMBps == 0)
    NSInteger limitMB = [PDMThemeManager sharedManager].speedLimitMBps;
    if (limitMB > 0) {
        int64_t maxBytesPerSec = (int64_t)limitMB * 1024LL * 1024LL;
        CFTimeInterval now = CFAbsoluteTimeGetCurrent();
        if (now - self.throttleWindowStart >= 1.0) {
            self.throttleWindowStart = now;
            self.throttleBytesThisSecond = 0;
        }
        self.throttleBytesThisSecond += (int64_t)len;
        if (self.throttleBytesThisSecond > maxBytesPerSec) {
            double sleepSec = MAX(0.02, 1.0 - (now - self.throttleWindowStart));
            usleep((useconds_t)(sleepSec * 1000000.0));
        }
    }
}

- (void)URLSession:(NSURLSession *__unused)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    NSNumber *tid = @(downloadTask.taskIdentifier);
    NSString *itemID = self.taskIDToItemID[tid];
    if (!itemID) return;
    PDMActiveDownloadContext *ctx = self.activeContexts[itemID];
    PDMDownloadItem *item = [self itemForIDLocked:itemID];
    if (!ctx || !item || ctx.cancelledOrPaused || ctx.finalizing) return;

    item.downloadedBytes = totalBytesWritten;
    if (totalBytesExpectedToWrite > 0) {
        item.totalBytes = totalBytesExpectedToWrite;
    }
    ctx.bytesInWindow += bytesWritten;
}

- (void)URLSession:(NSURLSession *__unused)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {
    NSNumber *tid = @(downloadTask.taskIdentifier);
    NSString *itemID = self.taskIDToItemID[tid];
    if (!itemID) return;
    PDMActiveDownloadContext *ctx = self.activeContexts[itemID];
    PDMDownloadItem *item = [self itemForIDLocked:itemID];
    if (!ctx || !item || ctx.cancelledOrPaused || ctx.finalizing) return;

    if ([downloadTask.response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSInteger statusCode = ((NSHTTPURLResponse *)downloadTask.response).statusCode;
        if (statusCode >= 400) {
            [self failItemLocked:item message:[NSString stringWithFormat:@"Server returned HTTP %ld", (long)statusCode]];
            return;
        }
    }

    if (item.partFilePath.length == 0) {
        NSURL *partDir = [[[self class] downloadsBaseDirectory] URLByAppendingPathComponent:@".parts" isDirectory:YES];
        [[NSFileManager defaultManager] createDirectoryAtURL:partDir withIntermediateDirectories:YES attributes:nil error:nil];
        item.partFilePath = [partDir URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.pdmpart", item.itemID]].path;
    } else {
        NSString *parentDir = [item.partFilePath stringByDeletingLastPathComponent];
        if (parentDir.length > 0) {
            [[NSFileManager defaultManager] createDirectoryAtPath:parentDir withIntermediateDirectories:YES attributes:nil error:nil];
        }
    }

    // Move temporary file to part path immediately before delegate returns
    [[NSFileManager defaultManager] removeItemAtPath:item.partFilePath error:nil];
    NSError *mvErr = nil;
    [[NSFileManager defaultManager] moveItemAtURL:location toURL:[NSURL fileURLWithPath:item.partFilePath] error:&mvErr];
    if (mvErr) {
        [self failItemLocked:item message:mvErr.localizedDescription];
        return;
    }
    [self completeDownloadedPartFileLocked:item context:ctx];
}

- (void)URLSession:(NSURLSession *__unused)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(nullable NSError *)error {
    NSNumber *tid = @(task.taskIdentifier);
    NSString *itemID = self.taskIDToItemID[tid];
    [self.taskIDToItemID removeObjectForKey:tid];
    if (!itemID) return;

    PDMActiveDownloadContext *ctx = self.activeContexts[itemID];
    PDMDownloadItem *item = [self itemForIDLocked:itemID];
    if (!ctx || !item) return;

    [ctx.tasks removeObject:task];
    NSNumber *segIdxNum = ctx.taskIDToSegmentIndex[tid];
    [ctx.taskIDToSegmentIndex removeObjectForKey:tid];

    if (ctx.cancelledOrPaused || ctx.finalizing) {
        return;
    }

    if (error) {
        if (error.code == NSURLErrorCancelled) return;
        [self failItemLocked:item message:error.localizedDescription];
        return;
    }

    if (segIdxNum) {
        NSInteger segIdx = segIdxNum.integerValue;
        if (segIdx >= 0 && segIdx < (NSInteger)item.segments.count) {
            item.segments[(NSUInteger)segIdx].completed = YES;
        }
        BOOL allDone = (item.segments.count > 0);
        for (PDMDownloadSegment *seg in item.segments) {
            if (!seg.completed) {
                allDone = NO;
                break;
            }
        }
        if (allDone) {
            [self completeDownloadedPartFileLocked:item context:ctx];
        } else {
            [self saveStateLocked];
        }
    }
}

#pragma mark - Completion & Auto-Conversion Pipeline

- (void)completeDownloadedPartFileLocked:(PDMDownloadItem *)item context:(PDMActiveDownloadContext *)ctx {
    if (ctx.finalizing || ctx.cancelledOrPaused) return;
    ctx.finalizing = YES;
    [ctx closeFileDescriptor];
    if (item.partFilePath.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:item.partFilePath]) {
        [self failItemLocked:item message:@"Downloaded file is missing from disk."];
        return;
    }
    NSURL *partURL = [NSURL fileURLWithPath:item.partFilePath];
    [self finalizeOrAutoConvertFileAtURL:partURL cleanupDirectory:nil forItemLocked:item context:ctx];
}

- (void)finalizeOrAutoConvertFileAtURL:(NSURL *)downloadedURL
                      cleanupDirectory:(nullable NSURL *)cleanupDir
                         forItemLocked:(PDMDownloadItem *)item
                               context:(PDMActiveDownloadContext *)ctx {
    BOOL needsConvert = [[PDMTranscoder sharedTranscoder] needsConversionForInputURL:downloadedURL config:item.formatConfig];
    if (!needsConvert) {
        NSURL *finalURL = [self uniqueDestinationURLForFilename:item.filename
                                                       category:item.category
                                                 isPrivateVault:item.isPrivateVault];
        NSError *mvErr = nil;
        [[NSFileManager defaultManager] removeItemAtURL:finalURL error:nil];
        [[NSFileManager defaultManager] moveItemAtURL:downloadedURL toURL:finalURL error:&mvErr];
        if (cleanupDir) {
            [[NSFileManager defaultManager] removeItemAtURL:cleanupDir error:nil];
        }
        [self.activeContexts removeObjectForKey:item.itemID];
        if (mvErr) {
            item.status = PDMDownloadStatusFailed;
            item.errorMessage = mvErr.localizedDescription;
        } else {
            NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:finalURL.path error:nil];
            int64_t fSize = [attrs[NSFileSize] longLongValue];
            if (fSize > 0) {
                item.totalBytes = fSize;
                item.downloadedBytes = fSize;
            }
            item.localFilePath = finalURL.path;
            item.filename = finalURL.lastPathComponent;
            item.status = PDMDownloadStatusCompleted;
            item.speedBytesPerSec = 0.0;
            item.etaSeconds = 0.0;
            item.completedAt = [NSDate date];
            [[PDMPrivacyShieldEngine sharedEngine] recordDownloadCompletedWithBytes:item.totalBytes];
        }
        [self saveStateLocked];
        [self pumpQueueLocked];
        [self notifyUpdateLocked];
        return;
    }

    // Rename .pdmpart to a proper media extension so AVURLAsset can always parse it cleanly
    NSURL *transcodeInputURL = downloadedURL;
    if ([downloadedURL.pathExtension.lowercaseString isEqualToString:@"pdmpart"] || downloadedURL.pathExtension.length == 0) {
        NSString *realExt = item.filename.pathExtension.lowercaseString;
        if (realExt.length == 0 || [realExt isEqualToString:@"pdmpart"] || [realExt isEqualToString:@"bin"]) {
            realExt = @"mp4";
        }
        NSURL *renamedURL = [[downloadedURL URLByDeletingPathExtension] URLByAppendingPathExtension:realExt];
        [[NSFileManager defaultManager] removeItemAtURL:renamedURL error:nil];
        if ([[NSFileManager defaultManager] moveItemAtURL:downloadedURL toURL:renamedURL error:nil]) {
            transcodeInputURL = renamedURL;
        }
    }

    // Automatic Post-Download Format & Encoding Conversion
    item.status = PDMDownloadStatusConverting;
    item.conversionProgress = 0.0;
    item.speedBytesPerSec = 0.0;
    item.etaSeconds = 0.0;
    [self notifyUpdateLocked];

    NSString *targetExt = [item.formatConfig targetFileExtension];
    NSString *outBase = [item.filename stringByDeletingPathExtension];
    if (outBase.length == 0) outBase = @"PrismDM_Media";
    NSString *convertedName = (targetExt.length > 0)
        ? [outBase stringByAppendingPathExtension:targetExt]
        : item.filename;
    NSString *finalCat = item.isPrivateVault ? @"Private Vault" : [PDMThemeManager categoryForFilename:convertedName mimeType:nil];
    NSURL *convertedURL = [self uniqueDestinationURLForFilename:convertedName
                                                       category:finalCat
                                                 isPrivateVault:item.isPrivateVault];

    // If user enabled "Keep Original File", save original copy first
    if ([PDMThemeManager sharedManager].keepOriginalAfterConvert) {
        NSURL *origDest = [self uniqueDestinationURLForFilename:item.filename
                                                       category:item.category
                                                 isPrivateVault:item.isPrivateVault];
        [[NSFileManager defaultManager] copyItemAtURL:transcodeInputURL toURL:origDest error:nil];
    }

    __weak typeof(self) weakSelf = self;
    ctx.transcodeJob = [[PDMTranscoder sharedTranscoder] transcodeFileAtURL:transcodeInputURL
                                                                toOutputURL:convertedURL
                                                                     config:item.formatConfig
                                                                   progress:^(double fraction) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        dispatch_async(strongSelf.engineQueue, ^{
            item.conversionProgress = fraction;
        });
    } completion:^(BOOL success, NSURL * _Nullable finalURL, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        dispatch_async(strongSelf.engineQueue, ^{
            [[NSFileManager defaultManager] removeItemAtURL:transcodeInputURL error:nil];
            if (cleanupDir) {
                [[NSFileManager defaultManager] removeItemAtURL:cleanupDir error:nil];
            }
            [strongSelf.activeContexts removeObjectForKey:item.itemID];
            if (success && finalURL) {
                NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:finalURL.path error:nil];
                int64_t fSize = [attrs[NSFileSize] longLongValue];
                if (fSize > 0) {
                    item.totalBytes = fSize;
                    item.downloadedBytes = fSize;
                }
                item.localFilePath = finalURL.path;
                item.filename = finalURL.lastPathComponent;
                item.category = finalCat;
                item.status = PDMDownloadStatusCompleted;
                item.conversionProgress = 1.0;
                item.completedAt = [NSDate date];
                [[PDMPrivacyShieldEngine sharedEngine] recordDownloadCompletedWithBytes:item.totalBytes];
            } else {
                item.status = PDMDownloadStatusFailed;
                item.errorMessage = error.localizedDescription ?: @"Post-download conversion failed";
            }
            [strongSelf saveStateLocked];
            [strongSelf pumpQueueLocked];
            [strongSelf notifyUpdateLocked];
        });
    }];
}

- (void)failItemLocked:(PDMDownloadItem *)item message:(NSString *)message {
    PDMActiveDownloadContext *ctx = self.activeContexts[item.itemID];
    if (ctx) {
        ctx.cancelledOrPaused = YES;
        for (NSURLSessionTask *t in ctx.tasks) {
            [t cancel];
        }
        [ctx.transcodeJob cancel];
        [ctx closeFileDescriptor];
        [self.activeContexts removeObjectForKey:item.itemID];
    }
    item.status = PDMDownloadStatusFailed;
    item.errorMessage = message;
    item.speedBytesPerSec = 0.0;
    item.etaSeconds = 0.0;
    [self saveStateLocked];
    [self pumpQueueLocked];
    [self notifyUpdateLocked];
}

#pragma mark - Controls (Pause, Resume, Retry, Cancel, Delete, Refresh Address)

- (void)startItemWithID:(NSString *)itemID {
    [self resumeItemWithID:itemID];
}

- (void)pauseItemWithID:(NSString *)itemID {
    dispatch_async(self.engineQueue, ^{
        PDMDownloadItem *item = [self itemForIDLocked:itemID];
        if (!item) return;
        PDMActiveDownloadContext *ctx = self.activeContexts[itemID];
        if (ctx) {
            ctx.cancelledOrPaused = YES;
            for (NSURLSessionTask *t in ctx.tasks) {
                [t cancel];
            }
            [ctx.transcodeJob cancel];
            [ctx closeFileDescriptor];
            [self.activeContexts removeObjectForKey:itemID];
        }
        if (item.status != PDMDownloadStatusCompleted) {
            item.status = PDMDownloadStatusPaused;
            item.speedBytesPerSec = 0.0;
            item.etaSeconds = 0.0;
        }
        [self saveStateLocked];
        [self pumpQueueLocked];
        [self notifyUpdateLocked];
    });
}

- (void)resumeItemWithID:(NSString *)itemID {
    dispatch_async(self.engineQueue, ^{
        PDMDownloadItem *item = [self itemForIDLocked:itemID];
        if (!item) return;
        if (item.status == PDMDownloadStatusPaused || item.status == PDMDownloadStatusFailed || item.status == PDMDownloadStatusCanceled) {
            item.status = PDMDownloadStatusQueued;
            item.errorMessage = nil;
            [self saveStateLocked];
            [self pumpQueueLocked];
            [self notifyUpdateLocked];
        }
    });
}

- (void)retryItemWithID:(NSString *)itemID {
    dispatch_async(self.engineQueue, ^{
        PDMDownloadItem *item = [self itemForIDLocked:itemID];
        if (!item) return;
        item.errorMessage = nil;
        item.status = PDMDownloadStatusQueued;
        [self saveStateLocked];
        [self pumpQueueLocked];
        [self notifyUpdateLocked];
    });
}

- (void)cancelItemWithID:(NSString *)itemID {
    dispatch_async(self.engineQueue, ^{
        PDMDownloadItem *item = [self itemForIDLocked:itemID];
        if (!item) return;
        PDMActiveDownloadContext *ctx = self.activeContexts[itemID];
        if (ctx) {
            ctx.cancelledOrPaused = YES;
            for (NSURLSessionTask *t in ctx.tasks) {
                [t cancel];
            }
            [ctx.transcodeJob cancel];
            [ctx closeFileDescriptor];
            [self.activeContexts removeObjectForKey:itemID];
        }
        if (item.partFilePath.length > 0) {
            [[NSFileManager defaultManager] removeItemAtPath:item.partFilePath error:nil];
        }
        [item.segments removeAllObjects];
        item.downloadedBytes = 0;
        item.speedBytesPerSec = 0.0;
        item.etaSeconds = 0.0;
        item.status = PDMDownloadStatusCanceled;
        [self saveStateLocked];
        [self pumpQueueLocked];
        [self notifyUpdateLocked];
    });
}

- (void)deleteItemWithID:(NSString *)itemID removeLocalFile:(BOOL)removeLocalFile {
    dispatch_async(self.engineQueue, ^{
        PDMDownloadItem *item = [self itemForIDLocked:itemID];
        if (!item) return;
        PDMActiveDownloadContext *ctx = self.activeContexts[itemID];
        if (ctx) {
            ctx.cancelledOrPaused = YES;
            for (NSURLSessionTask *t in ctx.tasks) {
                [t cancel];
            }
            [ctx.transcodeJob cancel];
            [ctx closeFileDescriptor];
            [self.activeContexts removeObjectForKey:itemID];
        }
        if (item.partFilePath.length > 0) {
            [[NSFileManager defaultManager] removeItemAtPath:item.partFilePath error:nil];
        }
        if (removeLocalFile && item.localFilePath.length > 0) {
            [[NSFileManager defaultManager] removeItemAtPath:item.localFilePath error:nil];
        }
        [self.mutableItems removeObject:item];
        [self saveStateLocked];
        [self pumpQueueLocked];
        [self notifyUpdateLocked];
    });
}

- (void)refreshDownloadAddressForItemID:(NSString *)itemID
                              newURLStr:(NSString *)newURLString
                                referer:(nullable NSString *)referer
                           cookieHeader:(nullable NSString *)cookieHeader {
    dispatch_async(self.engineQueue, ^{
        PDMDownloadItem *item = [self itemForIDLocked:itemID];
        if (!item || newURLString.length == 0) return;
        // Pause existing tasks while preserving .pdmpart and segment offsets!
        PDMActiveDownloadContext *ctx = self.activeContexts[itemID];
        if (ctx) {
            ctx.cancelledOrPaused = YES;
            for (NSURLSessionTask *t in ctx.tasks) {
                [t cancel];
            }
            [ctx closeFileDescriptor];
            [self.activeContexts removeObjectForKey:itemID];
        }
        item.urlString = newURLString;
        if (referer.length > 0) item.referer = referer;
        if (cookieHeader.length > 0) item.cookieHeader = cookieHeader;
        item.errorMessage = nil;
        item.status = PDMDownloadStatusQueued;
        [self saveStateLocked];
        [self pumpQueueLocked];
        [self notifyUpdateLocked];
    });
}

#pragma mark - Zero Idle Drain Telemetry Timer

- (void)ensureTelemetryTimerRunning {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.telemetryTimer) {
            __weak typeof(self) weakSelf = self;
            self.telemetryTimer = [NSTimer scheduledTimerWithTimeInterval:0.65 repeats:YES block:^(NSTimer *__unused timer) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;
                dispatch_async(strongSelf.engineQueue, ^{
                    [strongSelf sampleTelemetryLocked];
                });
            }];
        }
    });
}

- (void)sampleTelemetryLocked {
    CFTimeInterval now = CFAbsoluteTimeGetCurrent();
    double aggSpeed = 0.0;
    NSInteger active = 0;
    NSInteger queued = 0;

    for (PDMDownloadItem *it in self.mutableItems) {
        if ([it isActiveTransfer]) {
            active++;
            PDMActiveDownloadContext *ctx = self.activeContexts[it.itemID];
            if (ctx && it.status == PDMDownloadStatusDownloading) {
                double dt = MAX(0.2, now - ctx.lastSampleTime);
                double instant = (double)ctx.bytesInWindow / dt;
                it.speedBytesPerSec = (it.speedBytesPerSec > 0.0) ? (it.speedBytesPerSec * 0.4 + instant * 0.6) : instant;
                ctx.bytesInWindow = 0;
                ctx.lastSampleTime = now;
                if (it.totalBytes > it.downloadedBytes && it.speedBytesPerSec > 10.0) {
                    it.etaSeconds = (double)(it.totalBytes - it.downloadedBytes) / it.speedBytesPerSec;
                } else {
                    it.etaSeconds = 0.0;
                }
                aggSpeed += it.speedBytesPerSec;
            }
        } else if (it.status == PDMDownloadStatusQueued) {
            queued++;
        }
    }

    self.aggregateSpeedBytesPerSec = aggSpeed;
    self.activeCount = active;
    self.queuedCount = queued;

    if (active == 0 && queued == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.telemetryTimer invalidate];
            self.telemetryTimer = nil;
        });
    }
    [self notifyUpdateLocked];
}

- (void)updateCountersAndTimerLocked {
    NSInteger active = 0;
    NSInteger queued = 0;
    for (PDMDownloadItem *it in self.mutableItems) {
        if ([it isActiveTransfer]) active++;
        else if (it.status == PDMDownloadStatusQueued) queued++;
    }
    self.activeCount = active;
    self.queuedCount = queued;
    if (active == 0 && queued == 0) {
        self.aggregateSpeedBytesPerSec = 0.0;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.telemetryTimer invalidate];
            self.telemetryTimer = nil;
        });
    } else {
        [self ensureTelemetryTimerRunning];
    }
}

- (void)notifyUpdateLocked {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:PDMDownloadsDidUpdateNotification object:self];
    });
}

@end

#pragma mark - PDMDownloadCardCell

@interface PDMDownloadCardCell : UITableViewCell
@property (nonatomic, strong) PDMGlassView *cardGlass;
@property (nonatomic, strong) PDMGlassView *iconBadge;
@property (nonatomic, strong) UIImageView *typeIcon;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *metaPillLabel;
@property (nonatomic, strong) PDMSegmentProgressView *segmentBar;
@property (nonatomic, strong) UILabel *telemetryLabel;
@property (nonatomic, strong) PDMGlassPillButton *primaryActionBtn;
@property (nonatomic, strong) PDMGlassPillButton *moreActionBtn;
@property (nonatomic, copy, nullable) dispatch_block_t onPrimaryTap;
@property (nonatomic, copy, nullable) dispatch_block_t onMoreTap;
- (void)configureWithItem:(PDMDownloadItem *)item;
@end

@implementation PDMDownloadCardCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(nullable NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _cardGlass = [[PDMGlassView alloc] initWithCornerRadius:20.0 elevated:NO];
        _cardGlass.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_cardGlass];

        _iconBadge = [[PDMGlassView alloc] initWithCornerRadius:14.0 elevated:NO];
        _iconBadge.showAmbientShadow = NO;
        _iconBadge.translatesAutoresizingMaskIntoConstraints = NO;

        _typeIcon = [[UIImageView alloc] init];
        _typeIcon.contentMode = UIViewContentModeScaleAspectFit;
        _typeIcon.translatesAutoresizingMaskIntoConstraints = NO;
        [_iconBadge.contentView addSubview:_typeIcon];

        _nameLabel = [[UILabel alloc] init];
        _nameLabel.font = [[PDMThemeManager sharedManager] bodyFontOfSize:14.5 weight:UIFontWeightBold];
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

        _metaPillLabel = [[UILabel alloc] init];
        _metaPillLabel.font = [[PDMThemeManager sharedManager] tabularFontOfSize:11.0 weight:UIFontWeightSemibold];
        _metaPillLabel.lineBreakMode = NSLineBreakByTruncatingTail;

        _primaryActionBtn = [[PDMGlassPillButton alloc] initWithTitle:nil symbolName:@"pause.fill"];
        _primaryActionBtn.horizontalPadding = 10.0;
        _primaryActionBtn.verticalPadding = 8.0;
        [_primaryActionBtn addTarget:self action:@selector(handlePrimary) forControlEvents:UIControlEventTouchUpInside];

        _moreActionBtn = [[PDMGlassPillButton alloc] initWithTitle:nil symbolName:@"ellipsis"];
        _moreActionBtn.horizontalPadding = 10.0;
        _moreActionBtn.verticalPadding = 8.0;
        [_moreActionBtn addTarget:self action:@selector(handleMore) forControlEvents:UIControlEventTouchUpInside];

        UIStackView *titleStack = [[UIStackView alloc] initWithArrangedSubviews:@[_nameLabel, _metaPillLabel]];
        titleStack.axis = UILayoutConstraintAxisVertical;
        titleStack.spacing = 3.0;

        UIStackView *topRow = [[UIStackView alloc] initWithArrangedSubviews:@[_iconBadge, titleStack, _primaryActionBtn, _moreActionBtn]];
        topRow.axis = UILayoutConstraintAxisHorizontal;
        topRow.alignment = UIStackViewAlignmentCenter;
        topRow.spacing = 10.0;

        _segmentBar = [[PDMSegmentProgressView alloc] init];
        _segmentBar.translatesAutoresizingMaskIntoConstraints = NO;
        [_segmentBar.heightAnchor constraintEqualToConstant:8.0].active = YES;

        _telemetryLabel = [[UILabel alloc] init];
        _telemetryLabel.font = [[PDMThemeManager sharedManager] tabularFontOfSize:11.5 weight:UIFontWeightMedium];
        _telemetryLabel.lineBreakMode = NSLineBreakByTruncatingTail;

        UIStackView *mainStack = [[UIStackView alloc] initWithArrangedSubviews:@[topRow, _segmentBar, _telemetryLabel]];
        mainStack.axis = UILayoutConstraintAxisVertical;
        mainStack.spacing = 10.0;
        mainStack.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardGlass.contentView addSubview:mainStack];

        [NSLayoutConstraint activateConstraints:@[
            [_cardGlass.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6.0],
            [_cardGlass.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6.0],
            [_cardGlass.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14.0],
            [_cardGlass.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-14.0],

            [_iconBadge.widthAnchor constraintEqualToConstant:42.0],
            [_iconBadge.heightAnchor constraintEqualToConstant:42.0],
            [_typeIcon.centerXAnchor constraintEqualToAnchor:_iconBadge.contentView.centerXAnchor],
            [_typeIcon.centerYAnchor constraintEqualToAnchor:_iconBadge.contentView.centerYAnchor],

            [mainStack.topAnchor constraintEqualToAnchor:_cardGlass.contentView.topAnchor constant:13.0],
            [mainStack.bottomAnchor constraintEqualToAnchor:_cardGlass.contentView.bottomAnchor constant:-13.0],
            [mainStack.leadingAnchor constraintEqualToAnchor:_cardGlass.contentView.leadingAnchor constant:13.0],
            [mainStack.trailingAnchor constraintEqualToAnchor:_cardGlass.contentView.trailingAnchor constant:-13.0]
        ]];
    }
    return self;
}

- (void)handlePrimary {
    if (self.onPrimaryTap) self.onPrimaryTap();
}

- (void)handleMore {
    if (self.onMoreTap) self.onMoreTap();
}

- (void)configureWithItem:(PDMDownloadItem *)item {
    PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;
    UIColor *catColor = [PDMThemeManager tintColorForCategory:item.category spec:spec];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18.0 weight:UIImageSymbolWeightSemibold];
    self.typeIcon.image = [UIImage systemImageNamed:[PDMThemeManager symbolNameForCategory:item.category] withConfiguration:cfg];
    self.typeIcon.tintColor = catColor;
    self.iconBadge.customTintColor = [catColor colorWithAlphaComponent:0.18];
    self.iconBadge.customBorderColor = [catColor colorWithAlphaComponent:0.42];
    [self.iconBadge applyTheme];

    self.nameLabel.text = item.filename;
    self.nameLabel.textColor = spec.primaryTextColor;

    NSMutableArray<NSString *> *badges = [NSMutableArray array];
    if (item.qualityLabel.length > 0) [badges addObject:item.qualityLabel];
    if (item.formatConfig && item.formatConfig.outputMode != PDMOutputModeOriginal) {
        [badges addObject:[item.formatConfig summaryBadgeText]];
    }
    if (item.audioTrackLabel.length > 0) [badges addObject:item.audioTrackLabel];
    if (item.segmentCount > 1 && !item.isHLS) {
        [badges addObject:[NSString stringWithFormat:@"%ld Parts", (long)item.segmentCount]];
    } else if (item.isHLS) {
        [badges addObject:@"HLS"];
    }
    if (badges.count == 0) [badges addObject:item.category];
    self.metaPillLabel.text = [badges componentsJoinedByString:@" · "];
    self.metaPillLabel.textColor = spec.accentColor;

    BOOL isConverting = (item.status == PDMDownloadStatusConverting || item.status == PDMDownloadStatusMuxing);
    self.segmentBar.convertingMode = isConverting;
    self.segmentBar.pausedState = (item.status == PDMDownloadStatusPaused);
    self.segmentBar.failedState = (item.status == PDMDownloadStatusFailed || item.status == PDMDownloadStatusCanceled);
    if (isConverting) {
        self.segmentBar.conversionProgress = item.conversionProgress;
    } else {
        NSArray<NSNumber *> *fracs = [item segmentProgressFractions];
        self.segmentBar.segmentCount = MAX(1, (NSInteger)fracs.count);
        self.segmentBar.segmentProgress = fracs;
    }

    int pct = (int)llround([item overallProgress] * 100.0);
    self.telemetryLabel.textColor = spec.secondaryTextColor;
    switch (item.status) {
        case PDMDownloadStatusDownloading:
            self.telemetryLabel.text = [NSString stringWithFormat:@"%@ · %@ / %@ (%d%%) · ETA %@",
                                        [PDMThemeManager formatSpeed:item.speedBytesPerSec],
                                        [PDMThemeManager formatBytes:item.downloadedBytes],
                                        (item.totalBytes > 0 ? [PDMThemeManager formatBytes:item.totalBytes] : @"--"),
                                        pct,
                                        [PDMThemeManager formatETA:item.etaSeconds]];
            self.primaryActionBtn.symbolName = @"pause.fill";
            self.primaryActionBtn.glowing = NO;
            break;
        case PDMDownloadStatusProbing:
            self.telemetryLabel.text = @"Probing server & byte-range support...";
            self.primaryActionBtn.symbolName = @"pause.fill";
            self.primaryActionBtn.glowing = NO;
            break;
        case PDMDownloadStatusQueued:
            self.telemetryLabel.text = @"Queued · Waiting for slot";
            self.primaryActionBtn.symbolName = @"pause.fill";
            self.primaryActionBtn.glowing = NO;
            break;
        case PDMDownloadStatusMuxing:
            self.telemetryLabel.text = [NSString stringWithFormat:@"Muxing Video + Audio... %d%%", pct];
            self.telemetryLabel.textColor = spec.mediaGlowColor;
            self.primaryActionBtn.symbolName = @"xmark";
            self.primaryActionBtn.glowing = YES;
            break;
        case PDMDownloadStatusConverting:
            self.telemetryLabel.text = [NSString stringWithFormat:@"Converting (%@)... %d%%", [item.formatConfig summaryBadgeText], pct];
            self.telemetryLabel.textColor = spec.mediaGlowColor;
            self.primaryActionBtn.symbolName = @"xmark";
            self.primaryActionBtn.glowing = YES;
            break;
        case PDMDownloadStatusPaused:
            self.telemetryLabel.text = [NSString stringWithFormat:@"Paused · %@ / %@ (%d%%)",
                                        [PDMThemeManager formatBytes:item.downloadedBytes],
                                        (item.totalBytes > 0 ? [PDMThemeManager formatBytes:item.totalBytes] : @"--"),
                                        pct];
            self.primaryActionBtn.symbolName = @"play.fill";
            self.primaryActionBtn.glowing = NO;
            break;
        case PDMDownloadStatusCompleted:
            self.telemetryLabel.text = [NSString stringWithFormat:@"Completed · %@ · Ready to open",
                                        [PDMThemeManager formatBytes:item.totalBytes]];
            self.telemetryLabel.textColor = spec.successColor;
            self.primaryActionBtn.symbolName = @"play.circle.fill";
            self.primaryActionBtn.glowing = YES;
            break;
        case PDMDownloadStatusFailed:
            self.telemetryLabel.text = [NSString stringWithFormat:@"Failed · %@", item.errorMessage ?: @"Network error"];
            self.telemetryLabel.textColor = spec.dangerColor;
            self.primaryActionBtn.symbolName = @"arrow.clockwise";
            self.primaryActionBtn.glowing = NO;
            break;
        case PDMDownloadStatusCanceled:
            self.telemetryLabel.text = @"Canceled";
            self.primaryActionBtn.symbolName = @"arrow.clockwise";
            self.primaryActionBtn.glowing = NO;
            break;
    }
    [self.primaryActionBtn applyTheme];
    [self.moreActionBtn applyTheme];
    [self.cardGlass applyTheme];
}

@end

#pragma mark - PDMAddURLSheetViewController

@interface PDMAddURLSheetViewController ()
@property (nonatomic, strong) UITextView *urlTextView;
@property (nonatomic, assign) NSInteger selectedParts;
@property (nonatomic, copy) NSString *selectedCategory;
@property (nonatomic, strong) UIStackView *partsRow;
@property (nonatomic, strong) UIStackView *catRow;
@end

@implementation PDMAddURLSheetViewController

- (void)viewDidLoad {
    self.sheetTitle = @"Add URL / Batch Import";
    self.sheetSubtitle = @"Paste 1 URL or multiple lines for parallel IDM download";
    self.sheetSymbolName = @"plus.circle.fill";
    self.allowsMediumDetent = YES;
    self.prefersLargeDefaultDetent = YES;
    [super viewDidLoad];

    self.selectedParts = [PDMThemeManager sharedManager].defaultSegmentCount;
    self.selectedCategory = @"Auto";
    [self showBottomBar:YES];

    PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;

    NSString *prefill = self.initialURL;
    if (prefill.length == 0) {
        NSString *clip = [UIPasteboard generalPasteboard].string;
        if (clip.length > 7 && ([clip.lowercaseString hasPrefix:@"http://"] || [clip.lowercaseString hasPrefix:@"https://"])) {
            prefill = clip;
        }
    }

    PDMGlassView *tvCard = [[PDMGlassView alloc] initWithCornerRadius:16.0 elevated:YES];
    tvCard.showAmbientShadow = NO;
    self.urlTextView = [[UITextView alloc] init];
    self.urlTextView.translatesAutoresizingMaskIntoConstraints = NO;
    self.urlTextView.backgroundColor = [UIColor clearColor];
    self.urlTextView.textColor = spec.primaryTextColor;
    self.urlTextView.tintColor = spec.accentColor;
    self.urlTextView.font = [[PDMThemeManager sharedManager] monoFontOfSize:13.0 weight:UIFontWeightMedium];
    self.urlTextView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.urlTextView.autocorrectionType = UITextAutocorrectionTypeNo;
    self.urlTextView.keyboardType = UIKeyboardTypeURL;
    self.urlTextView.text = prefill ?: @"";
    [tvCard.contentView addSubview:self.urlTextView];
    [NSLayoutConstraint activateConstraints:@[
        [self.urlTextView.topAnchor constraintEqualToAnchor:tvCard.contentView.topAnchor constant:10.0],
        [self.urlTextView.bottomAnchor constraintEqualToAnchor:tvCard.contentView.bottomAnchor constant:-10.0],
        [self.urlTextView.leadingAnchor constraintEqualToAnchor:tvCard.contentView.leadingAnchor constant:10.0],
        [self.urlTextView.trailingAnchor constraintEqualToAnchor:tvCard.contentView.trailingAnchor constant:-10.0],
        [self.urlTextView.heightAnchor constraintEqualToConstant:110.0]
    ]];
    [self.contentStack addArrangedSubview:[self sectionHeaderWithTitle:@"Direct or Batch URLs (One Per Line)" detail:@"Auto-filled from clipboard"]];
    [self.contentStack addArrangedSubview:tvCard];

    [self.contentStack addArrangedSubview:[self sectionHeaderWithTitle:@"Parallel Segments" detail:@"IDM Multi-Part Engine"]];
    self.partsRow = [[UIStackView alloc] init];
    self.partsRow.axis = UILayoutConstraintAxisHorizontal;
    self.partsRow.spacing = 8.0;
    self.partsRow.distribution = UIStackViewDistributionFillEqually;
    [self.contentStack addArrangedSubview:self.partsRow];

    [self.contentStack addArrangedSubview:[self sectionHeaderWithTitle:@"Destination Folder" detail:nil]];
    self.catRow = [[UIStackView alloc] init];
    self.catRow.axis = UILayoutConstraintAxisHorizontal;
    self.catRow.spacing = 8.0;
    self.catRow.distribution = UIStackViewDistributionFillEqually;
    [self.contentStack addArrangedSubview:self.catRow];

    PDMGlassPillButton *pasteBtn = [[PDMGlassPillButton alloc] initWithTitle:@"Paste" symbolName:@"doc.on.clipboard"];
    pasteBtn.verticalPadding = 12.0;
    [pasteBtn addTarget:self action:@selector(handlePasteTap) forControlEvents:UIControlEventTouchUpInside];
    [self.bottomBarStack addArrangedSubview:pasteBtn];

    PDMGlassPillButton *startBtn = [[PDMGlassPillButton alloc] initWithTitle:@"Start Download" symbolName:@"arrow.down.circle.fill"];
    startBtn.prominentAccent = YES;
    startBtn.verticalPadding = 12.0;
    [startBtn addTarget:self action:@selector(handleStartTap) forControlEvents:UIControlEventTouchUpInside];
    [self.bottomBarStack addArrangedSubview:startBtn];

    [self rebuildChips];
}

- (void)rebuildChips {
    for (UIView *v in [self.partsRow.arrangedSubviews copy]) {
        [self.partsRow removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    for (NSNumber *n in @[@2, @4, @8, @16]) {
        PDMGlassChip *c = [[PDMGlassChip alloc] initWithTitle:[NSString stringWithFormat:@"%ld Parts", (long)n.integerValue] subtitle:nil];
        c.tag = n.integerValue;
        c.chipSelected = (self.selectedParts == n.integerValue);
        [c addTarget:self action:@selector(handlePartTap:) forControlEvents:UIControlEventTouchUpInside];
        [self.partsRow addArrangedSubview:c];
    }

    for (UIView *v in [self.catRow.arrangedSubviews copy]) {
        [self.catRow removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    NSArray<NSString *> *cats = @[@"Auto", @"Videos", @"Audio", @"Private Vault"];
    for (NSUInteger i = 0; i < cats.count; i++) {
        PDMGlassChip *c = [[PDMGlassChip alloc] initWithTitle:cats[i] subtitle:nil];
        c.tag = (NSInteger)i;
        c.chipSelected = [self.selectedCategory isEqualToString:cats[i]];
        [c addTarget:self action:@selector(handleCatTap:) forControlEvents:UIControlEventTouchUpInside];
        [self.catRow addArrangedSubview:c];
    }
}

- (void)handlePartTap:(PDMGlassChip *)sender {
    [[PDMThemeManager sharedManager] triggerSelectionHaptic];
    self.selectedParts = sender.tag;
    [self rebuildChips];
}

- (void)handleCatTap:(PDMGlassChip *)sender {
    [[PDMThemeManager sharedManager] triggerSelectionHaptic];
    NSArray<NSString *> *cats = @[@"Auto", @"Videos", @"Audio", @"Private Vault"];
    if (sender.tag >= 0 && sender.tag < (NSInteger)cats.count) {
        self.selectedCategory = cats[(NSUInteger)sender.tag];
        [self rebuildChips];
    }
}

- (void)handlePasteTap {
    NSString *clip = [UIPasteboard generalPasteboard].string;
    if (clip.length > 0) {
        self.urlTextView.text = clip;
        [[PDMThemeManager sharedManager] triggerLightImpact];
    }
}

- (void)handleStartTap {
    NSArray<NSString *> *lines = [self.urlTextView.text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSInteger added = 0;
    for (NSString *raw in lines) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (line.length < 8) continue;
        if (![line.lowercaseString hasPrefix:@"http://"] && ![line.lowercaseString hasPrefix:@"https://"]) {
            line = [@"https://" stringByAppendingString:line];
        }
        PDMMediaFormatConfig *cfg = [PDMMediaFormatConfig defaultConfig];
        cfg.segmentCount = self.selectedParts;
        cfg.destinationCategory = self.selectedCategory;
        BOOL isHLS = [line.lowercaseString containsString:@".m3u8"];
        [[PDMDownloadManager sharedManager] enqueueDownloadWithURL:line
                                                          filename:nil
                                                           referer:nil
                                                         userAgent:[[PDMPrivacyShieldEngine sharedEngine] mobileUserAgent]
                                                      cookieHeader:nil
                                                      formatConfig:cfg
                                                      qualityLabel:nil
                                                   audioTrackLabel:nil
                                                             isHLS:isHLS
                                                  hlsAudioTrackURL:nil
                                                  startImmediately:YES];
        added++;
    }
    if (added == 0) {
        [[PDMThemeManager sharedManager] triggerWarningHaptic];
        [PDMToastBanner showInView:self.view message:@"Enter at least one valid http(s) URL." symbolName:@"exclamationmark.triangle"];
        return;
    }
    [[PDMThemeManager sharedManager] triggerSuccessHaptic];
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - PDMDownloadManagerViewController

@interface PDMDownloadManagerViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) PDMGlassView *heroBanner;
@property (nonatomic, strong) UILabel *speedHeroLabel;
@property (nonatomic, strong) UILabel *countsHeroLabel;
@property (nonatomic, strong) PDMGlassPillButton *speedLimitBtn;
@property (nonatomic, strong) PDMGlassPillButton *wifiOnlyBtn;
@property (nonatomic, strong) UIStackView *filterBar;
@property (nonatomic, strong) NSArray<PDMGlassChip *> *filterChips;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyStateLabel;
@property (nonatomic, copy) NSString *activeFilter; // All, Active, Converting, Completed
@property (nonatomic, copy) NSArray<PDMDownloadItem *> *filteredItems;
@end

@implementation PDMDownloadManagerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.activeFilter = @"All";
    self.filteredItems = @[];
    [self buildUI];
    [self applyTheme];
    [self reloadData];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData) name:PDMDownloadsDidUpdateNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyTheme) name:PDMThemeDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTogglePills) name:PDMSettingsDidChangeNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)buildUI {
    PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;

    // Header Row
    UIStackView *navRow = [[UIStackView alloc] init];
    navRow.axis = UILayoutConstraintAxisHorizontal;
    navRow.alignment = UIStackViewAlignmentCenter;
    navRow.spacing = 8.0;
    navRow.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:navRow];

    UILabel *titleLbl = [[UILabel alloc] init];
    titleLbl.text = @"Downloads";
    titleLbl.font = [[PDMThemeManager sharedManager] displayFontOfSize:24.0 weight:UIFontWeightBold];
    titleLbl.tag = 9001;
    [navRow addArrangedSubview:titleLbl];

    PDMGlassPillButton *libBtn = [[PDMGlassPillButton alloc] initWithTitle:@"Library" symbolName:@"folder"];
    [libBtn addTarget:self action:@selector(handleOpenLibrary) forControlEvents:UIControlEventTouchUpInside];
    [navRow addArrangedSubview:libBtn];

    PDMGlassPillButton *closeBtn = [[PDMGlassPillButton alloc] initWithTitle:nil symbolName:@"xmark"];
    closeBtn.horizontalPadding = 10.0;
    closeBtn.verticalPadding = 10.0;
    [closeBtn addTarget:self action:@selector(handleClose) forControlEvents:UIControlEventTouchUpInside];
    [navRow addArrangedSubview:closeBtn];

    // Top Summary Banner
    self.heroBanner = [[PDMGlassView alloc] initWithCornerRadius:16.0 elevated:NO];
    self.heroBanner.showAmbientShadow = NO;
    self.heroBanner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.heroBanner];

    UIStackView *heroMain = [[UIStackView alloc] init];
    heroMain.axis = UILayoutConstraintAxisVertical;
    heroMain.spacing = 10.0;
    heroMain.translatesAutoresizingMaskIntoConstraints = NO;
    [self.heroBanner.contentView addSubview:heroMain];

    UIStackView *telemetryRow = [[UIStackView alloc] init];
    telemetryRow.axis = UILayoutConstraintAxisHorizontal;
    telemetryRow.alignment = UIStackViewAlignmentCenter;

    UIStackView *speedCol = [[UIStackView alloc] init];
    speedCol.axis = UILayoutConstraintAxisVertical;
    speedCol.spacing = 2.0;

    self.speedHeroLabel = [[UILabel alloc] init];
    self.speedHeroLabel.text = @"0 KB/s";
    self.speedHeroLabel.font = [[PDMThemeManager sharedManager] tabularFontOfSize:20.0 weight:UIFontWeightBold];
    self.speedHeroLabel.textColor = spec.accentColor;
    [speedCol addArrangedSubview:self.speedHeroLabel];

    self.countsHeroLabel = [[UILabel alloc] init];
    self.countsHeroLabel.text = @"0 Active · 0 Queued";
    self.countsHeroLabel.font = [[PDMThemeManager sharedManager] tabularFontOfSize:12.0 weight:UIFontWeightRegular];
    self.countsHeroLabel.textColor = spec.secondaryTextColor;
    [speedCol addArrangedSubview:self.countsHeroLabel];
    [telemetryRow addArrangedSubview:speedCol];

    PDMGlassPillButton *addBtn = [[PDMGlassPillButton alloc] initWithTitle:@"Add URL" symbolName:@"plus"];
    addBtn.prominentAccent = YES;
    [addBtn addTarget:self action:@selector(handleAddURLTap) forControlEvents:UIControlEventTouchUpInside];
    [telemetryRow addArrangedSubview:addBtn];
    [heroMain addArrangedSubview:telemetryRow];

    // Quick-toggle pills row
    UIScrollView *toggleScroll = [[UIScrollView alloc] init];
    toggleScroll.showsHorizontalScrollIndicator = NO;
    toggleScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [toggleScroll.heightAnchor constraintEqualToConstant:34.0].active = YES;

    UIStackView *toggleRow = [[UIStackView alloc] init];
    toggleRow.axis = UILayoutConstraintAxisHorizontal;
    toggleRow.spacing = 8.0;
    toggleRow.translatesAutoresizingMaskIntoConstraints = NO;
    [toggleScroll addSubview:toggleRow];
    [NSLayoutConstraint activateConstraints:@[
        [toggleRow.topAnchor constraintEqualToAnchor:toggleScroll.contentLayoutGuide.topAnchor],
        [toggleRow.bottomAnchor constraintEqualToAnchor:toggleScroll.contentLayoutGuide.bottomAnchor],
        [toggleRow.leadingAnchor constraintEqualToAnchor:toggleScroll.contentLayoutGuide.leadingAnchor],
        [toggleRow.trailingAnchor constraintEqualToAnchor:toggleScroll.contentLayoutGuide.trailingAnchor],
        [toggleRow.heightAnchor constraintEqualToAnchor:toggleScroll.frameLayoutGuide.heightAnchor]
    ]];

    self.speedLimitBtn = [[PDMGlassPillButton alloc] initWithTitle:@"Speed: Unlimited" symbolName:@"speedometer"];
    [self.speedLimitBtn addTarget:self action:@selector(handleCycleSpeedLimit) forControlEvents:UIControlEventTouchUpInside];
    [toggleRow addArrangedSubview:self.speedLimitBtn];

    self.wifiOnlyBtn = [[PDMGlassPillButton alloc] initWithTitle:@"Wi-Fi Only: Off" symbolName:@"wifi"];
    [self.wifiOnlyBtn addTarget:self action:@selector(handleToggleWifiOnly) forControlEvents:UIControlEventTouchUpInside];
    [toggleRow addArrangedSubview:self.wifiOnlyBtn];

    PDMGlassPillButton *settingsBtn = [[PDMGlassPillButton alloc] initWithTitle:@"Settings" symbolName:@"slider.horizontal.3"];
    [settingsBtn addTarget:self action:@selector(handleOpenSettings) forControlEvents:UIControlEventTouchUpInside];
    [toggleRow addArrangedSubview:settingsBtn];

    [heroMain addArrangedSubview:toggleScroll];

    // Filter Bar (created once and updated in place)
    self.filterBar = [[UIStackView alloc] init];
    self.filterBar.axis = UILayoutConstraintAxisHorizontal;
    self.filterBar.spacing = 8.0;
    self.filterBar.distribution = UIStackViewDistributionFillEqually;
    self.filterBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.filterBar];

    NSArray<NSString *> *filterKeys = @[@"All", @"Active", @"Converting", @"Completed"];
    NSMutableArray<PDMGlassChip *> *chips = [NSMutableArray arrayWithCapacity:filterKeys.count];
    for (NSUInteger i = 0; i < filterKeys.count; i++) {
        PDMGlassChip *c = [[PDMGlassChip alloc] initWithTitle:filterKeys[i] subtitle:@"0"];
        c.tag = (NSInteger)i;
        c.chipSelected = [self.activeFilter isEqualToString:filterKeys[i]];
        [c addTarget:self action:@selector(handleFilterTap:) forControlEvents:UIControlEventTouchUpInside];
        [self.filterBar addArrangedSubview:c];
        [chips addObject:c];
    }
    self.filterChips = chips;

    // TableView
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.estimatedRowHeight = 128.0;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    [self.tableView registerClass:[PDMDownloadCardCell class] forCellReuseIdentifier:@"PDMDownloadCardCell"];
    [self.view addSubview:self.tableView];

    self.emptyStateLabel = [[UILabel alloc] init];
    self.emptyStateLabel.text = @"No downloads yet.\nTap Add URL or grab media from any webpage.";
    self.emptyStateLabel.font = [[PDMThemeManager sharedManager] bodyFontOfSize:14.5 weight:UIFontWeightRegular];
    self.emptyStateLabel.numberOfLines = 0;
    self.emptyStateLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyStateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.emptyStateLabel];

    [NSLayoutConstraint activateConstraints:@[
        [navRow.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12.0],
        [navRow.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16.0],
        [navRow.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],

        [self.heroBanner.topAnchor constraintEqualToAnchor:navRow.bottomAnchor constant:12.0],
        [self.heroBanner.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14.0],
        [self.heroBanner.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14.0],

        [heroMain.topAnchor constraintEqualToAnchor:self.heroBanner.contentView.topAnchor constant:12.0],
        [heroMain.bottomAnchor constraintEqualToAnchor:self.heroBanner.contentView.bottomAnchor constant:-12.0],
        [heroMain.leadingAnchor constraintEqualToAnchor:self.heroBanner.contentView.leadingAnchor constant:14.0],
        [heroMain.trailingAnchor constraintEqualToAnchor:self.heroBanner.contentView.trailingAnchor constant:-14.0],

        [self.filterBar.topAnchor constraintEqualToAnchor:self.heroBanner.bottomAnchor constant:10.0],
        [self.filterBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14.0],
        [self.filterBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14.0],

        [self.tableView.topAnchor constraintEqualToAnchor:self.filterBar.bottomAnchor constant:8.0],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.emptyStateLabel.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
        [self.emptyStateLabel.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor constant:-20.0],
        [self.emptyStateLabel.widthAnchor constraintLessThanOrEqualToAnchor:self.view.widthAnchor constant:-48.0]
    ]];

    [self updateTogglePills];
}

- (void)applyTheme {
    PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;
    self.overrideUserInterfaceStyle = spec.interfaceStyle;
    self.view.backgroundColor = spec.canvasColor;
    UILabel *titleLbl = (UILabel *)[self.view viewWithTag:9001];
    if ([titleLbl isKindOfClass:[UILabel class]]) {
        titleLbl.textColor = spec.primaryTextColor;
    }
    self.speedHeroLabel.textColor = spec.accentColor;
    self.countsHeroLabel.textColor = spec.secondaryTextColor;
    self.emptyStateLabel.textColor = spec.secondaryTextColor;
    [self.heroBanner applyTheme];
    [self.tableView reloadData];
}

- (void)updateTogglePills {
    PDMThemeManager *tm = [PDMThemeManager sharedManager];
    self.speedLimitBtn.titleText = (tm.speedLimitMBps == 0)
        ? @"Speed: Unlimited"
        : [NSString stringWithFormat:@"Cap: %ld MB/s", (long)tm.speedLimitMBps];
    self.speedLimitBtn.glowing = (tm.speedLimitMBps > 0);

    self.wifiOnlyBtn.titleText = tm.wifiOnlyDownloads ? @"Wi-Fi Only: ON" : @"Wi-Fi Only: Off";
    self.wifiOnlyBtn.glowing = tm.wifiOnlyDownloads;
}

- (void)reloadData {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self reloadData];
        });
        return;
    }
    PDMDownloadManager *dm = [PDMDownloadManager sharedManager];
    NSArray<PDMDownloadItem *> *all = dm.items;

    NSInteger activeC = 0, convC = 0, compC = 0;
    NSMutableArray<PDMDownloadItem *> *filtered = [NSMutableArray array];

    for (PDMDownloadItem *it in all) {
        BOOL isAct = (it.status == PDMDownloadStatusDownloading || it.status == PDMDownloadStatusProbing || it.status == PDMDownloadStatusQueued || it.status == PDMDownloadStatusPaused);
        BOOL isConv = (it.status == PDMDownloadStatusConverting || it.status == PDMDownloadStatusMuxing);
        BOOL isComp = (it.status == PDMDownloadStatusCompleted);
        if (isAct) activeC++;
        if (isConv) convC++;
        if (isComp) compC++;

        if ([self.activeFilter isEqualToString:@"All"] ||
            ([self.activeFilter isEqualToString:@"Active"] && isAct) ||
            ([self.activeFilter isEqualToString:@"Converting"] && isConv) ||
            ([self.activeFilter isEqualToString:@"Completed"] && isComp)) {
            [filtered addObject:it];
        }
    }

    self.filteredItems = filtered;
    self.speedHeroLabel.text = [PDMThemeManager formatSpeed:dm.aggregateSpeedBytesPerSec];
    self.countsHeroLabel.text = [NSString stringWithFormat:@"%ld Active · %ld Queued · %lu Total",
                                 (long)dm.activeCount, (long)dm.queuedCount, (unsigned long)all.count];

    NSArray<NSString *> *keys = @[@"All", @"Active", @"Converting", @"Completed"];
    NSArray<NSNumber *> *counts = @[@(all.count), @(activeC), @(convC), @(compC)];
    for (NSUInteger i = 0; i < self.filterChips.count && i < keys.count; i++) {
        PDMGlassChip *c = self.filterChips[i];
        c.subtitleText = [NSString stringWithFormat:@"%ld", (long)counts[i].integerValue];
        c.chipSelected = [self.activeFilter isEqualToString:keys[i]];
    }

    self.emptyStateLabel.hidden = (self.filteredItems.count > 0);
    [self.tableView reloadData];
}

#pragma mark - Actions

- (void)handleClose {
    [[PDMThemeManager sharedManager] triggerLightImpact];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)handleOpenLibrary {
    [[PDMThemeManager sharedManager] triggerLightImpact];
    dispatch_block_t cb = self.onOpenLibraryRequested;
    [self dismissViewControllerAnimated:YES completion:^{
        if (cb) cb();
    }];
}

- (void)handleOpenSettings {
    [[PDMThemeManager sharedManager] triggerLightImpact];
    dispatch_block_t cb = self.onOpenSettingsRequested;
    [self dismissViewControllerAnimated:YES completion:^{
        if (cb) cb();
    }];
}

- (void)handleAddURLTap {
    [[PDMThemeManager sharedManager] triggerMediumImpact];
    PDMAddURLSheetViewController *sheet = [[PDMAddURLSheetViewController alloc] init];
    [sheet presentFromViewController:self];
}

- (void)handleCycleSpeedLimit {
    [[PDMThemeManager sharedManager] triggerSelectionHaptic];
    NSArray<NSNumber *> *caps = @[@0, @1, @2, @5, @10];
    NSInteger cur = [PDMThemeManager sharedManager].speedLimitMBps;
    NSUInteger idx = [caps indexOfObject:@(cur)];
    NSInteger next = (idx == NSNotFound) ? 0 : caps[(idx + 1) % caps.count].integerValue;
    [PDMThemeManager sharedManager].speedLimitMBps = next;
    [self updateTogglePills];
}

- (void)handleToggleWifiOnly {
    [[PDMThemeManager sharedManager] triggerSelectionHaptic];
    PDMThemeManager *tm = [PDMThemeManager sharedManager];
    tm.wifiOnlyDownloads = !tm.wifiOnlyDownloads;
    [self updateTogglePills];
}

- (void)handleFilterTap:(PDMGlassChip *)sender {
    [[PDMThemeManager sharedManager] triggerSelectionHaptic];
    NSArray<NSString *> *keys = @[@"All", @"Active", @"Converting", @"Completed"];
    if (sender.tag >= 0 && sender.tag < (NSInteger)keys.count) {
        self.activeFilter = keys[(NSUInteger)sender.tag];
        [self reloadData];
    }
}

- (void)openCompletedItem:(PDMDownloadItem *)item {
    if (item.localFilePath.length == 0) return;
    NSURL *fileURL = [NSURL fileURLWithPath:item.localFilePath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:fileURL.path]) {
        [PDMToastBanner showInView:self.view message:@"Local file no longer exists on disk." symbolName:@"exclamationmark.triangle"];
        return;
    }
    if ([item.category isEqualToString:@"Videos"] || [item.category isEqualToString:@"Audio"]) {
        PDMMediaPlayerViewController *player = [[PDMMediaPlayerViewController alloc] initWithURL:fileURL title:item.filename httpHeaders:nil];
        player.onRequestConvertLocalFile = ^(NSURL *localURL, PDMMediaFormatConfig *cfg, NSString *outName) {
            [[PDMDownloadManager sharedManager] enqueueLocalConversionForFileURL:localURL config:cfg outputFilename:outName isPrivateVault:item.isPrivateVault];
        };
        [self presentViewController:player animated:YES completion:nil];
    } else {
        UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
        share.popoverPresentationController.sourceView = self.view;
        [self presentViewController:share animated:YES completion:nil];
    }
}

- (void)presentMoreActionsForItem:(PDMDownloadItem *)item {
    NSMutableArray<PDMGlassActionItem *> *actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;

    if (item.status == PDMDownloadStatusCompleted) {
        [actions addObject:[PDMGlassActionItem actionWithTitle:@"Play / Open File" subtitle:item.filename symbolName:@"play.circle.fill" destructive:NO handler:^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) [strongSelf openCompletedItem:item];
        }]];
    } else if ([item isActiveTransfer]) {
        [actions addObject:[PDMGlassActionItem actionWithTitle:@"Pause Transfer" subtitle:@"Preserves .pdmpart segment offsets" symbolName:@"pause.circle.fill" destructive:NO handler:^{
            [[PDMDownloadManager sharedManager] pauseItemWithID:item.itemID];
        }]];
    } else {
        [actions addObject:[PDMGlassActionItem actionWithTitle:@"Resume / Retry" subtitle:@"Continue from saved segment progress" symbolName:@"play.circle.fill" destructive:NO handler:^{
            [[PDMDownloadManager sharedManager] resumeItemWithID:item.itemID];
        }]];
    }

    if (item.status != PDMDownloadStatusCompleted) {
        [actions addObject:[PDMGlassActionItem actionWithTitle:@"Refresh Download Address"
                                                      subtitle:@"Replace expired link while keeping .pdmpart progress"
                                                    symbolName:@"link.badge.plus"
                                                   destructive:NO
                                                       handler:^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [PDMGlassActionSheetController presentTextInputFrom:strongSelf
                                                          title:@"Refresh Download Address"
                                                       subtitle:@"Paste a fresh link for this file — existing segment progress is preserved"
                                                    placeholder:@"https://..."
                                                    initialText:item.urlString
                                                   confirmTitle:@"Update & Resume"
                                                      onConfirm:^(NSString *value) {
                [[PDMDownloadManager sharedManager] refreshDownloadAddressForItemID:item.itemID
                                                                          newURLStr:value
                                                                            referer:item.referer
                                                                       cookieHeader:item.cookieHeader];
            }];
        }]];

        [actions addObject:[PDMGlassActionItem actionWithTitle:@"Cancel Transfer" subtitle:@"Stops download and removes partial data" symbolName:@"xmark.circle" destructive:YES handler:^{
            [[PDMDownloadManager sharedManager] cancelItemWithID:item.itemID];
        }]];
    }

    [actions addObject:[PDMGlassActionItem actionWithTitle:@"Copy Source URL" subtitle:item.urlString symbolName:@"doc.on.doc" destructive:NO handler:^{
        [UIPasteboard generalPasteboard].string = item.urlString;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) [PDMToastBanner showInView:strongSelf.view message:@"URL copied to clipboard" symbolName:@"checkmark.circle.fill"];
    }]];

    [actions addObject:[PDMGlassActionItem actionWithTitle:@"Delete from List (Keep File)" subtitle:nil symbolName:@"minus.circle" destructive:NO handler:^{
        [[PDMDownloadManager sharedManager] deleteItemWithID:item.itemID removeLocalFile:NO];
    }]];

    [actions addObject:[PDMGlassActionItem actionWithTitle:@"Delete Item & File" subtitle:@"Permanently removes file from disk" symbolName:@"trash.fill" destructive:YES handler:^{
        [[PDMDownloadManager sharedManager] deleteItemWithID:item.itemID removeLocalFile:YES];
    }]];

    [PDMGlassActionSheetController presentFrom:self
                                         title:item.filename
                                      subtitle:[NSString stringWithFormat:@"%@ · %@", item.category, [PDMThemeManager formatBytes:item.totalBytes]]
                                    symbolName:[PDMThemeManager symbolNameForCategory:item.category]
                                       actions:actions];
}

#pragma mark - UITableViewDataSource & Delegate

- (NSInteger)tableView:(UITableView *__unused)tableView numberOfRowsInSection:(NSInteger __unused)section {
    return (NSInteger)self.filteredItems.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PDMDownloadCardCell *cell = [tableView dequeueReusableCellWithIdentifier:@"PDMDownloadCardCell" forIndexPath:indexPath];
    PDMDownloadItem *item = self.filteredItems[(NSUInteger)indexPath.row];
    [cell configureWithItem:item];

    __weak typeof(self) weakSelf = self;
    cell.onPrimaryTap = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [[PDMThemeManager sharedManager] triggerLightImpact];
        if (item.status == PDMDownloadStatusCompleted) {
            [strongSelf openCompletedItem:item];
        } else if ([item isActiveTransfer] || item.status == PDMDownloadStatusQueued) {
            [[PDMDownloadManager sharedManager] pauseItemWithID:item.itemID];
        } else {
            [[PDMDownloadManager sharedManager] resumeItemWithID:item.itemID];
        }
    };
    cell.onMoreTap = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [[PDMThemeManager sharedManager] triggerLightImpact];
        [strongSelf presentMoreActionsForItem:item];
    };
    return cell;
}

- (void)tableView:(UITableView *__unused)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PDMDownloadItem *item = self.filteredItems[(NSUInteger)indexPath.row];
    if (item.status == PDMDownloadStatusCompleted) {
        [self openCompletedItem:item];
    } else {
        [self presentMoreActionsForItem:item];
    }
}

@end
