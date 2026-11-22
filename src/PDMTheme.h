// Copyright © 2026 PrismDM. All Rights Reserved. Proprietary and Confidential.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const PDMThemeDidChangeNotification;
extern NSNotificationName const PDMLayoutDidChangeNotification;
extern NSNotificationName const PDMSettingsDidChangeNotification;

typedef NS_ENUM(NSInteger, PDMThemeID) {
    PDMThemeLiquidGlass = 0,
    PDMThemeObsidianOLED = 1,
    PDMThemeBraveEmber = 2,
    PDMThemeChromeMinimal = 3,
    PDMThemeArcticGlacier = 4,
    PDMThemeCyberMidnight = 5
};

typedef NS_ENUM(NSInteger, PDMLayoutPreset) {
    PDMLayoutFloatingBottom = 0,
    PDMLayoutChromeMinimalTop = 1,
    PDMLayoutCompactPowerBar = 2
};

typedef NS_ENUM(NSInteger, PDMSearchEngine) {
    PDMSearchEngineGoogle = 0,
    PDMSearchEngineDuckDuckGo = 1,
    PDMSearchEngineBrave = 2,
    PDMSearchEngineBing = 3,
    PDMSearchEngineYouTube = 4,
    PDMSearchEngineCustom = 5
};

@interface PDMThemeSpec : NSObject
@property (nonatomic, assign, readonly) PDMThemeID themeID;
@property (nonatomic, copy, readonly) NSString *displayName;
@property (nonatomic, copy, readonly) NSString *subtitle;
@property (nonatomic, strong, readonly) UIColor *canvasColor;
@property (nonatomic, strong, readonly) UIColor *secondaryCanvasColor;
@property (nonatomic, strong, readonly) UIColor *glassTintColor;
@property (nonatomic, strong, readonly) UIColor *glassElevatedTintColor;
@property (nonatomic, strong, readonly) UIColor *glassSpecularBorderColor;
@property (nonatomic, strong, readonly) UIColor *glassTopRimColor;
@property (nonatomic, strong, readonly) UIColor *accentColor;
@property (nonatomic, strong, readonly) UIColor *secondaryAccentColor;
@property (nonatomic, strong, readonly) UIColor *mediaGlowColor;
@property (nonatomic, strong, readonly) UIColor *successColor;
@property (nonatomic, strong, readonly) UIColor *warningColor;
@property (nonatomic, strong, readonly) UIColor *dangerColor;
@property (nonatomic, strong, readonly) UIColor *primaryTextColor;
@property (nonatomic, strong, readonly) UIColor *secondaryTextColor;
@property (nonatomic, strong, readonly) UIColor *tertiaryTextColor;
@property (nonatomic, strong, readonly) UIColor *swatchPrimary;
@property (nonatomic, strong, readonly) UIColor *swatchSecondary;
@property (nonatomic, assign, readonly) UIBlurEffectStyle blurStyle;
@property (nonatomic, assign, readonly) UIUserInterfaceStyle interfaceStyle;
@property (nonatomic, assign, readonly) BOOL isDark;
@property (nonatomic, assign, readonly) BOOL isOLED;
@end

@interface PDMThemeManager : NSObject

+ (instancetype)sharedManager;

@property (nonatomic, assign) PDMThemeID currentThemeID;
@property (nonatomic, strong, readonly) PDMThemeSpec *currentSpec;
@property (nonatomic, assign) PDMLayoutPreset layoutPreset;
@property (nonatomic, assign) PDMSearchEngine searchEngine;
@property (nonatomic, copy) NSString *customSearchURLTemplate;

@property (nonatomic, assign) BOOL globalForceDarkMode;
@property (nonatomic, assign) BOOL clearDataOnExit;
@property (nonatomic, assign) BOOL biometricVaultLockEnabled;
@property (nonatomic, assign) BOOL keepOriginalAfterConvert;
@property (nonatomic, assign) NSInteger defaultSegmentCount;
@property (nonatomic, assign) NSInteger maxConcurrentDownloads;
@property (nonatomic, assign) NSInteger speedLimitMBps; // 0 = Unlimited
@property (nonatomic, assign) BOOL wifiOnlyDownloads;

- (NSArray<PDMThemeSpec *> *)allThemeSpecs;
- (PDMThemeSpec *)specForThemeID:(PDMThemeID)themeID;
- (NSString *)displayNameForLayoutPreset:(PDMLayoutPreset)preset;
- (NSString *)subtitleForLayoutPreset:(PDMLayoutPreset)preset;
- (NSString *)displayNameForSearchEngine:(PDMSearchEngine)engine;
- (NSString *)symbolNameForSearchEngine:(PDMSearchEngine)engine;
- (nullable NSURL *)searchURLForQuery:(NSString *)query;

// Typography helpers
- (UIFont *)displayFontOfSize:(CGFloat)size weight:(UIFontWeight)weight;
- (UIFont *)bodyFontOfSize:(CGFloat)size weight:(UIFontWeight)weight;
- (UIFont *)tabularFontOfSize:(CGFloat)size weight:(UIFontWeight)weight;
- (UIFont *)monoFontOfSize:(CGFloat)size weight:(UIFontWeight)weight;

// Haptics
- (void)triggerLightImpact;
- (void)triggerMediumImpact;
- (void)triggerSelectionHaptic;
- (void)triggerSuccessHaptic;
- (void)triggerWarningHaptic;

// Formatting utilities
+ (NSString *)formatBytes:(int64_t)bytes;
+ (NSString *)formatSpeed:(double)bytesPerSecond;
+ (NSString *)formatETA:(double)seconds;
+ (NSString *)formatDuration:(double)seconds;
+ (NSString *)sanitizeFilename:(NSString *)rawName fallbackExtension:(nullable NSString *)ext;
+ (NSString *)categoryForFilename:(NSString *)filename mimeType:(nullable NSString *)mimeType;
+ (NSString *)symbolNameForCategory:(NSString *)category;
+ (UIColor *)tintColorForCategory:(NSString *)category spec:(PDMThemeSpec *)spec;

@end

NS_ASSUME_NONNULL_END
