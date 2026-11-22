// Copyright © 2026 PrismDM. All Rights Reserved. Proprietary and Confidential.

#import <Foundation/Foundation.h>
#import "PDMMediaSniffer.h"

NS_ASSUME_NONNULL_BEGIN

@interface PDMTranscodeJob : NSObject
@property (nonatomic, copy, readonly) NSString *jobID;
@property (nonatomic, assign, readonly, getter=isCancelled) BOOL cancelled;
- (void)cancel;
@end

@interface PDMTranscoder : NSObject

+ (instancetype)sharedTranscoder;

- (BOOL)needsConversionForInputURL:(NSURL *)inputURL config:(PDMMediaFormatConfig *)config;

- (PDMTranscodeJob *)transcodeFileAtURL:(NSURL *)inputURL
                            toOutputURL:(NSURL *)outputURL
                                 config:(PDMMediaFormatConfig *)config
                               progress:(nullable void (^)(double fraction))progressHandler
                             completion:(void (^)(BOOL success, NSURL * _Nullable finalURL, NSError * _Nullable error))completion;

- (PDMTranscodeJob *)muxVideoURL:(NSURL *)videoURL
                        audioURL:(nullable NSURL *)audioURL
                     toOutputURL:(NSURL *)outputURL
                        progress:(nullable void (^)(double fraction))progressHandler
                      completion:(void (^)(BOOL success, NSURL * _Nullable finalURL, NSError * _Nullable error))completion;

+ (nullable NSData *)decryptAES128Data:(NSData *)encryptedData
                                   key:(NSData *)keyData
                                    iv:(NSData *)ivData;

@end

NS_ASSUME_NONNULL_END
