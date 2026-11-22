// Copyright © 2026 PrismDM. All Rights Reserved. Proprietary and Confidential.

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import "PDMUI.h"

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const PDMPrivacyStatsDidChangeNotification;

@interface PDMSiteShieldSettings : NSObject
@property (nonatomic, copy) NSString *host;
@property (nonatomic, assign) BOOL shieldsEnabled;
@property (nonatomic, assign) BOOL blockPopups;
@property (nonatomic, assign) BOOL blockThirdPartyScripts;
@property (nonatomic, assign) BOOL autoUpgradeHTTPS;
@property (nonatomic, assign) BOOL forceDarkMode;
@property (nonatomic, assign) BOOL useDesktopUserAgent;

+ (instancetype)defaultSettingsForHost:(NSString *)host;
- (NSDictionary<NSString *, id> *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary<NSString *, id> *)dict host:(NSString *)host;
@end

@interface PDMPrivacyShieldEngine : NSObject

+ (instancetype)sharedEngine;

@property (nonatomic, assign, readonly) NSInteger adsBlocked;
@property (nonatomic, assign, readonly) NSInteger trackersBlocked;
@property (nonatomic, assign, readonly) NSInteger popupsBlocked;
@property (nonatomic, assign, readonly) int64_t bytesSaved;
@property (nonatomic, assign, readonly) NSInteger downloadsCompleted;

@property (nonatomic, strong, readonly, nullable) WKContentRuleList *adTrackerRuleList;
@property (nonatomic, strong, readonly, nullable) WKContentRuleList *thirdPartyScriptRuleList;

- (void)prepareContentRuleListsWithCompletion:(nullable void (^)(void))completion;
- (void)applyRulesToUserContentController:(WKUserContentController *)ucc forHost:(nullable NSString *)host;

- (PDMSiteShieldSettings *)settingsForHost:(nullable NSString *)host;
- (void)saveSettings:(PDMSiteShieldSettings *)settings;

- (NSInteger)blockedCountForHost:(nullable NSString *)host;
- (void)recordBlockedAdForHost:(nullable NSString *)host count:(NSInteger)count;
- (void)recordBlockedTrackerForHost:(nullable NSString *)host count:(NSInteger)count;
- (void)recordBlockedPopupForHost:(nullable NSString *)host;
- (void)recordDownloadCompletedWithBytes:(int64_t)bytes;
- (void)resetStats;

- (NSURL *)upgradedURLIfNeeded:(NSURL *)url;
- (NSString *)mobileUserAgent;
- (NSString *)desktopUserAgent;

- (WKUserScript *)cosmeticAdHiderUserScript;
- (WKUserScript *)forceDarkModeUserScript;
- (NSString *)toggleDarkModeJavaScript:(BOOL)enable;
- (NSString *)readerModeExtractionJavaScript;

- (void)clearDataForHost:(NSString *)host completion:(nullable dispatch_block_t)completion;
- (void)clearAllBrowsingDataWithCompletion:(nullable dispatch_block_t)completion;

@end

@interface PDMShieldSheetViewController : PDMGlassSheetViewController
@property (nonatomic, copy) NSString *currentHost;
@property (nonatomic, copy, nullable) void (^onSettingsChanged)(PDMSiteShieldSettings *settings);
@property (nonatomic, copy, nullable) dispatch_block_t onClearSiteData;
@end

NS_ASSUME_NONNULL_END
