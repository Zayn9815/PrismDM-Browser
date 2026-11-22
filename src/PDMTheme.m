// Copyright © 2026 PrismDM. All Rights Reserved. Proprietary and Confidential.

#import "PDMTheme.h"

NSNotificationName const PDMThemeDidChangeNotification = @"PDMThemeDidChangeNotification";
NSNotificationName const PDMLayoutDidChangeNotification = @"PDMLayoutDidChangeNotification";
NSNotificationName const PDMSettingsDidChangeNotification = @"PDMSettingsDidChangeNotification";

static NSString *const kPDMThemeIDKey = @"pdm_theme_id_v1";
static NSString *const kPDMLayoutPresetKey = @"pdm_layout_preset_v1";
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
            savedTheme = PDMThemeLiquidGlass;
        }
        _currentThemeID = (PDMThemeID)savedTheme;

        NSInteger savedLayout = [defaults integerForKey:kPDMLayoutPresetKey];
        if (savedLayout < 0 || savedLayout > PDMLayoutCompactPowerBar) {
            savedLayout = PDMLayoutFloatingBottom;
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
    // 1. Liquid Glass (Default)
    PDMThemeSpec *liquid = [[PDMThemeSpec alloc] init];
    liquid.themeID = PDMThemeLiquidGlass;
    liquid.displayName = @"Liquid Glass";
    liquid.subtitle = @"Frosted prism glass, luminous specular borders & sapphire-cyan aura";
    liquid.canvasColor = PDMRGB(0x060A16, 1.0);
    liquid.secondaryCanvasColor = PDMRGB(0x0C152B, 1.0);
    liquid.glassTintColor = PDMRGB(0x132240, 0.56);
    liquid.glassElevatedTintColor = PDMRGB(0x1B3159, 0.68);
    liquid.glassSpecularBorderColor = [UIColor colorWithWhite:1.0 alpha:0.24];
    liquid.glassTopRimColor = [UIColor colorWithRed:0.65 green:0.92 blue:1.0 alpha:0.42];
    liquid.accentColor = PDMRGB(0x38BDF8, 1.0);
    liquid.secondaryAccentColor = PDMRGB(0x6366F1, 1.0);
    liquid.mediaGlowColor = PDMRGB(0x22D3EE, 1.0);
    liquid.successColor = PDMRGB(0x34D399, 1.0);
    liquid.warningColor = PDMRGB(0xFBBF24, 1.0);
    liquid.dangerColor = PDMRGB(0xFB7185, 1.0);
    liquid.primaryTextColor = PDMRGB(0xF8FAFC, 1.0);
    liquid.secondaryTextColor = PDMRGB(0xB8C7E0, 1.0);
    liquid.tertiaryTextColor = PDMRGB(0x7A8EAD, 1.0);
    liquid.swatchPrimary = PDMRGB(0x38BDF8, 1.0);
    liquid.swatchSecondary = PDMRGB(0x6366F1, 1.0);
    liquid.blurStyle = UIBlurEffectStyleSystemUltraThinMaterialDark;
    liquid.interfaceStyle = UIUserInterfaceStyleDark;
    liquid.isDark = YES;
    liquid.isOLED = NO;

    // 2. Obsidian OLED
    PDMThemeSpec *oled = [[PDMThemeSpec alloc] init];
    oled.themeID = PDMThemeObsidianOLED;
    oled.displayName = @"Obsidian OLED";
    oled.subtitle = @"Pitch-black #000000 glass cards with crisp cobalt accents";
    oled.canvasColor = PDMRGB(0x000000, 1.0);
    oled.secondaryCanvasColor = PDMRGB(0x080A0F, 1.0);
    oled.glassTintColor = PDMRGB(0x0B0F19, 0.78);
    oled.glassElevatedTintColor = PDMRGB(0x121828, 0.86);
    oled.glassSpecularBorderColor = [UIColor colorWithWhite:1.0 alpha:0.17];
    oled.glassTopRimColor = PDMRGB(0x3B82F6, 0.45);
    oled.accentColor = PDMRGB(0x3B82F6, 1.0);
    oled.secondaryAccentColor = PDMRGB(0x60A5FA, 1.0);
    oled.mediaGlowColor = PDMRGB(0x38BDF8, 1.0);
    oled.successColor = PDMRGB(0x22C55E, 1.0);
    oled.warningColor = PDMRGB(0xF59E0B, 1.0);
    oled.dangerColor = PDMRGB(0xEF4444, 1.0);
    oled.primaryTextColor = PDMRGB(0xFFFFFF, 1.0);
    oled.secondaryTextColor = PDMRGB(0xA1ACC2, 1.0);
    oled.tertiaryTextColor = PDMRGB(0x667085, 1.0);
    oled.swatchPrimary = PDMRGB(0x000000, 1.0);
    oled.swatchSecondary = PDMRGB(0x3B82F6, 1.0);
    oled.blurStyle = UIBlurEffectStyleSystemChromeMaterialDark;
    oled.interfaceStyle = UIUserInterfaceStyleDark;
    oled.isDark = YES;
    oled.isOLED = YES;

    // 3. Brave Ember
    PDMThemeSpec *ember = [[PDMThemeSpec alloc] init];
    ember.themeID = PDMThemeBraveEmber;
    ember.displayName = @"Brave Ember";
    ember.subtitle = @"Deep charcoal glass with warm ember-orange & crimson shields";
    ember.canvasColor = PDMRGB(0x110E12, 1.0);
    ember.secondaryCanvasColor = PDMRGB(0x1C151B, 1.0);
    ember.glassTintColor = PDMRGB(0x24191F, 0.68);
    ember.glassElevatedTintColor = PDMRGB(0x312028, 0.78);
    ember.glassSpecularBorderColor = PDMRGB(0xFF8A5B, 0.28);
    ember.glassTopRimColor = PDMRGB(0xFF6B35, 0.46);
    ember.accentColor = PDMRGB(0xFF5A2C, 1.0);
    ember.secondaryAccentColor = PDMRGB(0xE11D48, 1.0);
    ember.mediaGlowColor = PDMRGB(0xFB923C, 1.0);
    ember.successColor = PDMRGB(0x34D399, 1.0);
    ember.warningColor = PDMRGB(0xFBBF24, 1.0);
    ember.dangerColor = PDMRGB(0xF43F5E, 1.0);
    ember.primaryTextColor = PDMRGB(0xFFF7F5, 1.0);
    ember.secondaryTextColor = PDMRGB(0xD4B8BC, 1.0);
    ember.tertiaryTextColor = PDMRGB(0x9C7E84, 1.0);
    ember.swatchPrimary = PDMRGB(0xFF5A2C, 1.0);
    ember.swatchSecondary = PDMRGB(0xE11D48, 1.0);
    ember.blurStyle = UIBlurEffectStyleSystemThinMaterialDark;
    ember.interfaceStyle = UIUserInterfaceStyleDark;
    ember.isDark = YES;
    ember.isOLED = NO;

    // 4. Chrome Minimal (Adaptive light/dark minimalist capsule chrome)
    PDMThemeSpec *chrome = [[PDMThemeSpec alloc] init];
    chrome.themeID = PDMThemeChromeMinimal;
    chrome.displayName = @"Chrome Minimal";
    chrome.subtitle = @"Adaptive pure light / dark minimalist capsule chrome";
    chrome.canvasColor = PDMDynamicColor(PDMRGB(0xF6F8FC, 1.0), PDMRGB(0x14161A, 1.0));
    chrome.secondaryCanvasColor = PDMDynamicColor(PDMRGB(0xEAEFF7, 1.0), PDMRGB(0x1E2128, 1.0));
    chrome.glassTintColor = PDMDynamicColor(PDMRGB(0xFFFFFF, 0.72), PDMRGB(0x232730, 0.74));
    chrome.glassElevatedTintColor = PDMDynamicColor(PDMRGB(0xFFFFFF, 0.88), PDMRGB(0x2D323E, 0.86));
    chrome.glassSpecularBorderColor = PDMDynamicColor([UIColor colorWithWhite:0.0 alpha:0.10], [UIColor colorWithWhite:1.0 alpha:0.16]);
    chrome.glassTopRimColor = PDMDynamicColor([UIColor colorWithWhite:1.0 alpha:0.90], [UIColor colorWithWhite:1.0 alpha:0.25]);
    chrome.accentColor = PDMDynamicColor(PDMRGB(0x1A73E8, 1.0), PDMRGB(0x8AB4F8, 1.0));
    chrome.secondaryAccentColor = PDMDynamicColor(PDMRGB(0x1967D2, 1.0), PDMRGB(0x669DF6, 1.0));
    chrome.mediaGlowColor = PDMDynamicColor(PDMRGB(0x0B8043, 1.0), PDMRGB(0x5BB974, 1.0));
    chrome.successColor = PDMDynamicColor(PDMRGB(0x188038, 1.0), PDMRGB(0x81C995, 1.0));
    chrome.warningColor = PDMDynamicColor(PDMRGB(0xE37400, 1.0), PDMRGB(0xFDD663, 1.0));
    chrome.dangerColor = PDMDynamicColor(PDMRGB(0xD93025, 1.0), PDMRGB(0xF28B82, 1.0));
    chrome.primaryTextColor = PDMDynamicColor(PDMRGB(0x111827, 1.0), PDMRGB(0xF3F4F6, 1.0));
    chrome.secondaryTextColor = PDMDynamicColor(PDMRGB(0x4B5563, 1.0), PDMRGB(0xB0B8C5, 1.0));
    chrome.tertiaryTextColor = PDMDynamicColor(PDMRGB(0x6B7280, 1.0), PDMRGB(0x7D8594, 1.0));
    chrome.swatchPrimary = PDMRGB(0xE8EEF8, 1.0);
    chrome.swatchSecondary = PDMRGB(0x1A73E8, 1.0);
    chrome.blurStyle = UIBlurEffectStyleSystemUltraThinMaterial;
    chrome.interfaceStyle = UIUserInterfaceStyleUnspecified;
    chrome.isDark = NO;
    chrome.isOLED = NO;

    // 5. Arctic Glacier
    PDMThemeSpec *arctic = [[PDMThemeSpec alloc] init];
    arctic.themeID = PDMThemeArcticGlacier;
    arctic.displayName = @"Arctic Glacier";
    arctic.subtitle = @"Airy icy frosted glass with crystal glacier-blue highlights";
    arctic.canvasColor = PDMRGB(0xEBF4FC, 1.0);
    arctic.secondaryCanvasColor = PDMRGB(0xDCEAF8, 1.0);
    arctic.glassTintColor = PDMRGB(0xFFFFFF, 0.64);
    arctic.glassElevatedTintColor = PDMRGB(0xFFFFFF, 0.80);
    arctic.glassSpecularBorderColor = PDMRGB(0x0284C7, 0.22);
    arctic.glassTopRimColor = [UIColor colorWithWhite:1.0 alpha:0.95];
    arctic.accentColor = PDMRGB(0x0284C7, 1.0);
    arctic.secondaryAccentColor = PDMRGB(0x06B6D4, 1.0);
    arctic.mediaGlowColor = PDMRGB(0x0EA5E9, 1.0);
    arctic.successColor = PDMRGB(0x059669, 1.0);
    arctic.warningColor = PDMRGB(0xD97706, 1.0);
    arctic.dangerColor = PDMRGB(0xE11D48, 1.0);
    arctic.primaryTextColor = PDMRGB(0x0C1C2E, 1.0);
    arctic.secondaryTextColor = PDMRGB(0x3B5672, 1.0);
    arctic.tertiaryTextColor = PDMRGB(0x64809B, 1.0);
    arctic.swatchPrimary = PDMRGB(0xBAE6FD, 1.0);
    arctic.swatchSecondary = PDMRGB(0x0284C7, 1.0);
    arctic.blurStyle = UIBlurEffectStyleSystemUltraThinMaterialLight;
    arctic.interfaceStyle = UIUserInterfaceStyleLight;
    arctic.isDark = NO;
    arctic.isOLED = NO;

    // 6. Cyber Midnight
    PDMThemeSpec *cyber = [[PDMThemeSpec alloc] init];
    cyber.themeID = PDMThemeCyberMidnight;
    cyber.displayName = @"Cyber Midnight";
    cyber.subtitle = @"Deep midnight-indigo glass with electric violet & neon teal";
    cyber.canvasColor = PDMRGB(0x080618, 1.0);
    cyber.secondaryCanvasColor = PDMRGB(0x120E2E, 1.0);
    cyber.glassTintColor = PDMRGB(0x1B1442, 0.62);
    cyber.glassElevatedTintColor = PDMRGB(0x271C5C, 0.74);
    cyber.glassSpecularBorderColor = PDMRGB(0xA855F7, 0.34);
    cyber.glassTopRimColor = PDMRGB(0x2DD4BF, 0.50);
    cyber.accentColor = PDMRGB(0xA855F7, 1.0);
    cyber.secondaryAccentColor = PDMRGB(0x14B8A6, 1.0);
    cyber.mediaGlowColor = PDMRGB(0x2DD4BF, 1.0);
    cyber.successColor = PDMRGB(0x2DD4BF, 1.0);
    cyber.warningColor = PDMRGB(0xFACC15, 1.0);
    cyber.dangerColor = PDMRGB(0xF43F5E, 1.0);
    cyber.primaryTextColor = PDMRGB(0xF5F3FF, 1.0);
    cyber.secondaryTextColor = PDMRGB(0xC4B5FD, 1.0);
    cyber.tertiaryTextColor = PDMRGB(0x8B7EC8, 1.0);
    cyber.swatchPrimary = PDMRGB(0xA855F7, 1.0);
    cyber.swatchSecondary = PDMRGB(0x14B8A6, 1.0);
    cyber.blurStyle = UIBlurEffectStyleSystemUltraThinMaterialDark;
    cyber.interfaceStyle = UIUserInterfaceStyleDark;
    cyber.isDark = YES;
    cyber.isOLED = NO;

    return @[liquid, oled, ember, chrome, arctic, cyber];
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
        case PDMLayoutFloatingBottom: return @"Liquid Floating Bottom";
        case PDMLayoutChromeMinimalTop: return @"Chrome Minimal Top";
        case PDMLayoutCompactPowerBar: return @"Compact Power Bar";
    }
    return @"Liquid Floating Bottom";
}

- (NSString *)subtitleForLayoutPreset:(PDMLayoutPreset)preset {
    switch (preset) {
        case PDMLayoutFloatingBottom: return @"Thumb-friendly floating bottom glass capsule with auto-hide";
        case PDMLayoutChromeMinimalTop: return @"Single top glass omnibar + slim translucent bottom nav strip";
        case PDMLayoutCompactPowerBar: return @"High-density Liquid Glass command bar with all controls visible";
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
        case PDMSearchEngineGoogle: return @"magnifyingglass.circle.fill";
        case PDMSearchEngineDuckDuckGo: return @"shield.lefthalf.filled";
        case PDMSearchEngineBrave: return @"flame.fill";
        case PDMSearchEngineBing: return @"globe.americas.fill";
        case PDMSearchEngineYouTube: return @"play.rectangle.fill";
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
    UIFont *base = [UIFont systemFontOfSize:size weight:weight];
    UIFontDescriptor *desc = [base.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
    if (desc) {
        return [UIFont fontWithDescriptor:desc size:size];
    }
    return base;
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
