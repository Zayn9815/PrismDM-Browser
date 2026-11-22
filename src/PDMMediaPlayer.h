// Copyright © 2026 PrismDM. All Rights Reserved. Proprietary and Confidential.

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import "PDMMediaSniffer.h"

NS_ASSUME_NONNULL_BEGIN

@interface PDMMediaPlayerViewController : UIViewController

@property (nonatomic, strong, readonly) NSURL *mediaURL;
@property (nonatomic, copy, readonly) NSString *mediaTitle;
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *httpHeaders;
@property (nonatomic, copy, nullable) void (^onRequestConvertLocalFile)(NSURL *localFileURL, PDMMediaFormatConfig *config, NSString *outputFilename);

- (instancetype)initWithURL:(NSURL *)url
                      title:(NSString *)title
                httpHeaders:(nullable NSDictionary<NSString *, NSString *> *)headers;

+ (void)configurePlaybackAudioSession;

@end

NS_ASSUME_NONNULL_END
