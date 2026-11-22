// Copyright © 2026 PrismDM. All Rights Reserved. Proprietary and Confidential.

#import <UIKit/UIKit.h>
#import "PDMUI.h"

NS_ASSUME_NONNULL_BEGIN

@interface PDMLibraryFileEntry : NSObject
@property (nonatomic, copy) NSString *filename;
@property (nonatomic, strong) NSURL *fileURL;
@property (nonatomic, copy) NSString *category;
@property (nonatomic, assign) BOOL isPrivateVault;
@property (nonatomic, assign) int64_t fileSize;
@property (nonatomic, strong) NSDate *modifiedDate;
@property (nonatomic, assign) BOOL selected;
@end

@interface PDMLibraryViewController : UIViewController
@property (nonatomic, copy, nullable) dispatch_block_t onOpenDownloadsRequested;

+ (nullable NSString *)sha256HexForFileAtPath:(NSString *)filePath;
+ (BOOL)extractZipAtURL:(NSURL *)zipURL toDirectory:(NSURL *)destDir extractedCount:(NSInteger * _Nullable)outCount error:(NSError **)outError;
@end

NS_ASSUME_NONNULL_END
