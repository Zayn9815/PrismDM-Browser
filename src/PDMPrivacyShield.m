// Copyright © 2026 PrismDM. All Rights Reserved. Proprietary and Confidential.

#import "PDMPrivacyShield.h"

NSNotificationName const PDMPrivacyStatsDidChangeNotification = @"PDMPrivacyStatsDidChangeNotification";

static NSString *const kPDMStatsAdsKey = @"pdm_stats_ads_v1";
static NSString *const kPDMStatsTrackersKey = @"pdm_stats_trackers_v1";
static NSString *const kPDMStatsPopupsKey = @"pdm_stats_popups_v1";
static NSString *const kPDMStatsBytesKey = @"pdm_stats_bytes_saved_v1";
static NSString *const kPDMStatsDownloadsKey = @"pdm_stats_downloads_v1";
static NSString *const kPDMSiteSettingsKey = @"pdm_site_shield_settings_v1";
static NSString *const kPDMAdRuleListIdentifier = @"com.prismdm.browser.rules.adtracker.v1";
static NSString *const kPDMThirdPartyScriptRuleListIdentifier = @"com.prismdm.browser.rules.3pscripts.v1";

#pragma mark - PDMSiteShieldSettings

@implementation PDMSiteShieldSettings

+ (instancetype)defaultSettingsForHost:(NSString *)host {
    PDMSiteShieldSettings *s = [[PDMSiteShieldSettings alloc] init];
    s.host = host.lowercaseString ?: @"";
    s.shieldsEnabled = YES;
    s.blockPopups = YES;
    s.blockThirdPartyScripts = NO;
    s.autoUpgradeHTTPS = YES;
    s.forceDarkMode = [PDMThemeManager sharedManager].globalForceDarkMode;
    s.useDesktopUserAgent = NO;
    return s;
}

- (NSDictionary<NSString *, id> *)toDictionary {
    return @{
        @"shieldsEnabled": @(self.shieldsEnabled),
        @"blockPopups": @(self.blockPopups),
        @"blockThirdPartyScripts": @(self.blockThirdPartyScripts),
        @"autoUpgradeHTTPS": @(self.autoUpgradeHTTPS),
        @"forceDarkMode": @(self.forceDarkMode),
        @"useDesktopUserAgent": @(self.useDesktopUserAgent)
    };
}

+ (instancetype)fromDictionary:(NSDictionary<NSString *, id> *)dict host:(NSString *)host {
    PDMSiteShieldSettings *s = [self defaultSettingsForHost:host];
    if (![dict isKindOfClass:[NSDictionary class]]) {
        return s;
    }
    if (dict[@"shieldsEnabled"] != nil) s.shieldsEnabled = [dict[@"shieldsEnabled"] boolValue];
    if (dict[@"blockPopups"] != nil) s.blockPopups = [dict[@"blockPopups"] boolValue];
    if (dict[@"blockThirdPartyScripts"] != nil) s.blockThirdPartyScripts = [dict[@"blockThirdPartyScripts"] boolValue];
    if (dict[@"autoUpgradeHTTPS"] != nil) s.autoUpgradeHTTPS = [dict[@"autoUpgradeHTTPS"] boolValue];
    if (dict[@"forceDarkMode"] != nil) s.forceDarkMode = [dict[@"forceDarkMode"] boolValue];
    if (dict[@"useDesktopUserAgent"] != nil) s.useDesktopUserAgent = [dict[@"useDesktopUserAgent"] boolValue];
    return s;
}

@end

#pragma mark - PDMPrivacyShieldEngine

@interface PDMPrivacyShieldEngine ()
@property (nonatomic, assign, readwrite) NSInteger adsBlocked;
@property (nonatomic, assign, readwrite) NSInteger trackersBlocked;
@property (nonatomic, assign, readwrite) NSInteger popupsBlocked;
@property (nonatomic, assign, readwrite) int64_t bytesSaved;
@property (nonatomic, assign, readwrite) NSInteger downloadsCompleted;
@property (nonatomic, strong, readwrite, nullable) WKContentRuleList *adTrackerRuleList;
@property (nonatomic, strong, readwrite, nullable) WKContentRuleList *thirdPartyScriptRuleList;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *domainBlockedCounts;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *siteSettingsMap;
@end

@implementation PDMPrivacyShieldEngine

+ (instancetype)sharedEngine {
    static PDMPrivacyShieldEngine *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[PDMPrivacyShieldEngine alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _adsBlocked = [defaults integerForKey:kPDMStatsAdsKey];
        _trackersBlocked = [defaults integerForKey:kPDMStatsTrackersKey];
        _popupsBlocked = [defaults integerForKey:kPDMStatsPopupsKey];
        _bytesSaved = (int64_t)[defaults integerForKey:kPDMStatsBytesKey];
        _downloadsCompleted = [defaults integerForKey:kPDMStatsDownloadsKey];
        _domainBlockedCounts = [NSMutableDictionary dictionary];

        NSDictionary *saved = [defaults dictionaryForKey:kPDMSiteSettingsKey];
        _siteSettingsMap = saved ? [saved mutableCopy] : [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSString *)buildAdTrackerContentRulesJSON {
    NSArray<NSString *> *blockedDomains = @[
        @"doubleclick\\.net",
        @"googlesyndication\\.com",
        @"googleadservices\\.com",
        @"google-analytics\\.com",
        @"googletagmanager\\.com",
        @"adservice\\.google\\.",
        @"pagead2\\.googlesyndication\\.com",
        @"ads\\.youtube\\.com",
        @"facebook\\.net/en_US/fbevents\\.js",
        @"connect\\.facebook\\.net/.*fbevents",
        @"pixel\\.facebook\\.com",
        @"ads-twitter\\.com",
        @"static\\.ads-twitter\\.com",
        @"analytics\\.tiktok\\.com",
        @"amazon-adsystem\\.com",
        @"adnxs\\.com",
        @"rubiconproject\\.com",
        @"pubmatic\\.com",
        @"openx\\.net",
        @"casalemedia\\.com",
        @"criteo\\.com",
        @"criteo\\.net",
        @"outbrain\\.com",
        @"taboola\\.com",
        @"scorecardresearch\\.com",
        @"quantserve\\.com",
        @"hotjar\\.com",
        @"mixpanel\\.com",
        @"segment\\.io",
        @"segment\\.com",
        @"amplitude\\.com",
        @"newrelic\\.com",
        @"nr-data\\.net",
        @"chartbeat\\.com",
        @"moatads\\.com",
        @"doubleverify\\.com",
        @"adsrvr\\.org",
        @"adform\\.net",
        @"smartadserver\\.com",
        @"yieldmo\\.com",
        @"sharethrough\\.com",
        @"mediavine\\.com",
        @"adthrive\\.com",
        @"popads\\.net",
        @"popcash\\.net",
        @"propellerads\\.com",
        @"exoclick\\.com",
        @"juicyads\\.com",
        @"trafficjunky\\.net",
        @"mgid\\.com",
        @"revcontent\\.com",
        @"zedo\\.com",
        @"bidswitch\\.net",
        @"mathtag\\.com",
        @"rlcdn\\.com",
        @"krxd\\.net",
        @"bluekai\\.com",
        @"demdex\\.net",
        @"omtrdc\\.net",
        @"2o7\\.net",
        @"bing\\.com/bat\\.js",
        @"clarity\\.ms",
        @"fullstory\\.com",
        @"mouseflow\\.com",
        @"crazyegg\\.com",
        @"optimizely\\.com",
        @"branch\\.io",
        @"adjust\\.com",
        @"appsflyer\\.com",
        @"onesignal\\.com",
        @"pushwoosh\\.com",
        @"track\\.adform\\.net"
    ];

    NSMutableArray<NSDictionary<NSString *, id> *> *rules = [NSMutableArray arrayWithCapacity:blockedDomains.count + 4];
    for (NSString *pattern in blockedDomains) {
        NSString *filter = [NSString stringWithFormat:@"^https?://([^/]+\\.)?%@", pattern];
        [rules addObject:@{
            @"trigger": @{
                @"url-filter": filter,
                @"load-type": @[@"third-party"]
            },
            @"action": @{
                @"type": @"block"
            }
        }];
    }

    // Common ad path heuristics on third-party scripts/images
    [rules addObject:@{
        @"trigger": @{
            @"url-filter": @"^https?://.*/(ads|adserver|adsystem|banner_ads|popunder|prebid)/",
            @"load-type": @[@"third-party"],
            @"resource-type": @[@"script", @"image", @"raw"]
        },
        @"action": @{
            @"type": @"block"
        }
    }];

    // Hide common ad containers via CSS content blocker rule
    [rules addObject:@{
        @"trigger": @{
            @"url-filter": @".*"
        },
        @"action": @{
            @"type": @"css-display-none",
            @"selector": @"ins.adsbygoogle, [id^='google_ads_iframe'], .ad-banner, .ad-container, .sponsored-ad, [data-ad-slot], .taboola-widget, .outbrain-widget"
        }
    }];

    NSError *err = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:rules options:0 error:&err];
    if (!jsonData || err) {
        return @"[]";
    }
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] ?: @"[]";
}

- (NSString *)buildThirdPartyScriptRulesJSON {
    NSArray<NSDictionary<NSString *, id> *> *rules = @[
        @{
            @"trigger": @{
                @"url-filter": @".*",
                @"load-type": @[@"third-party"],
                @"resource-type": @[@"script"]
            },
            @"action": @{
                @"type": @"block"
            }
        }
    ];
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:rules options:0 error:nil];
    return jsonData ? ([[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] ?: @"[]") : @"[]";
}

- (void)prepareContentRuleListsWithCompletion:(nullable void (^)(void))completion {
    WKContentRuleListStore *store = [WKContentRuleListStore defaultStore];
    if (!store) {
        if (completion) completion();
        return;
    }

    dispatch_group_t group = dispatch_group_create();
    __weak typeof(self) weakSelf = self;

    dispatch_group_enter(group);
    NSString *adJSON = [self buildAdTrackerContentRulesJSON];
    [store compileContentRuleListForIdentifier:kPDMAdRuleListIdentifier
                        encodedContentRuleList:adJSON
                             completionHandler:^(WKContentRuleList * _Nullable list, NSError * _Nullable __unused error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf && list) {
            strongSelf.adTrackerRuleList = list;
        }
        dispatch_group_leave(group);
    }];

    dispatch_group_enter(group);
    NSString *scriptJSON = [self buildThirdPartyScriptRulesJSON];
    [store compileContentRuleListForIdentifier:kPDMThirdPartyScriptRuleListIdentifier
                        encodedContentRuleList:scriptJSON
                             completionHandler:^(WKContentRuleList * _Nullable list, NSError * _Nullable __unused error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf && list) {
            strongSelf.thirdPartyScriptRuleList = list;
        }
        dispatch_group_leave(group);
    }];

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if (completion) {
            completion();
        }
    });
}

- (void)applyRulesToUserContentController:(WKUserContentController *)ucc forHost:(nullable NSString *)host {
    [ucc removeAllContentRuleLists];
    PDMSiteShieldSettings *settings = [self settingsForHost:host];
    if (!settings.shieldsEnabled) {
        return;
    }
    if (self.adTrackerRuleList) {
        [ucc addContentRuleList:self.adTrackerRuleList];
    }
    if (settings.blockThirdPartyScripts && self.thirdPartyScriptRuleList) {
        [ucc addContentRuleList:self.thirdPartyScriptRuleList];
    }
}

#pragma mark - Per-Site Settings

- (PDMSiteShieldSettings *)settingsForHost:(nullable NSString *)host {
    NSString *key = host.lowercaseString;
    if (key.length == 0) {
        return [PDMSiteShieldSettings defaultSettingsForHost:@""];
    }
    NSDictionary<NSString *, id> *stored = self.siteSettingsMap[key];
    if (stored) {
        return [PDMSiteShieldSettings fromDictionary:stored host:key];
    }
    return [PDMSiteShieldSettings defaultSettingsForHost:key];
}

- (void)saveSettings:(PDMSiteShieldSettings *)settings {
    if (settings.host.length == 0) {
        return;
    }
    self.siteSettingsMap[settings.host.lowercaseString] = [settings toDictionary];
    [[NSUserDefaults standardUserDefaults] setObject:self.siteSettingsMap forKey:kPDMSiteSettingsKey];
}

#pragma mark - Stats

- (NSInteger)blockedCountForHost:(nullable NSString *)host {
    if (host.length == 0) return 0;
    return self.domainBlockedCounts[host.lowercaseString].integerValue;
}

- (void)persistStats {
    dispatch_block_t work = ^{
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setInteger:self.adsBlocked forKey:kPDMStatsAdsKey];
        [defaults setInteger:self.trackersBlocked forKey:kPDMStatsTrackersKey];
        [defaults setInteger:self.popupsBlocked forKey:kPDMStatsPopupsKey];
        [defaults setInteger:(NSInteger)self.bytesSaved forKey:kPDMStatsBytesKey];
        [defaults setInteger:self.downloadsCompleted forKey:kPDMStatsDownloadsKey];
        [[NSNotificationCenter defaultCenter] postNotificationName:PDMPrivacyStatsDidChangeNotification object:self];
    };
    if ([NSThread isMainThread]) {
        work();
    } else {
        dispatch_async(dispatch_get_main_queue(), work);
    }
}

- (void)recordBlockedAdForHost:(nullable NSString *)host count:(NSInteger)count {
    if (count <= 0) return;
    NSString *hostCopy = [host copy];
    dispatch_block_t work = ^{
        self.adsBlocked += count;
        self.bytesSaved += (int64_t)count * 64 * 1024;
        if (hostCopy.length > 0) {
            NSString *k = hostCopy.lowercaseString;
            self.domainBlockedCounts[k] = @(self.domainBlockedCounts[k].integerValue + count);
        }
        [self persistStats];
    };
    if ([NSThread isMainThread]) {
        work();
    } else {
        dispatch_async(dispatch_get_main_queue(), work);
    }
}

- (void)recordBlockedTrackerForHost:(nullable NSString *)host count:(NSInteger)count {
    if (count <= 0) return;
    NSString *hostCopy = [host copy];
    dispatch_block_t work = ^{
        self.trackersBlocked += count;
        self.bytesSaved += (int64_t)count * 28 * 1024;
        if (hostCopy.length > 0) {
            NSString *k = hostCopy.lowercaseString;
            self.domainBlockedCounts[k] = @(self.domainBlockedCounts[k].integerValue + count);
        }
        [self persistStats];
    };
    if ([NSThread isMainThread]) {
        work();
    } else {
        dispatch_async(dispatch_get_main_queue(), work);
    }
}

- (void)recordBlockedPopupForHost:(nullable NSString *)host {
    NSString *hostCopy = [host copy];
    dispatch_block_t work = ^{
        self.popupsBlocked += 1;
        self.bytesSaved += 96 * 1024;
        if (hostCopy.length > 0) {
            NSString *k = hostCopy.lowercaseString;
            self.domainBlockedCounts[k] = @(self.domainBlockedCounts[k].integerValue + 1);
        }
        [self persistStats];
    };
    if ([NSThread isMainThread]) {
        work();
    } else {
        dispatch_async(dispatch_get_main_queue(), work);
    }
}

- (void)recordDownloadCompletedWithBytes:(int64_t)bytes {
    dispatch_block_t work = ^{
        self.downloadsCompleted += 1;
        if (bytes > 0) {
            self.bytesSaved += (bytes / 20); // efficiency credit
        }
        [self persistStats];
    };
    if ([NSThread isMainThread]) {
        work();
    } else {
        dispatch_async(dispatch_get_main_queue(), work);
    }
}

- (void)resetStats {
    dispatch_block_t work = ^{
        self.adsBlocked = 0;
        self.trackersBlocked = 0;
        self.popupsBlocked = 0;
        self.bytesSaved = 0;
        self.downloadsCompleted = 0;
        [self.domainBlockedCounts removeAllObjects];
        [self persistStats];
    };
    if ([NSThread isMainThread]) {
        work();
    } else {
        dispatch_async(dispatch_get_main_queue(), work);
    }
}

#pragma mark - HTTPS Upgrade & User Agents

- (NSURL *)upgradedURLIfNeeded:(NSURL *)url {
    if (!url || ![url.scheme.lowercaseString isEqualToString:@"http"]) {
        return url;
    }
    NSString *host = url.host.lowercaseString;
    if (host.length == 0 || [host isEqualToString:@"localhost"] || [host hasPrefix:@"127."] || [host hasPrefix:@"192.168."] || [host hasPrefix:@"10."]) {
        return url;
    }
    PDMSiteShieldSettings *settings = [self settingsForHost:host];
    if (!settings.shieldsEnabled || !settings.autoUpgradeHTTPS) {
        return url;
    }
    NSURLComponents *comps = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    comps.scheme = @"https";
    return comps.URL ?: url;
}

- (NSString *)mobileUserAgent {
    return @"Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1";
}

- (NSString *)desktopUserAgent {
    return @"Mozilla/5.0 (Macintosh; Intel Mac OS X 15_4) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15";
}

#pragma mark - User Scripts (Cosmetic Ad/Cookie Hider, Force Dark Mode, Reader Mode)

- (WKUserScript *)cosmeticAdHiderUserScript {
    NSString *js = @""
    "(function(){"
    "  if (window.__pdmCosmeticInjected) return;"
    "  window.__pdmCosmeticInjected = true;"
    "  var selectors = ["
    "    '[id*=\"cookie-banner\" i]', '[class*=\"cookie-banner\" i]', '[id*=\"cookie-consent\" i]', '[class*=\"cookie-consent\" i]',"
    "    '[id*=\"onetrust-banner\" i]', '#onetrust-consent-sdk', '#CybotCookiebotDialog', '.qc-cmp2-container',"
    "    '[aria-label*=\"cookie\" i][role=\"dialog\"]', '[class*=\"gdpr-banner\" i]', '[id*=\"sp_message_container\"]',"
    "    'ins.adsbygoogle', '[id^=\"google_ads_iframe\"]', '[class*=\"sticky-ad\" i]', '[id*=\"sticky-ad\" i]',"
    "    '[class*=\"ad-overlay\" i]', '[class*=\"floating-ad\" i]', '.ad-slot-wrapper', '.taboola-widget', '.outbrain-widget'"
    "  ];"
    "  var hiddenCount = 0;"
    "  function sweep(){"
    "    var newlyHidden = 0;"
    "    try {"
    "      var joined = selectors.join(',');"
    "      var nodes = document.querySelectorAll(joined);"
    "      for (var i = 0; i < nodes.length; i++) {"
    "        var el = nodes[i];"
    "        if (!el.dataset.pdmHidden) {"
    "          el.dataset.pdmHidden = '1';"
    "          el.style.setProperty('display', 'none', 'important');"
    "          el.style.setProperty('visibility', 'hidden', 'important');"
    "          newlyHidden++;"
    "        }"
    "      }"
    "      if (document.body && document.body.style.overflow === 'hidden' && newlyHidden > 0) {"
    "        document.body.style.overflow = 'auto';"
    "      }"
    "    } catch(e) {}"
    "    if (newlyHidden > 0) {"
    "      hiddenCount += newlyHidden;"
    "      try {"
    "        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.pdmShield) {"
    "          window.webkit.messageHandlers.pdmShield.postMessage({type:'cosmetic', count:newlyHidden, host:location.hostname});"
    "        }"
    "      } catch(e) {}"
    "    }"
    "  }"
    "  if (document.readyState === 'loading') {"
    "    document.addEventListener('DOMContentLoaded', sweep, {once:true});"
    "  } else { sweep(); }"
    "  setTimeout(sweep, 900);"
    "  setTimeout(sweep, 2600);"
    "})();";
    return [[WKUserScript alloc] initWithSource:js
                                  injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                               forMainFrameOnly:YES];
}

- (NSString *)toggleDarkModeJavaScript:(BOOL)enable {
    if (!enable) {
        return @"(function(){ var s = document.getElementById('__pdm_force_dark_css'); if (s) s.remove(); })();";
    }
    return @""
    "(function(){"
    "  var id = '__pdm_force_dark_css';"
    "  if (document.getElementById(id)) return;"
    "  var style = document.createElement('style');"
    "  style.id = id;"
    "  style.textContent = '"
    "    html { filter: invert(0.92) hue-rotate(180deg) !important; background: #0c0e14 !important; }"
    "    img, video, picture, canvas, svg, iframe, [style*=\"background-image\"] { filter: invert(1) hue-rotate(180deg) !important; }"
    "    img[src$=\".svg\"] { filter: none !important; }"
    "  ';"
    "  (document.head || document.documentElement).appendChild(style);"
    "})();";
}

- (WKUserScript *)forceDarkModeUserScript {
    return [[WKUserScript alloc] initWithSource:[self toggleDarkModeJavaScript:YES]
                                  injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                               forMainFrameOnly:YES];
}

- (NSString *)readerModeExtractionJavaScript {
    return @""
    "(function(){"
    "  var title = document.title || '';"
    "  var h1 = document.querySelector('h1');"
    "  if (h1 && h1.innerText && h1.innerText.trim().length > 4) title = h1.innerText.trim();"
    "  var container = document.querySelector('article') || document.querySelector('main') || document.querySelector('[role=\"main\"]') || document.body;"
    "  var blocks = [];"
    "  if (container) {"
    "    var nodes = container.querySelectorAll('h1, h2, h3, p, blockquote, li, img');"
    "    for (var i = 0; i < nodes.length && blocks.length < 300; i++) {"
    "      var n = nodes[i];"
    "      var tag = n.tagName.toLowerCase();"
    "      if (tag === 'img') {"
    "        var src = n.currentSrc || n.src || '';"
    "        if (src && (n.naturalWidth || 0) >= 240) {"
    "          blocks.push({type:'img', src:src, alt:(n.alt||'')});"
    "        }"
    "      } else {"
    "        var txt = (n.innerText || '').trim();"
    "        if (txt.length >= 20 || tag === 'h2' || tag === 'h3') {"
    "          blocks.push({type:tag, text:txt});"
    "        }"
    "      }"
    "    }"
    "  }"
    "  return JSON.stringify({title:title, url:location.href, host:location.hostname, blocks:blocks});"
    "})();";
}

#pragma mark - Clear Data

- (void)clearDataForHost:(NSString *)host completion:(nullable dispatch_block_t)completion {
    if (host.length == 0) {
        if (completion) completion();
        return;
    }
    WKWebsiteDataStore *store = [WKWebsiteDataStore defaultDataStore];
    NSSet<NSString *> *types = [WKWebsiteDataStore allWebsiteDataTypes];
    NSString *target = host.lowercaseString;
    [store fetchDataRecordsOfTypes:types completionHandler:^(NSArray<WKWebsiteDataRecord *> *records) {
        NSMutableArray<WKWebsiteDataRecord *> *matching = [NSMutableArray array];
        for (WKWebsiteDataRecord *rec in records) {
            NSString *disp = rec.displayName.lowercaseString;
            if ([target containsString:disp] || [disp containsString:target]) {
                [matching addObject:rec];
            }
        }
        [store removeDataOfTypes:types forDataRecords:matching completionHandler:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion();
            });
        }];
    }];
}

- (void)clearAllBrowsingDataWithCompletion:(nullable dispatch_block_t)completion {
    WKWebsiteDataStore *store = [WKWebsiteDataStore defaultDataStore];
    NSSet<NSString *> *types = [WKWebsiteDataStore allWebsiteDataTypes];
    [store removeDataOfTypes:types modifiedSince:[NSDate distantPast] completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion();
        });
    }];
}

@end

#pragma mark - PDMShieldSheetViewController

@interface PDMShieldSheetViewController ()
@property (nonatomic, strong) PDMSiteShieldSettings *siteSettings;
@property (nonatomic, strong) UILabel *heroCountLabel;
@property (nonatomic, strong) UILabel *heroStatusLabel;
@property (nonatomic, strong) UISwitch *masterSwitch;
@property (nonatomic, strong) UISwitch *popupsSwitch;
@property (nonatomic, strong) UISwitch *scriptsSwitch;
@property (nonatomic, strong) UISwitch *httpsSwitch;
@property (nonatomic, strong) UISwitch *darkModeSwitch;
@property (nonatomic, strong) UISwitch *desktopSwitch;
@end

@implementation PDMShieldSheetViewController

- (void)viewDidLoad {
    self.sheetTitle = @"Privacy Shields";
    self.sheetSubtitle = (self.currentHost.length > 0) ? self.currentHost : @"Global Protection";
    self.sheetSymbolName = @"shield.lefthalf.filled.badge.checkmark";
    self.allowsMediumDetent = YES;
    self.prefersLargeDefaultDetent = YES;
    [super viewDidLoad];

    self.siteSettings = [[PDMPrivacyShieldEngine sharedEngine] settingsForHost:self.currentHost];
    [self buildContent];
}

- (void)buildContent {
    PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;
    PDMPrivacyShieldEngine *engine = [PDMPrivacyShieldEngine sharedEngine];
    NSInteger siteCount = [engine blockedCountForHost:self.currentHost];

    // Hero Ring / Pill Glass Card
    PDMGlassView *heroCard = [[PDMGlassView alloc] initWithCornerRadius:22.0 elevated:YES];
    heroCard.customBorderColor = [spec.accentColor colorWithAlphaComponent:0.45];

    UIStackView *heroStack = [[UIStackView alloc] init];
    heroStack.axis = UILayoutConstraintAxisHorizontal;
    heroStack.alignment = UIStackViewAlignmentCenter;
    heroStack.spacing = 16.0;
    heroStack.translatesAutoresizingMaskIntoConstraints = NO;
    [heroCard.contentView addSubview:heroStack];

    // Ring badge
    PDMGlassView *ring = [[PDMGlassView alloc] initWithCornerRadius:34.0 elevated:NO];
    ring.showAmbientShadow = NO;
    ring.customBorderColor = spec.accentColor;
    ring.customTintColor = [spec.accentColor colorWithAlphaComponent:0.18];
    ring.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [ring.widthAnchor constraintEqualToConstant:68.0],
        [ring.heightAnchor constraintEqualToConstant:68.0]
    ]];

    self.heroCountLabel = [[UILabel alloc] init];
    self.heroCountLabel.text = [NSString stringWithFormat:@"%ld", (long)siteCount];
    self.heroCountLabel.font = [[PDMThemeManager sharedManager] tabularFontOfSize:24.0 weight:UIFontWeightHeavy];
    self.heroCountLabel.textColor = spec.accentColor;
    self.heroCountLabel.textAlignment = NSTextAlignmentCenter;
    self.heroCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [ring.contentView addSubview:self.heroCountLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.heroCountLabel.centerXAnchor constraintEqualToAnchor:ring.contentView.centerXAnchor],
        [self.heroCountLabel.centerYAnchor constraintEqualToAnchor:ring.contentView.centerYAnchor]
    ]];
    [heroStack addArrangedSubview:ring];

    UIStackView *heroText = [[UIStackView alloc] init];
    heroText.axis = UILayoutConstraintAxisVertical;
    heroText.spacing = 3.0;
    [heroStack addArrangedSubview:heroText];

    self.heroStatusLabel = [[UILabel alloc] init];
    self.heroStatusLabel.font = [[PDMThemeManager sharedManager] displayFontOfSize:17.0 weight:UIFontWeightBold];
    self.heroStatusLabel.textColor = spec.primaryTextColor;
    [heroText addArrangedSubview:self.heroStatusLabel];

    UILabel *totalSub = [[UILabel alloc] init];
    totalSub.text = [NSString stringWithFormat:@"Blocked on this site · %ld total saved (%@)",
                     (long)(engine.adsBlocked + engine.trackersBlocked + engine.popupsBlocked),
                     [PDMThemeManager formatBytes:engine.bytesSaved]];
    totalSub.font = [[PDMThemeManager sharedManager] tabularFontOfSize:12.0 weight:UIFontWeightMedium];
    totalSub.textColor = spec.secondaryTextColor;
    totalSub.numberOfLines = 2;
    [heroText addArrangedSubview:totalSub];

    self.masterSwitch = [[UISwitch alloc] init];
    self.masterSwitch.on = self.siteSettings.shieldsEnabled;
    self.masterSwitch.onTintColor = spec.accentColor;
    [self.masterSwitch addTarget:self action:@selector(handleSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [heroStack addArrangedSubview:self.masterSwitch];

    [NSLayoutConstraint activateConstraints:@[
        [heroStack.topAnchor constraintEqualToAnchor:heroCard.contentView.topAnchor constant:16.0],
        [heroStack.bottomAnchor constraintEqualToAnchor:heroCard.contentView.bottomAnchor constant:-16.0],
        [heroStack.leadingAnchor constraintEqualToAnchor:heroCard.contentView.leadingAnchor constant:16.0],
        [heroStack.trailingAnchor constraintEqualToAnchor:heroCard.contentView.trailingAnchor constant:-16.0]
    ]];
    [self.contentStack addArrangedSubview:heroCard];

    [self.contentStack addArrangedSubview:[self sectionHeaderWithTitle:@"Per-Site Protections" detail:@"Instant Live Apply"]];

    PDMGlassView *controlsCard = [[PDMGlassView alloc] initWithCornerRadius:20.0 elevated:NO];
    controlsCard.showAmbientShadow = NO;
    UIStackView *controlsStack = [[UIStackView alloc] init];
    controlsStack.axis = UILayoutConstraintAxisVertical;
    controlsStack.spacing = 0.0;
    controlsStack.translatesAutoresizingMaskIntoConstraints = NO;
    [controlsCard.contentView addSubview:controlsStack];
    [NSLayoutConstraint activateConstraints:@[
        [controlsStack.topAnchor constraintEqualToAnchor:controlsCard.contentView.topAnchor],
        [controlsStack.bottomAnchor constraintEqualToAnchor:controlsCard.contentView.bottomAnchor],
        [controlsStack.leadingAnchor constraintEqualToAnchor:controlsCard.contentView.leadingAnchor],
        [controlsStack.trailingAnchor constraintEqualToAnchor:controlsCard.contentView.trailingAnchor]
    ]];

    self.popupsSwitch = [self addToggleRowTo:controlsStack
                                      symbol:@"rectangle.on.rectangle.slash"
                                       title:@"Block Popups & Redirects"
                                    subtitle:@"Stops script-triggered popups while keeping tapped links"
                                        isOn:self.siteSettings.blockPopups
                                   separator:YES];

    self.scriptsSwitch = [self addToggleRowTo:controlsStack
                                       symbol:@"chevron.left.forwardslash.chevron.right"
                                        title:@"Block Third-Party Scripts"
                                     subtitle:@"Aggressive script isolation via native WKContentRuleList"
                                         isOn:self.siteSettings.blockThirdPartyScripts
                                    separator:YES];

    self.httpsSwitch = [self addToggleRowTo:controlsStack
                                     symbol:@"lock.fill"
                                      title:@"Auto-Upgrade HTTP → HTTPS"
                                   subtitle:@"Automatically encrypt insecure connections"
                                       isOn:self.siteSettings.autoUpgradeHTTPS
                                  separator:YES];

    self.darkModeSwitch = [self addToggleRowTo:controlsStack
                                        symbol:@"moon.stars.fill"
                                         title:@"Force Dark Mode"
                                      subtitle:@"Smart CSS dark injection preserving photos & video"
                                          isOn:self.siteSettings.forceDarkMode
                                     separator:YES];

    self.desktopSwitch = [self addToggleRowTo:controlsStack
                                       symbol:@"desktopcomputer"
                                        title:@"Request Desktop Website"
                                     subtitle:@"Send macOS Safari desktop User-Agent for this site"
                                         isOn:self.siteSettings.useDesktopUserAgent
                                    separator:NO];

    [self.contentStack addArrangedSubview:controlsCard];

    if (self.currentHost.length > 0) {
        PDMGlassPillButton *clearBtn = [[PDMGlassPillButton alloc] initWithTitle:[NSString stringWithFormat:@"Clear Cookies & Data for %@", self.currentHost]
                                                                      symbolName:@"trash.fill"];
        clearBtn.customAccentColor = spec.dangerColor;
        clearBtn.glowing = YES;
        clearBtn.verticalPadding = 12.0;
        [clearBtn addTarget:self action:@selector(handleClearSiteDataTap) forControlEvents:UIControlEventTouchUpInside];
        [self.contentStack addArrangedSubview:clearBtn];
    }

    [self updateHeroStatus];
}

- (UISwitch *)addToggleRowTo:(UIStackView *)stack
                      symbol:(NSString *)symbol
                       title:(NSString *)title
                    subtitle:(NSString *)subtitle
                        isOn:(BOOL)isOn
                   separator:(BOOL)separator {
    PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;
    UIView *container = [[UIView alloc] init];

    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 12.0;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:row];

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightSemibold];
    UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol withConfiguration:cfg]];
    iv.tintColor = spec.accentColor;
    iv.contentMode = UIViewContentModeScaleAspectFit;
    [iv.widthAnchor constraintEqualToConstant:24.0].active = YES;
    [row addArrangedSubview:iv];

    UIStackView *vStack = [[UIStackView alloc] init];
    vStack.axis = UILayoutConstraintAxisVertical;
    vStack.spacing = 2.0;
    [row addArrangedSubview:vStack];

    UILabel *tLbl = [[UILabel alloc] init];
    tLbl.text = title;
    tLbl.font = [[PDMThemeManager sharedManager] bodyFontOfSize:14.5 weight:UIFontWeightSemibold];
    tLbl.textColor = spec.primaryTextColor;
    [vStack addArrangedSubview:tLbl];

    UILabel *sLbl = [[UILabel alloc] init];
    sLbl.text = subtitle;
    sLbl.font = [[PDMThemeManager sharedManager] bodyFontOfSize:11.5 weight:UIFontWeightRegular];
    sLbl.textColor = spec.secondaryTextColor;
    sLbl.numberOfLines = 2;
    [vStack addArrangedSubview:sLbl];

    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = isOn;
    sw.onTintColor = spec.accentColor;
    [sw addTarget:self action:@selector(handleSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [row addArrangedSubview:sw];

    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:container.topAnchor constant:12.0],
        [row.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-12.0],
        [row.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:14.0],
        [row.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-14.0]
    ]];

    if (separator) {
        UIView *sep = [[UIView alloc] init];
        sep.backgroundColor = spec.glassSpecularBorderColor;
        sep.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:sep];
        [NSLayoutConstraint activateConstraints:@[
            [sep.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:50.0],
            [sep.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [sep.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
            [sep.heightAnchor constraintEqualToConstant:0.6]
        ]];
    }

    [stack addArrangedSubview:container];
    return sw;
}

- (void)updateHeroStatus {
    self.heroStatusLabel.text = self.siteSettings.shieldsEnabled ? @"Shields are UP" : @"Shields are DOWN";
}

- (void)handleSwitchChanged:(UISwitch *__unused)sender {
    [[PDMThemeManager sharedManager] triggerSelectionHaptic];
    self.siteSettings.shieldsEnabled = self.masterSwitch.isOn;
    self.siteSettings.blockPopups = self.popupsSwitch.isOn;
    self.siteSettings.blockThirdPartyScripts = self.scriptsSwitch.isOn;
    self.siteSettings.autoUpgradeHTTPS = self.httpsSwitch.isOn;
    self.siteSettings.forceDarkMode = self.darkModeSwitch.isOn;
    self.siteSettings.useDesktopUserAgent = self.desktopSwitch.isOn;
    [[PDMPrivacyShieldEngine sharedEngine] saveSettings:self.siteSettings];
    [self updateHeroStatus];
    if (self.onSettingsChanged) {
        self.onSettingsChanged(self.siteSettings);
    }
}

- (void)handleClearSiteDataTap {
    [[PDMThemeManager sharedManager] triggerWarningHaptic];
    NSString *host = self.currentHost;
    dispatch_block_t cb = self.onClearSiteData;
    [[PDMPrivacyShieldEngine sharedEngine] clearDataForHost:host completion:^{
        if (cb) cb();
    }];
    [PDMToastBanner showInView:self.view message:[NSString stringWithFormat:@"Cleared data for %@", host] symbolName:@"checkmark.shield.fill"];
}

@end
