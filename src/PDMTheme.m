// Copyright © 2026 PrismDM. All Rights Reserved. Proprietary and Confidential.

#import "PDMTheme.h"

NSNotificationName const PDMThemeDidChangeNotification = @"PDMThemeDidChangeNotification";
NSNotificationName const PDMLayoutDidChangeNotification = @"PDMLayoutDidChangeNotification";
NSNotificationName const PDMSettingsDidChangeNotification = @"PDMSettingsDidChangeNotification";

static NSString *const kPDMThemeIDKey = @"pdm_appearance_v2";
static NSString *const kPDMLayoutPresetKey = @"pdm_bar_position_v2";
static NSString *const kPDMSearchEngineKey = @"pdm_search_engine_v1";
static NSString *const kPDMCustomSearchURLKey = @"pdm_custom_search_url_v1";
static NSString *const kPDMGlobalDarkKey = @"pdm_global_force_dark_v1";
static NSString *const kPDMClearOnExitKey = @"pdm_clear_on_exit_v1";
static NSString *const kPDMBiometricLockKey = @"pdm_biometric_vault_lock_v1";
static NSString *const kPDMKeepOriginalKey = @"pdm_keep_original_convert_v1";
static NSString *const kPDMDefaultSegmentsKey = @"pdm_default_segments_v1";
static NSString *const kPDMMaxConcurrentKey = @"pdm_max_concurrent_v1";
static NSString *const kPDMSpeedLimitKey = @"pdm_speed_limit_mbps_v1";
static NSString *const kPDMWifiOnlyKey = @"pdm_wifi_only_v1";

static UIColor *PDMRGB(uint32_t hex, CGFloat alpha) {
    CGFloat r = (CGFloat)((hex >> 16) & 0xFF) / 255.0;
    CGFloat g = (CGFloat)((hex >> 8) & 0xFF) / 255.0;
    CGFloat b = (CGFloat)(hex & 0xFF) / 255.0;
    return [UIColor colorWithRed:r green:g blue:b alpha:alpha];
}

static UIColor *PDMDynamicColor(UIColor *lightColor, UIColor *darkColor) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return (tc.userInterfaceStyle == UIUserInterfaceStyleDark) ? darkColor : lightColor;
    }];
}

@interface PDMThemeSpec ()
@property (nonatomic, assign, readwrite) PDMThemeID themeID;
@property (nonatomic, copy, readwrite) NSString *displayName;
@property (nonatomic, copy, readwrite) NSString *subtitle;
@property (nonatomic, strong, readwrite) UIColor *canvasColor;
@property (nonatomic, strong, readwrite) UIColor *secondaryCanvasColor;
@property (nonatomic, strong, readwrite) UIColor *glassTintColor;
@property (nonatomic, strong, readwrite) UIColor *glassElevatedTintColor;
@property (nonatomic, strong, readwrite) UIColor *glassSpecularBorderColor;
@property (nonatomic, strong, readwrite) UIColor *glassTopRimColor;
@property (nonatomic, strong, readwrite) UIColor *accentColor;
@property (nonatomic, strong, readwrite) UIColor *secondaryAccentColor;
@property (nonatomic, strong, readwrite) UIColor *mediaGlowColor;
@property (nonatomic, strong, readwrite) UIColor *successColor;
@property (nonatomic, strong, readwrite) UIColor *warningColor;
@property (nonatomic, strong, readwrite) UIColor *dangerColor;
@property (nonatomic, strong, readwrite) UIColor *primaryTextColor;
@property (nonatomic, strong, readwrite) UIColor *secondaryTextColor;
@property (nonatomic, strong, readwrite) UIColor *tertiaryTextColor;
@property (nonatomic, strong, readwrite) UIColor *swatchPrimary;
@property (nonatomic, strong, readwrite) UIColor *swatchSecondary;
@property (nonatomic, assign, readwrite) UIBlurEffectStyle blurStyle;
@property (nonatomic, assign, readwrite) UIUserInterfaceStyle interfaceStyle;
@property (nonatomic, assign, readwrite) BOOL isDark;
@property (nonatomic, assign, readwrite) BOOL isOLED;
@end

@implementation PDMThemeSpec
@end

@interface PDMThemeManager ()
@property (nonatomic, strong) NSArray<PDMThemeSpec *> *cachedSpecs;
@property (nonatomic, strong) UIImpactFeedbackGenerator *lightGenerator;
@property (nonatomic, strong) UIImpactFeedbackGenerator *mediumGenerator;
@property (nonatomic, strong) UISelectionFeedbackGenerator *selectionGenerator;
@property (nonatomic, strong) UINotificationFeedbackGenerator *notificationGenerator;
@end

@implementation PDMThemeManager

+ (instancetype)sharedManager {
    static PDMThemeManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[PDMThemeManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cachedSpecs = [self buildThemeSpecs];
        _lightGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        _mediumGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        _selectionGenerator = [[UISelectionFeedbackGenerator alloc] init];
        _notificationGenerator = [[UINotificationFeedbackGenerator alloc] init];

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSInteger savedTheme = [defaults integerForKey:kPDMThemeIDKey];
        if (savedTheme < 0 || savedTheme >= (NSInteger)_cachedSpecs.count) {
            savedTheme = PDMThemeSystem;
        }
        _currentThemeID = (PDMThemeID)savedTheme;

        NSInteger savedLayout = [defaults integerForKey:kPDMLayoutPresetKey];
        if (savedLayout < 0 || savedLayout > PDMLayoutChromeBottom) {
            savedLayout = PDMLayoutChromeTop;
        }
        _layoutPreset = (PDMLayoutPreset)savedLayout;

        NSInteger savedEngine = [defaults integerForKey:kPDMSearchEngineKey];
        if (savedEngine < 0 || savedEngine > PDMSearchEngineCustom) {
            savedEngine = PDMSearchEngineGoogle;
        }
        _searchEngine = (PDMSearchEngine)savedEngine;

        NSString *customURL = [defaults stringForKey:kPDMCustomSearchURLKey];
        _customSearchURLTemplate = (customURL.length > 0) ? customURL : @"https://search.brave.com/search?q=%@";

        _globalForceDarkMode = [defaults boolForKey:kPDMGlobalDarkKey];
        _clearDataOnExit = [defaults boolForKey:kPDMClearOnExitKey];
        _biometricVaultLockEnabled = ([defaults objectForKey:kPDMBiometricLockKey] != nil)
            ? [defaults boolForKey:kPDMBiometricLockKey] : YES;
        _keepOriginalAfterConvert = [defaults boolForKey:kPDMKeepOriginalKey];

        NSInteger segs = [defaults integerForKey:kPDMDefaultSegmentsKey];
        _defaultSegmentCount = (segs == 2 || segs == 4 || segs == 8 || segs == 16) ? segs : 8;

        NSInteger maxConc = [defaults integerForKey:kPDMMaxConcurrentKey];
        _maxConcurrentDownloads = (maxConc >= 1 && maxConc <= 3) ? maxConc : 3;

        NSInteger spd = [defaults integerForKey:kPDMSpeedLimitKey];
        _speedLimitMBps = (spd >= 0 && spd <= 100) ? spd : 0;

        _wifiOnlyDownloads = [defaults boolForKey:kPDMWifiOnlyKey];
    }
    return self;
}

- (NSArray<PDMThemeSpec *> *)buildThemeSpecs {
    // 1. System (Default — Adaptive Chrome Light / Graphite Dark)
    PDMThemeSpec *system = [[PDMThemeSpec alloc] init];
    system.themeID = PDMThemeSystem;
    system.displayName = @"System";
    system.subtitle = @"Matches iOS Light & Dark appearance";
    system.canvasColor = PDMDynamicColor(PDMRGB(0xFFFFFF, 1.0), PDMRGB(0x202124, 1.0));
    system.secondaryCanvasColor = PDMDynamicColor(PDMRGB(0xF1F3F4, 1.0), PDMRGB(0x303134, 1.0));
    system.glassTintColor = PDMDynamicColor(PDMRGB(0xF1F3F4, 1.0), PDMRGB(0x303134, 1.0));
    system.glassElevatedTintColor = PDMDynamicColor(PDMRGB(0xFFFFFF, 1.0), PDMRGB(0x292A2D, 1.0));
    system.glassSpecularBorderColor = PDMDynamicColor([UIColor colorWithWhite:0.0 alpha:0.08], [UIColor colorWithWhite:1.0 alpha:0.10]);
    system.glassTopRimColor = [UIColor clearColor];
    system.accentColor = PDMDynamicColor(PDMRGB(0x1A73E8, 1.0), PDMRGB(0x8AB4F8, 1.0));
    system.secondaryAccentColor = PDMDynamicColor(PDMRGB(0x1967D2, 1.0), PDMRGB(0x669DF6, 1.0));
    system.mediaGlowColor = PDMDynamicColor(PDMRGB(0x1A73E8, 1.0), PDMRGB(0x8AB4F8, 1.0));
    system.successColor = PDMDynamicColor(PDMRGB(0x188038, 1.0), PDMRGB(0x81C995, 1.0));
    system.warningColor = PDMDynamicColor(PDMRGB(0xE37400, 1.0), PDMRGB(0xFDD663, 1.0));
    system.dangerColor = PDMDynamicColor(PDMRGB(0xD93025, 1.0), PDMRGB(0xF28B82, 1.0));
    system.primaryTextColor = PDMDynamicColor(PDMRGB(0x202124, 1.0), PDMRGB(0xE8EAED, 1.0));
    system.secondaryTextColor = PDMDynamicColor(PDMRGB(0x5F6368, 1.0), PDMRGB(0x9AA0A6, 1.0));
    system.tertiaryTextColor = PDMDynamicColor(PDMRGB(0x80868B, 1.0), PDMRGB(0x80868B, 1.0));
    system.swatchPrimary = PDMRGB(0xF1F3F4, 1.0);
    system.swatchSecondary = PDMRGB(0x1A73E8, 1.0);
    system.blurStyle = UIBlurEffectStyleSystemChromeMaterial;
    system.interfaceStyle = UIUserInterfaceStyleUnspecified;
    system.isDark = NO;
    system.isOLED = NO;

    // 2. Light (Crisp Minimal Chrome Light)
    PDMThemeSpec *light = [[PDMThemeSpec alloc] init];
    light.themeID = PDMThemeLight;
    light.displayName = @"Light";
    light.subtitle = @"Pure white canvas with subtle slate surfaces";
    light.canvasColor = PDMRGB(0xFFFFFF, 1.0);
    light.secondaryCanvasColor = PDMRGB(0xF1F3F4, 1.0);
    light.glassTintColor = PDMRGB(0xF1F3F4, 1.0);
    light.glassElevatedTintColor = PDMRGB(0xFFFFFF, 1.0);
    light.glassSpecularBorderColor = [UIColor colorWithWhite:0.0 alpha:0.08];
    light.glassTopRimColor = [UIColor clearColor];
    light.accentColor = PDMRGB(0x1A73E8, 1.0);
    light.secondaryAccentColor = PDMRGB(0x1967D2, 1.0);
    light.mediaGlowColor = PDMRGB(0x1A73E8, 1.0);
    light.successColor = PDMRGB(0x188038, 1.0);
    light.warningColor = PDMRGB(0xE37400, 1.0);
    light.dangerColor = PDMRGB(0xD93025, 1.0);
    light.primaryTextColor = PDMRGB(0x202124, 1.0);
    light.secondaryTextColor = PDMRGB(0x5F6368, 1.0);
    light.tertiaryTextColor = PDMRGB(0x80868B, 1.0);
    light.swatchPrimary = PDMRGB(0xFFFFFF, 1.0);
    light.swatchSecondary = PDMRGB(0x1A73E8, 1.0);
    light.blurStyle = UIBlurEffectStyleSystemChromeMaterialLight;
    light.interfaceStyle = UIUserInterfaceStyleLight;
    light.isDark = NO;
    light.isOLED = NO;

    // 3. Dark (Refined Chrome Graphite Dark)
    PDMThemeSpec *dark = [[PDMThemeSpec alloc] init];
    dark.themeID = PDMThemeDark;
    dark.displayName = @"Dark";
    dark.subtitle = @"Refined matte graphite with soft blue accents";
    dark.canvasColor = PDMRGB(0x202124, 1.0);
    dark.secondaryCanvasColor = PDMRGB(0x303134, 1.0);
    dark.glassTintColor = PDMRGB(0x303134, 1.0);
    dark.glassElevatedTintColor = PDMRGB(0x292A2D, 1.0);
    dark.glassSpecularBorderColor = [UIColor colorWithWhite:1.0 alpha:0.10];
    dark.glassTopRimColor = [UIColor clearColor];
    dark.accentColor = PDMRGB(0x8AB4F8, 1.0);
    dark.secondaryAccentColor = PDMRGB(0x669DF6, 1.0);
    dark.mediaGlowColor = PDMRGB(0x8AB4F8, 1.0);
    dark.successColor = PDMRGB(0x81C995, 1.0);
    dark.warningColor = PDMRGB(0xFDD663, 1.0);
    dark.dangerColor = PDMRGB(0xF28B82, 1.0);
    dark.primaryTextColor = PDMRGB(0xE8EAED, 1.0);
    dark.secondaryTextColor = PDMRGB(0x9AA0A6, 1.0);
    dark.tertiaryTextColor = PDMRGB(0x80868B, 1.0);
    dark.swatchPrimary = PDMRGB(0x202124, 1.0);
    dark.swatchSecondary = PDMRGB(0x8AB4F8, 1.0);
    dark.blurStyle = UIBlurEffectStyleSystemChromeMaterialDark;
    dark.interfaceStyle = UIUserInterfaceStyleDark;
    dark.isDark = YES;
    dark.isOLED = NO;

    return @[system, light, dark];
}

- (NSArray<PDMThemeSpec *> *)allThemeSpecs {
    return self.cachedSpecs;
}

- (PDMThemeSpec *)specForThemeID:(PDMThemeID)themeID {
    NSInteger idx = (NSInteger)themeID;
    if (idx < 0 || idx >= (NSInteger)self.cachedSpecs.count) {
        return self.cachedSpecs.firstObject;
    }
    return self.cachedSpecs[(NSUInteger)idx];
}

- (PDMThemeSpec *)currentSpec {
    return [self specForThemeID:self.currentThemeID];
}

- (void)setCurrentThemeID:(PDMThemeID)currentThemeID {
    if (_currentThemeID == currentThemeID) {
        return;
    }
    _currentThemeID = currentThemeID;
    [[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)currentThemeID forKey:kPDMThemeIDKey];
    [self triggerSelectionHaptic];
    [[NSNotificationCenter defaultCenter] postNotificationName:PDMThemeDidChangeNotification object:self];
}

- (void)setLayoutPreset:(PDMLayoutPreset)layoutPreset {
    if (_layoutPreset == layoutPreset) {
        return;
    }
    _layoutPreset = layoutPreset;
    [[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)layoutPreset forKey:kPDMLayoutPresetKey];
    [self triggerSelectionHaptic];
    [[NSNotificationCenter defaultCenter] postNotificationName:PDMLayoutDidChangeNotification object:self];
}

- (void)setSearchEngine:(PDMSearchEngine)searchEngine {
    if (_searchEngine == searchEngine) {
        return;
    }
    _searchEngine = searchEngine;
    [[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)searchEngine forKey:kPDMSearchEngineKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:PDMSettingsDidChangeNotification object:self];
}

- (void)setCustomSearchURLTemplate:(NSString *)customSearchURLTemplate {
    _customSearchURLTemplate = [customSearchURLTemplate copy];
    [[NSUserDefaults standardUserDefaults] setObject:_customSearchURLTemplate forKey:kPDMCustomSearchURLKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:PDMSettingsDidChangeNotification object:self];
}

- (void)setGlobalForceDarkMode:(BOOL)globalForceDarkMode {
    _globalForceDarkMode = globalForceDarkMode;
    [[NSUserDefaults standardUserDefaults] setBool:globalForceDarkMode forKey:kPDMGlobalDarkKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:PDMSettingsDidChangeNotification object:self];
}

- (void)setClearDataOnExit:(BOOL)clearDataOnExit {
    _clearDataOnExit = clearDataOnExit;
    [[NSUserDefaults standardUserDefaults] setBool:clearDataOnExit forKey:kPDMClearOnExitKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:PDMSettingsDidChangeNotification object:self];
}

- (void)setBiometricVaultLockEnabled:(BOOL)biometricVaultLockEnabled {
    _biometricVaultLockEnabled = biometricVaultLockEnabled;
    [[NSUserDefaults standardUserDefaults] setBool:biometricVaultLockEnabled forKey:kPDMBiometricLockKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:PDMSettingsDidChangeNotification object:self];
}

- (void)setKeepOriginalAfterConvert:(BOOL)keepOriginalAfterConvert {
    _keepOriginalAfterConvert = keepOriginalAfterConvert;
    [[NSUserDefaults standardUserDefaults] setBool:keepOriginalAfterConvert forKey:kPDMKeepOriginalKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:PDMSettingsDidChangeNotification object:self];
}

- (void)setDefaultSegmentCount:(NSInteger)defaultSegmentCount {
    if (defaultSegmentCount != 2 && defaultSegmentCount != 4 && defaultSegmentCount != 8 && defaultSegmentCount != 16) {
        defaultSegmentCount = 8;
    }
    _defaultSegmentCount = defaultSegmentCount;
    [[NSUserDefaults standardUserDefaults] setInteger:defaultSegmentCount forKey:kPDMDefaultSegmentsKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:PDMSettingsDidChangeNotification object:self];
}

- (void)setMaxConcurrentDownloads:(NSInteger)maxConcurrentDownloads {
    if (maxConcurrentDownloads < 1) maxConcurrentDownloads = 1;
    if (maxConcurrentDownloads > 3) maxConcurrentDownloads = 3;
    _maxConcurrentDownloads = maxConcurrentDownloads;
    [[NSUserDefaults standardUserDefaults] setInteger:maxConcurrentDownloads forKey:kPDMMaxConcurrentKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:PDMSettingsDidChangeNotification object:self];
}

- (void)setSpeedLimitMBps:(NSInteger)speedLimitMBps {
    if (speedLimitMBps < 0) speedLimitMBps = 0;
    _speedLimitMBps = speedLimitMBps;
    [[NSUserDefaults standardUserDefaults] setInteger:speedLimitMBps forKey:kPDMSpeedLimitKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:PDMSettingsDidChangeNotification object:self];
}

- (void)setWifiOnlyDownloads:(BOOL)wifiOnlyDownloads {
    _wifiOnlyDownloads = wifiOnlyDownloads;
    [[NSUserDefaults standardUserDefaults] setBool:wifiOnlyDownloads forKey:kPDMWifiOnlyKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:PDMSettingsDidChangeNotification object:self];
}

- (NSString *)displayNameForLayoutPreset:(PDMLayoutPreset)preset {
    switch (preset) {
        case PDMLayoutChromeTop: return @"Top";
        case PDMLayoutChromeBottom: return @"Bottom";
    }
    return @"Top";
}

- (NSString *)subtitleForLayoutPreset:(PDMLayoutPreset)preset {
    switch (preset) {
        case PDMLayoutChromeTop: return @"Classic Chrome top address bar + bottom toolbar";
        case PDMLayoutChromeBottom: return @"Thumb-friendly bottom address bar";
    }
    return @"";
}

- (NSString *)displayNameForSearchEngine:(PDMSearchEngine)engine {
    switch (engine) {
        case PDMSearchEngineGoogle: return @"Google";
        case PDMSearchEngineDuckDuckGo: return @"DuckDuckGo";
        case PDMSearchEngineBrave: return @"Brave Search";
        case PDMSearchEngineBing: return @"Bing";
        case PDMSearchEngineYouTube: return @"YouTube";
        case PDMSearchEngineCustom: return @"Custom";
    }
    return @"Google";
}

- (NSString *)symbolNameForSearchEngine:(PDMSearchEngine)engine {
    switch (engine) {
        case PDMSearchEngineGoogle: return @"magnifyingglass";
        case PDMSearchEngineDuckDuckGo: return @"shield";
        case PDMSearchEngineBrave: return @"flame";
        case PDMSearchEngineBing: return @"globe";
        case PDMSearchEngineYouTube: return @"play.rectangle";
        case PDMSearchEngineCustom: return @"slider.horizontal.3";
    }
    return @"magnifyingglass";
}

- (nullable NSURL *)searchURLForQuery:(NSString *)query {
    NSString *trimmed = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return nil;
    }
    // Check if input looks like a direct URL
    BOOL hasSpaces = ([trimmed rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]].location != NSNotFound);
    if (!hasSpaces) {
        NSString *lower = trimmed.lowercaseString;
        if ([lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"]) {
            return [NSURL URLWithString:trimmed];
        }
        if ([trimmed containsString:@"."] && ![trimmed hasPrefix:@"."] && ![trimmed hasSuffix:@"."]) {
            NSURL *candidate = [NSURL URLWithString:[@"https://" stringByAppendingString:trimmed]];
            if (candidate && candidate.host.length > 0) {
                return candidate;
            }
        }
    }

    NSString *encoded = [trimmed stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    if (!encoded) {
        encoded = trimmed;
    }
    NSString *templateStr = nil;
    switch (self.searchEngine) {
        case PDMSearchEngineGoogle:
            templateStr = @"https://www.google.com/search?q=%@";
            break;
        case PDMSearchEngineDuckDuckGo:
            templateStr = @"https://duckduckgo.com/?q=%@";
            break;
        case PDMSearchEngineBrave:
            templateStr = @"https://search.brave.com/search?q=%@";
            break;
        case PDMSearchEngineBing:
            templateStr = @"https://www.bing.com/search?q=%@";
            break;
        case PDMSearchEngineYouTube:
            templateStr = @"https://m.youtube.com/results?search_query=%@";
            break;
        case PDMSearchEngineCustom:
            templateStr = (self.customSearchURLTemplate.length > 0) ? self.customSearchURLTemplate : @"https://search.brave.com/search?q=%@";
            break;
    }
    NSString *finalStr = nil;
    if ([templateStr containsString:@"%@"]) {
        finalStr = [templateStr stringByReplacingOccurrencesOfString:@"%@" withString:encoded];
    } else if ([templateStr containsString:@"{q}"]) {
        finalStr = [templateStr stringByReplacingOccurrencesOfString:@"{q}" withString:encoded];
    } else {
        finalStr = [templateStr stringByAppendingString:encoded];
    }
    return [NSURL URLWithString:finalStr];
}

#pragma mark - Typography

- (UIFont *)displayFontOfSize:(CGFloat)size weight:(UIFontWeight)weight {
    return [UIFont systemFontOfSize:size weight:weight];
}

- (UIFont *)bodyFontOfSize:(CGFloat)size weight:(UIFontWeight)weight {
    return [UIFont systemFontOfSize:size weight:weight];
}

- (UIFont *)tabularFontOfSize:(CGFloat)size weight:(UIFontWeight)weight {
    return [UIFont monospacedDigitSystemFontOfSize:size weight:weight];
}

- (UIFont *)monoFontOfSize:(CGFloat)size weight:(UIFontWeight)weight {
    return [UIFont monospacedSystemFontOfSize:size weight:weight];
}

#pragma mark - Haptics

- (void)triggerLightImpact {
    [self.lightGenerator impactOccurred];
}

- (void)triggerMediumImpact {
    [self.mediumGenerator impactOccurred];
}

- (void)triggerSelectionHaptic {
    [self.selectionGenerator selectionChanged];
}

- (void)triggerSuccessHaptic {
    [self.notificationGenerator notificationOccurred:UINotificationFeedbackTypeSuccess];
}

- (void)triggerWarningHaptic {
    [self.notificationGenerator notificationOccurred:UINotificationFeedbackTypeWarning];
}

#pragma mark - Formatters

+ (NSString *)formatBytes:(int64_t)bytes {
    if (bytes < 0) {
        return @"--";
    }
    double b = (double)bytes;
    if (b < 1024.0) {
        return [NSString stringWithFormat:@"%lld B", (long long)bytes];
    } else if (b < 1024.0 * 1024.0) {
        return [NSString stringWithFormat:@"%.1f KB", b / 1024.0];
    } else if (b < 1024.0 * 1024.0 * 1024.0) {
        return [NSString stringWithFormat:@"%.1f MB", b / (1024.0 * 1024.0)];
    } else {
        return [NSString stringWithFormat:@"%.2f GB", b / (1024.0 * 1024.0 * 1024.0)];
    }
}

+ (NSString *)formatSpeed:(double)bytesPerSecond {
    if (bytesPerSecond <= 1.0) {
        return @"0 KB/s";
    }
    if (bytesPerSecond < 1024.0 * 1024.0) {
        return [NSString stringWithFormat:@"%.0f KB/s", bytesPerSecond / 1024.0];
    }
    return [NSString stringWithFormat:@"%.1f MB/s", bytesPerSecond / (1024.0 * 1024.0)];
}

+ (NSString *)formatETA:(double)seconds {
    if (seconds <= 0.0 || !isfinite(seconds) || seconds > 86400.0 * 7.0) {
        return @"--";
    }
    long total = (long)llround(seconds);
    if (total < 60) {
        return [NSString stringWithFormat:@"%lds", total];
    } else if (total < 3600) {
        long m = total / 60;
        long s = total % 60;
        return [NSString stringWithFormat:@"%ldm %02lds", m, s];
    } else {
        long h = total / 3600;
        long m = (total % 3600) / 60;
        return [NSString stringWithFormat:@"%ldh %02ldm", h, m];
    }
}

+ (NSString *)formatDuration:(double)seconds {
    if (seconds < 0.0 || !isfinite(seconds)) {
        return @"0:00";
    }
    long total = (long)floor(seconds);
    long h = total / 3600;
    long m = (total % 3600) / 60;
    long s = total % 60;
    if (h > 0) {
        return [NSString stringWithFormat:@"%ld:%02ld:%02ld", h, m, s];
    }
    return [NSString stringWithFormat:@"%ld:%02ld", m, s];
}

+ (NSString *)sanitizeFilename:(NSString *)rawName fallbackExtension:(nullable NSString *)ext {
    NSString *cleaned = [rawName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (cleaned.length == 0) {
        cleaned = @"PrismDM_Download";
    }
    NSCharacterSet *illegal = [NSCharacterSet characterSetWithCharactersInString:@"/\\:?%*|\"<>#\n\r\t"];
    NSArray<NSString *> *parts = [cleaned componentsSeparatedByCharactersInSet:illegal];
    cleaned = [parts componentsJoinedByString:@"_"];
    while ([cleaned hasPrefix:@"."]) {
        cleaned = [cleaned substringFromIndex:1];
    }
    if (cleaned.length == 0) {
        cleaned = @"PrismDM_Download";
    }
    if (cleaned.length > 140) {
        NSString *currentExt = cleaned.pathExtension;
        NSString *base = [cleaned stringByDeletingPathExtension];
        if (base.length > 120) {
            base = [base substringToIndex:120];
        }
        cleaned = (currentExt.length > 0) ? [base stringByAppendingPathExtension:currentExt] : base;
    }
    if (cleaned.pathExtension.length == 0 && ext.length > 0) {
        NSString *cleanExt = [ext stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"."]];
        if (cleanExt.length > 0) {
            cleaned = [cleaned stringByAppendingPathExtension:cleanExt];
        }
    }
    return cleaned;
}

+ (NSString *)categoryForFilename:(NSString *)filename mimeType:(nullable NSString *)mimeType {
    NSString *ext = filename.pathExtension.lowercaseString;
    NSString *mime = mimeType.lowercaseString ?: @"";

    NSSet<NSString *> *videoExts = [NSSet setWithObjects:@"mp4", @"m4v", @"mov", @"mkv", @"webm", @"ts", @"m3u8", @"avi", @"flv", @"3gp", nil];
    NSSet<NSString *> *audioExts = [NSSet setWithObjects:@"mp3", @"m4a", @"aac", @"flac", @"wav", @"ogg", @"opus", @"alac", @"aiff", nil];
    NSSet<NSString *> *archiveExts = [NSSet setWithObjects:@"zip", @"rar", @"7z", @"tar", @"gz", @"bz2", @"xz", @"ipa", @"dmg", @"pkg", nil];
    NSSet<NSString *> *imageExts = [NSSet setWithObjects:@"png", @"jpg", @"jpeg", @"webp", @"gif", @"heic", @"svg", @"bmp", @"tiff", nil];
    NSSet<NSString *> *docExts = [NSSet setWithObjects:@"pdf", @"doc", @"docx", @"xls", @"xlsx", @"ppt", @"pptx", @"txt", @"md", @"csv", @"json", @"xml", @"epub", @"html", nil];

    if ([videoExts containsObject:ext] || [mime hasPrefix:@"video/"] || [mime containsString:@"mpegurl"]) {
        return @"Videos";
    }
    if ([audioExts containsObject:ext] || [mime hasPrefix:@"audio/"]) {
        return @"Audio";
    }
    if ([archiveExts containsObject:ext] || [mime containsString:@"zip"] || [mime containsString:@"compressed"] || [mime containsString:@"octet-stream"]) {
        if ([ext isEqualToString:@"ipa"]) {
            return @"Archives";
        }
        if ([archiveExts containsObject:ext] || [mime containsString:@"zip"]) {
            return @"Archives";
        }
    }
    if ([imageExts containsObject:ext] || [mime hasPrefix:@"image/"]) {
        return @"Images";
    }
    if ([docExts containsObject:ext] || [mime hasPrefix:@"text/"] || [mime containsString:@"pdf"]) {
        return @"Documents";
    }
    return @"Documents";
}

+ (NSString *)symbolNameForCategory:(NSString *)category {
    if ([category isEqualToString:@"Videos"]) return @"film.fill";
    if ([category isEqualToString:@"Audio"]) return @"waveform.circle.fill";
    if ([category isEqualToString:@"Archives"]) return @"archivebox.fill";
    if ([category isEqualToString:@"Images"]) return @"photo.fill";
    if ([category isEqualToString:@"Private Vault"]) return @"lock.shield.fill";
    return @"doc.text.fill";
}

+ (UIColor *)tintColorForCategory:(NSString *)category spec:(PDMThemeSpec *)spec {
    if ([category isEqualToString:@"Videos"]) return spec.accentColor;
    if ([category isEqualToString:@"Audio"]) return spec.secondaryAccentColor;
    if ([category isEqualToString:@"Archives"]) return spec.warningColor;
    if ([category isEqualToString:@"Images"]) return spec.successColor;
    if ([category isEqualToString:@"Private Vault"]) return spec.dangerColor;
    return spec.mediaGlowColor;
}

@end
