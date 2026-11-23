// Copyright © 2026 PrismDM. All Rights Reserved. Proprietary and Confidential.

#import "PDMBrowser.h"
#import "PDMTheme.h"
#import "PDMUI.h"
#import "PDMPrivacyShield.h"
#import "PDMMediaSniffer.h"
#import "PDMDownloadManager.h"
#import "PDMMediaPlayer.h"
#import "PDMLibrary.h"
#import "PDMTabGrid.h"
#import <WebKit/WebKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString *const kPDMBookmarksKey = @"pdm_bookmarks_v1";
static NSString *const kPDMHistoryKey = @"pdm_history_v1";
static NSString *const kPDMSpeedDialKey = @"pdm_speed_dial_v1";

#pragma mark - Distraction-Free Reader Mode Sheet

@interface PDMReaderViewController : PDMGlassSheetViewController
@property (nonatomic, copy) NSString *articleTitle;
@property (nonatomic, copy) NSString *articleHost;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *blocks;
@property (nonatomic, assign) CGFloat fontSize;
@property (nonatomic, assign) NSInteger paperTheme; // 0 = Glass Dark, 1 = Crisp Paper, 2 = Warm Sepia
@property (nonatomic, strong) UITextView *articleTextView;
@end

@implementation PDMReaderViewController

- (void)viewDidLoad {
    self.sheetTitle = @"Reader Mode";
    self.sheetSubtitle = self.articleHost ?: @"Distraction-Free Reading";
    self.sheetSymbolName = @"doc.plaintext.fill";
    self.allowsMediumDetent = NO;
    self.prefersLargeDefaultDetent = YES;
    [super viewDidLoad];

    self.fontSize = 17.5;
    self.paperTheme = 0;

    UIStackView *controls = [[UIStackView alloc] init];
    controls.axis = UILayoutConstraintAxisHorizontal;
    controls.spacing = 8.0;
    controls.distribution = UIStackViewDistributionFillEqually;

    PDMGlassPillButton *smaller = [[PDMGlassPillButton alloc] initWithTitle:@"A-" symbolName:nil];
    [smaller addTarget:self action:@selector(handleSmallerFont) forControlEvents:UIControlEventTouchUpInside];
    [controls addArrangedSubview:smaller];

    PDMGlassPillButton *larger = [[PDMGlassPillButton alloc] initWithTitle:@"A+" symbolName:nil];
    [larger addTarget:self action:@selector(handleLargerFont) forControlEvents:UIControlEventTouchUpInside];
    [controls addArrangedSubview:larger];

    PDMGlassPillButton *themeBtn = [[PDMGlassPillButton alloc] initWithTitle:@"Theme" symbolName:@"paintpalette.fill"];
    [themeBtn addTarget:self action:@selector(handleCyclePaper) forControlEvents:UIControlEventTouchUpInside];
    [controls addArrangedSubview:themeBtn];
    [self.contentStack addArrangedSubview:controls];

    self.articleTextView = [[UITextView alloc] init];
    self.articleTextView.editable = NO;
    self.articleTextView.scrollEnabled = NO;
    self.articleTextView.layer.cornerRadius = 18.0;
    self.articleTextView.textContainerInset = UIEdgeInsetsMake(18.0, 16.0, 22.0, 16.0);
    [self.contentStack addArrangedSubview:self.articleTextView];

    [self renderArticle];
}

- (void)handleSmallerFont {
    self.fontSize = MAX(13.0, self.fontSize - 1.5);
    [self renderArticle];
}

- (void)handleLargerFont {
    self.fontSize = MIN(26.0, self.fontSize + 1.5);
    [self renderArticle];
}

- (void)handleCyclePaper {
    self.paperTheme = (self.paperTheme + 1) % 3;
    [self renderArticle];
}

- (void)renderArticle {
    UIColor *bg = nil;
    UIColor *fg = nil;
    UIColor *sub = nil;
    if (self.paperTheme == 1) {
        bg = [UIColor colorWithWhite:0.98 alpha:1.0];
        fg = [UIColor colorWithWhite:0.10 alpha:1.0];
        sub = [UIColor colorWithWhite:0.38 alpha:1.0];
    } else if (self.paperTheme == 2) {
        bg = [UIColor colorWithRed:0.96 green:0.93 blue:0.86 alpha:1.0];
        fg = [UIColor colorWithRed:0.22 green:0.17 blue:0.12 alpha:1.0];
        sub = [UIColor colorWithRed:0.46 green:0.38 blue:0.28 alpha:1.0];
    } else {
        PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;
        bg = [spec.glassTintColor colorWithAlphaComponent:0.55];
        fg = spec.primaryTextColor;
        sub = spec.secondaryTextColor;
    }

    self.articleTextView.backgroundColor = bg;
    NSMutableAttributedString *doc = [[NSMutableAttributedString alloc] init];

    NSMutableParagraphStyle *titlePara = [[NSMutableParagraphStyle alloc] init];
    titlePara.paragraphSpacing = 12.0;
    [doc appendAttributedString:[[NSAttributedString alloc] initWithString:[(self.articleTitle ?: @"Article") stringByAppendingString:@"\n"]
                                                                attributes:@{
        NSFontAttributeName: [[PDMThemeManager sharedManager] displayFontOfSize:(self.fontSize + 6.0) weight:UIFontWeightBold],
        NSForegroundColorAttributeName: fg,
        NSParagraphStyleAttributeName: titlePara
    }]];

    NSMutableParagraphStyle *bodyPara = [[NSMutableParagraphStyle alloc] init];
    bodyPara.lineSpacing = 6.0;
    bodyPara.paragraphSpacing = 12.0;

    for (NSDictionary<NSString *, id> *b in self.blocks) {
        NSString *type = [b[@"type"] isKindOfClass:[NSString class]] ? b[@"type"] : @"p";
        NSString *txt = [b[@"text"] isKindOfClass:[NSString class]] ? b[@"text"] : nil;
        if (txt.length == 0) continue;
        BOOL isHeading = ([type isEqualToString:@"h1"] || [type isEqualToString:@"h2"] || [type isEqualToString:@"h3"]);
        UIFont *f = isHeading
            ? [[PDMThemeManager sharedManager] displayFontOfSize:(self.fontSize + 2.5) weight:UIFontWeightBold]
            : [[PDMThemeManager sharedManager] bodyFontOfSize:self.fontSize weight:UIFontWeightRegular];
        UIColor *c = [type isEqualToString:@"blockquote"] ? sub : fg;
        [doc appendAttributedString:[[NSAttributedString alloc] initWithString:[txt stringByAppendingString:@"\n"]
                                                                    attributes:@{
            NSFontAttributeName: f,
            NSForegroundColorAttributeName: c,
            NSParagraphStyleAttributeName: bodyPara
        }]];
    }
    self.articleTextView.attributedText = doc;
}

@end

#pragma mark - Settings Sheet

@interface PDMSettingsSheetViewController : PDMGlassSheetViewController
@property (nonatomic, copy, nullable) dispatch_block_t onClearAllDataRequested;
@property (nonatomic, strong) UIStackView *themeGridStack;
@property (nonatomic, strong) UIStackView *layoutStack;
@property (nonatomic, strong) UIStackView *engineStack;
@property (nonatomic, strong) UIStackView *partsStack;
@property (nonatomic, strong) UIStackView *concStack;
@property (nonatomic, strong) UIStackView *speedStack;
@end

@implementation PDMSettingsSheetViewController

- (void)viewDidLoad {
    self.sheetTitle = @"Settings";
    self.sheetSubtitle = @"Appearance, address bar & downloads";
    self.sheetSymbolName = @"gearshape";
    self.allowsMediumDetent = NO;
    self.prefersLargeDefaultDetent = YES;
    [super viewDidLoad];
    [self buildSettingsContent];
}

- (void)clearStack:(UIStackView *)stack {
    for (UIView *v in [stack.arrangedSubviews copy]) {
        [stack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
}

- (void)buildSettingsContent {
    PDMThemeManager *tm = [PDMThemeManager sharedManager];
    PDMThemeSpec *spec = tm.currentSpec;

    // 1. Clean Appearance (System / Light / Dark)
    [self.contentStack addArrangedSubview:[self sectionHeaderWithTitle:@"Appearance" detail:nil]];
    self.themeGridStack = [[UIStackView alloc] init];
    self.themeGridStack.axis = UILayoutConstraintAxisHorizontal;
    self.themeGridStack.spacing = 8.0;
    self.themeGridStack.distribution = UIStackViewDistributionFillEqually;
    [self.contentStack addArrangedSubview:self.themeGridStack];

    // 2. Address Bar Position (Top / Bottom, Chrome iOS style)
    [self.contentStack addArrangedSubview:[self sectionHeaderWithTitle:@"Address Bar" detail:nil]];
    self.layoutStack = [[UIStackView alloc] init];
    self.layoutStack.axis = UILayoutConstraintAxisHorizontal;
    self.layoutStack.spacing = 8.0;
    self.layoutStack.distribution = UIStackViewDistributionFillEqually;
    [self.contentStack addArrangedSubview:self.layoutStack];

    // 3. Search Engine
    [self.contentStack addArrangedSubview:[self sectionHeaderWithTitle:@"Search Engine" detail:nil]];
    self.engineStack = [[UIStackView alloc] init];
    self.engineStack.axis = UILayoutConstraintAxisVertical;
    self.engineStack.spacing = 8.0;
    [self.contentStack addArrangedSubview:self.engineStack];

    // 4. Download & Conversion Engine
    [self.contentStack addArrangedSubview:[self sectionHeaderWithTitle:@"Downloads & Conversion" detail:@"Parallel Segments"]];
    self.partsStack = [[UIStackView alloc] init];
    self.partsStack.axis = UILayoutConstraintAxisHorizontal;
    self.partsStack.spacing = 8.0;
    self.partsStack.distribution = UIStackViewDistributionFillEqually;
    [self.contentStack addArrangedSubview:self.partsStack];

    self.concStack = [[UIStackView alloc] init];
    self.concStack.axis = UILayoutConstraintAxisHorizontal;
    self.concStack.spacing = 8.0;
    self.concStack.distribution = UIStackViewDistributionFillEqually;
    [self.contentStack addArrangedSubview:self.concStack];

    self.speedStack = [[UIStackView alloc] init];
    self.speedStack.axis = UILayoutConstraintAxisHorizontal;
    self.speedStack.spacing = 6.0;
    self.speedStack.distribution = UIStackViewDistributionFillEqually;
    [self.contentStack addArrangedSubview:self.speedStack];

    // 5. Privacy & Behavior Toggles
    [self.contentStack addArrangedSubview:[self sectionHeaderWithTitle:@"Privacy & Behavior" detail:nil]];
    PDMGlassView *togglesCard = [[PDMGlassView alloc] initWithCornerRadius:14.0 elevated:NO];
    togglesCard.showAmbientShadow = NO;
    UIStackView *tStack = [[UIStackView alloc] init];
    tStack.axis = UILayoutConstraintAxisVertical;
    tStack.spacing = 12.0;
    tStack.translatesAutoresizingMaskIntoConstraints = NO;
    [togglesCard.contentView addSubview:tStack];
    [NSLayoutConstraint activateConstraints:@[
        [tStack.topAnchor constraintEqualToAnchor:togglesCard.contentView.topAnchor constant:12.0],
        [tStack.bottomAnchor constraintEqualToAnchor:togglesCard.contentView.bottomAnchor constant:-12.0],
        [tStack.leadingAnchor constraintEqualToAnchor:togglesCard.contentView.leadingAnchor constant:14.0],
        [tStack.trailingAnchor constraintEqualToAnchor:togglesCard.contentView.trailingAnchor constant:-14.0]
    ]];

    [self addToggleTo:tStack title:@"Biometric Vault Lock" subtitle:@"Require Face ID / Touch ID for Private Tabs & Vault" isOn:tm.biometricVaultLockEnabled tag:1];
    [self addToggleTo:tStack title:@"Force Dark Webpages" subtitle:@"Apply dark CSS styling to light websites" isOn:tm.globalForceDarkMode tag:2];
    [self addToggleTo:tStack title:@"Clear Data on Exit" subtitle:@"Remove history, cache & cookies when closing" isOn:tm.clearDataOnExit tag:3];
    [self addToggleTo:tStack title:@"Wi-Fi Only Downloads" subtitle:@"Pause automatic downloads on cellular" isOn:tm.wifiOnlyDownloads tag:4];
    [self addToggleTo:tStack title:@"Keep Original After Convert" subtitle:@"Keep raw file alongside converted video or audio" isOn:tm.keepOriginalAfterConvert tag:5];
    [self.contentStack addArrangedSubview:togglesCard];

    PDMGlassPillButton *clearAllBtn = [[PDMGlassPillButton alloc] initWithTitle:@"Clear Browsing Data" symbolName:@"trash"];
    clearAllBtn.customAccentColor = spec.dangerColor;
    clearAllBtn.glowing = YES;
    clearAllBtn.verticalPadding = 12.0;
    [clearAllBtn addTarget:self action:@selector(handleClearAllTap) forControlEvents:UIControlEventTouchUpInside];
    [self.contentStack addArrangedSubview:clearAllBtn];

    // 6. About & Legal (Strictly Proprietary / All Rights Reserved)
    [self.contentStack addArrangedSubview:[self sectionHeaderWithTitle:@"About" detail:@"v1.0.0"]];
    PDMGlassView *legalCard = [[PDMGlassView alloc] initWithCornerRadius:14.0 elevated:NO];
    legalCard.showAmbientShadow = NO;
    UIStackView *legStack = [[UIStackView alloc] init];
    legStack.axis = UILayoutConstraintAxisVertical;
    legStack.spacing = 6.0;
    legStack.translatesAutoresizingMaskIntoConstraints = NO;
    [legalCard.contentView addSubview:legStack];

    UILabel *appNameLbl = [[UILabel alloc] init];
    appNameLbl.text = @"PrismDM Browser · v1.0.0";
    appNameLbl.font = [tm displayFontOfSize:15.0 weight:UIFontWeightSemibold];
    appNameLbl.textColor = spec.primaryTextColor;
    [legStack addArrangedSubview:appNameLbl];

    UILabel *licBadge = [[UILabel alloc] init];
    licBadge.text = @"Proprietary Software · All Rights Reserved";
    licBadge.font = [tm bodyFontOfSize:12.5 weight:UIFontWeightMedium];
    licBadge.textColor = spec.accentColor;
    [legStack addArrangedSubview:licBadge];

    UILabel *copyrightLbl = [[UILabel alloc] init];
    copyrightLbl.text = @"Copyright © 2026 PrismDM. All Rights Reserved.\nThis software is strictly closed-source and proprietary. Unauthorized copying, redistribution, modification, derivative works, reverse engineering, or commercial use without prior written permission from the copyright owner is strictly prohibited.";
    copyrightLbl.font = [tm bodyFontOfSize:11.5 weight:UIFontWeightRegular];
    copyrightLbl.textColor = spec.secondaryTextColor;
    copyrightLbl.numberOfLines = 0;
    [legStack addArrangedSubview:copyrightLbl];

    [NSLayoutConstraint activateConstraints:@[
        [legStack.topAnchor constraintEqualToAnchor:legalCard.contentView.topAnchor constant:14.0],
        [legStack.bottomAnchor constraintEqualToAnchor:legalCard.contentView.bottomAnchor constant:-14.0],
        [legStack.leadingAnchor constraintEqualToAnchor:legalCard.contentView.leadingAnchor constant:14.0],
        [legStack.trailingAnchor constraintEqualToAnchor:legalCard.contentView.trailingAnchor constant:-14.0]
    ]];
    [self.contentStack addArrangedSubview:legalCard];

    [self rebuildDynamicSelectors];
}

- (void)addToggleTo:(UIStackView *)stack title:(NSString *)title subtitle:(NSString *)sub isOn:(BOOL)isOn tag:(NSInteger)tag {
    PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;
    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 10.0;

    UIStackView *txt = [[UIStackView alloc] init];
    txt.axis = UILayoutConstraintAxisVertical;
    txt.spacing = 2.0;

    UILabel *t = [[UILabel alloc] init];
    t.text = title;
    t.font = [[PDMThemeManager sharedManager] bodyFontOfSize:14.0 weight:UIFontWeightMedium];
    t.textColor = spec.primaryTextColor;
    [txt addArrangedSubview:t];

    UILabel *s = [[UILabel alloc] init];
    s.text = sub;
    s.font = [[PDMThemeManager sharedManager] bodyFontOfSize:11.5 weight:UIFontWeightRegular];
    s.textColor = spec.secondaryTextColor;
    s.numberOfLines = 2;
    [txt addArrangedSubview:s];
    [row addArrangedSubview:txt];

    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = isOn;
    sw.tag = tag;
    sw.onTintColor = spec.accentColor;
    [sw addTarget:self action:@selector(handleToggleSwitch:) forControlEvents:UIControlEventValueChanged];
    [row addArrangedSubview:sw];

    [stack addArrangedSubview:row];
}

- (void)rebuildDynamicSelectors {
    PDMThemeManager *tm = [PDMThemeManager sharedManager];

    // Appearance (System / Light / Dark)
    [self clearStack:self.themeGridStack];
    NSArray<PDMThemeSpec *> *allThemes = [tm allThemeSpecs];
    NSArray<NSString *> *themeIcons = @[@"circle.lefthalf.filled", @"sun.max", @"moon"];
    for (NSUInteger i = 0; i < allThemes.count; i++) {
        PDMThemeSpec *ts = allThemes[i];
        PDMGlassChip *c = [[PDMGlassChip alloc] initWithTitle:ts.displayName subtitle:nil];
        c.symbolName = (i < themeIcons.count) ? themeIcons[i] : @"circle.lefthalf.filled";
        c.tag = (NSInteger)ts.themeID;
        c.chipSelected = (tm.currentThemeID == ts.themeID);
        [c addTarget:self action:@selector(handleThemeTap:) forControlEvents:UIControlEventTouchUpInside];
        [self.themeGridStack addArrangedSubview:c];
    }

    // Address Bar Position (Top / Bottom)
    [self clearStack:self.layoutStack];
    for (NSInteger p = 0; p <= PDMLayoutChromeBottom; p++) {
        PDMLayoutPreset preset = (PDMLayoutPreset)p;
        PDMGlassChip *c = [[PDMGlassChip alloc] initWithTitle:[tm displayNameForLayoutPreset:preset] subtitle:nil];
        c.symbolName = (preset == PDMLayoutChromeTop) ? @"rectangle.topthird.inset.filled" : @"rectangle.bottomthird.inset.filled";
        c.tag = p;
        c.chipSelected = (tm.layoutPreset == preset);
        [c addTarget:self action:@selector(handleLayoutTap:) forControlEvents:UIControlEventTouchUpInside];
        [self.layoutStack addArrangedSubview:c];
    }

    // Search Engines 2x3
    [self clearStack:self.engineStack];
    for (NSInteger e = 0; e <= PDMSearchEngineCustom; e += 3) {
        UIStackView *row = [[UIStackView alloc] init];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.spacing = 8.0;
        row.distribution = UIStackViewDistributionFillEqually;
        for (NSInteger j = e; j < MIN(e + 3, (NSInteger)PDMSearchEngineCustom + 1); j++) {
            PDMSearchEngine eng = (PDMSearchEngine)j;
            PDMGlassChip *c = [[PDMGlassChip alloc] initWithTitle:[tm displayNameForSearchEngine:eng] subtitle:nil];
            c.symbolName = [tm symbolNameForSearchEngine:eng];
            c.tag = j;
            c.chipSelected = (tm.searchEngine == eng);
            [c addTarget:self action:@selector(handleEngineTap:) forControlEvents:UIControlEventTouchUpInside];
            [row addArrangedSubview:c];
        }
        [self.engineStack addArrangedSubview:row];
    }

    // Default Parts
    [self clearStack:self.partsStack];
    for (NSNumber *n in @[@2, @4, @8, @16]) {
        PDMGlassChip *c = [[PDMGlassChip alloc] initWithTitle:[NSString stringWithFormat:@"%ld Parts", (long)n.integerValue] subtitle:nil];
        c.tag = n.integerValue;
        c.chipSelected = (tm.defaultSegmentCount == n.integerValue);
        [c addTarget:self action:@selector(handlePartsTap:) forControlEvents:UIControlEventTouchUpInside];
        [self.partsStack addArrangedSubview:c];
    }

    // Max Concurrent
    [self clearStack:self.concStack];
    for (NSNumber *n in @[@1, @2, @3]) {
        PDMGlassChip *c = [[PDMGlassChip alloc] initWithTitle:[NSString stringWithFormat:@"%ld Concurrent", (long)n.integerValue] subtitle:nil];
        c.tag = n.integerValue;
        c.chipSelected = (tm.maxConcurrentDownloads == n.integerValue);
        [c addTarget:self action:@selector(handleConcTap:) forControlEvents:UIControlEventTouchUpInside];
        [self.concStack addArrangedSubview:c];
    }

    // Speed Cap
    [self clearStack:self.speedStack];
    for (NSNumber *n in @[@0, @1, @2, @5, @10]) {
        NSString *t = (n.integerValue == 0) ? @"Unlimited" : [NSString stringWithFormat:@"%ldM/s", (long)n.integerValue];
        PDMGlassChip *c = [[PDMGlassChip alloc] initWithTitle:t subtitle:nil];
        c.tag = n.integerValue;
        c.chipSelected = (tm.speedLimitMBps == n.integerValue);
        [c addTarget:self action:@selector(handleSpeedCapTap:) forControlEvents:UIControlEventTouchUpInside];
        [self.speedStack addArrangedSubview:c];
    }
}

- (void)handleThemeTap:(PDMGlassChip *)sender {
    [PDMThemeManager sharedManager].currentThemeID = (PDMThemeID)sender.tag;
    [self applyTheme];
    [self rebuildDynamicSelectors];
}

- (void)handleLayoutTap:(PDMGlassChip *)sender {
    [PDMThemeManager sharedManager].layoutPreset = (PDMLayoutPreset)sender.tag;
    [self rebuildDynamicSelectors];
}

- (void)handleEngineTap:(PDMGlassChip *)sender {
    PDMSearchEngine eng = (PDMSearchEngine)sender.tag;
    [PDMThemeManager sharedManager].searchEngine = eng;
    [self rebuildDynamicSelectors];
    if (eng == PDMSearchEngineCustom) {
        [PDMGlassActionSheetController presentTextInputFrom:self
                                                      title:@"Custom Search URL"
                                                   subtitle:@"Use %@ where your search query should be inserted"
                                                placeholder:@"https://search.example.com/?q=%@"
                                                initialText:[PDMThemeManager sharedManager].customSearchURLTemplate
                                               confirmTitle:@"Save Engine"
                                                  onConfirm:^(NSString *value) {
            if (value.length > 0) {
                [PDMThemeManager sharedManager].customSearchURLTemplate = value;
            }
        }];
    }
}

- (void)handlePartsTap:(PDMGlassChip *)sender {
    [PDMThemeManager sharedManager].defaultSegmentCount = sender.tag;
    [self rebuildDynamicSelectors];
}

- (void)handleConcTap:(PDMGlassChip *)sender {
    [PDMThemeManager sharedManager].maxConcurrentDownloads = sender.tag;
    [self rebuildDynamicSelectors];
}

- (void)handleSpeedCapTap:(PDMGlassChip *)sender {
    [PDMThemeManager sharedManager].speedLimitMBps = sender.tag;
    [self rebuildDynamicSelectors];
}

- (void)handleToggleSwitch:(UISwitch *)sw {
    PDMThemeManager *tm = [PDMThemeManager sharedManager];
    [tm triggerSelectionHaptic];
    switch (sw.tag) {
        case 1: tm.biometricVaultLockEnabled = sw.isOn; break;
        case 2: tm.globalForceDarkMode = sw.isOn; break;
        case 3: tm.clearDataOnExit = sw.isOn; break;
        case 4: tm.wifiOnlyDownloads = sw.isOn; break;
        case 5: tm.keepOriginalAfterConvert = sw.isOn; break;
        default: break;
    }
}

- (void)handleClearAllTap {
    [[PDMThemeManager sharedManager] triggerWarningHaptic];
    if (self.onClearAllDataRequested) {
        self.onClearAllDataRequested();
    }
    [PDMToastBanner showInView:self.view message:@"All browsing history, cache & cookies cleared." symbolName:@"checkmark.shield.fill"];
}

@end

#pragma mark - Chrome-Style Rounded-Square Tab Counter Button

@interface PDMChromeTabCounterButton : UIControl
@property (nonatomic, assign) NSInteger tabCount;
@property (nonatomic, assign) BOOL privateMode;
- (void)applyTheme;
@end

@interface PDMChromeTabCounterButton ()
@property (nonatomic, strong) UIView *boxView;
@property (nonatomic, strong) UILabel *countLabel;
@end

@implementation PDMChromeTabCounterButton

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _tabCount = 1;
        _boxView = [[UIView alloc] init];
        _boxView.translatesAutoresizingMaskIntoConstraints = NO;
        _boxView.userInteractionEnabled = NO;
        _boxView.layer.cornerRadius = 5.5;
        _boxView.layer.cornerCurve = kCACornerCurveContinuous;
        _boxView.layer.borderWidth = 1.75;
        [self addSubview:_boxView];

        _countLabel = [[UILabel alloc] init];
        _countLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _countLabel.textAlignment = NSTextAlignmentCenter;
        _countLabel.font = [[PDMThemeManager sharedManager] tabularFontOfSize:11.5 weight:UIFontWeightBold];
        _countLabel.text = @"1";
        [_boxView addSubview:_countLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_boxView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_boxView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_boxView.widthAnchor constraintEqualToConstant:22.0],
            [_boxView.heightAnchor constraintEqualToConstant:22.0],
            [_countLabel.centerXAnchor constraintEqualToAnchor:_boxView.centerXAnchor],
            [_countLabel.centerYAnchor constraintEqualToAnchor:_boxView.centerYAnchor],
            [self.widthAnchor constraintGreaterThanOrEqualToConstant:40.0],
            [self.heightAnchor constraintGreaterThanOrEqualToConstant:38.0]
        ]];
        [self applyTheme];
    }
    return self;
}

- (void)setTabCount:(NSInteger)tabCount {
    _tabCount = MAX(1, tabCount);
    self.countLabel.text = (_tabCount > 99) ? @":D" : [NSString stringWithFormat:@"%ld", (long)_tabCount];
}

- (void)setPrivateMode:(BOOL)privateMode {
    _privateMode = privateMode;
    [self applyTheme];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:0.12 animations:^{
        self.alpha = highlighted ? 0.55 : 1.0;
        self.transform = highlighted ? CGAffineTransformMakeScale(0.92, 0.92) : CGAffineTransformIdentity;
    }];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self applyTheme];
}

- (void)applyTheme {
    PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;
    UIColor *ink = self.privateMode ? spec.accentColor : spec.primaryTextColor;
    self.boxView.layer.borderColor = [ink resolvedColorWithTraitCollection:self.traitCollection].CGColor;
    self.countLabel.textColor = ink;
}

@end

#pragma mark - PDMRootBrowserViewController

@interface PDMRootBrowserViewController () <WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, UITextFieldDelegate, UIScrollViewDelegate, UIDocumentPickerDelegate>
@property (nonatomic, strong) NSMutableArray<PDMTabItem *> *standardTabs;
@property (nonatomic, strong) NSMutableArray<PDMTabItem *> *privateTabs;
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *closedTabsHistory;
@property (nonatomic, strong, nullable) PDMTabItem *activeTab;

@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *bookmarks;
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *historyEntries;
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *speedDials;

// Main containers
@property (nonatomic, strong) UIView *webContainerView;
@property (nonatomic, strong) UIProgressView *loadProgressView;
@property (nonatomic, strong) NSLayoutConstraint *webTopToTopBar;
@property (nonatomic, strong) NSLayoutConstraint *webTopToSafeArea;

// Minimalist Chrome New Tab Page
@property (nonatomic, strong) UIScrollView *startPageScroll;
@property (nonatomic, strong) UIStackView *startPageStack;
@property (nonatomic, strong) UIView *heroSearchPill;
@property (nonatomic, strong) UIImageView *heroSearchIcon;
@property (nonatomic, strong) UITextField *startSearchField;
@property (nonatomic, strong) PDMGlassPillButton *startEnginePill;
@property (nonatomic, strong) PDMGlassView *clipboardPasteCard;
@property (nonatomic, strong) UILabel *clipboardURLLabel;
@property (nonatomic, copy, nullable) NSString *detectedClipboardURL;
@property (nonatomic, strong) UIStackView *speedDialGridStack;
@property (nonatomic, strong) PDMGlassView *activeDownloadsMiniCard;
@property (nonatomic, strong) UILabel *miniCardTitleLabel;
@property (nonatomic, strong) UILabel *miniCardSubtitleLabel;
@property (nonatomic, strong) PDMGlassPillButton *shieldSummaryPill;

// Chrome Top & Bottom Toolbars
@property (nonatomic, strong) UIView *topChromeBar;
@property (nonatomic, strong) UIView *topHairline;
@property (nonatomic, strong) UIView *bottomChromeBar;
@property (nonatomic, strong) UIView *bottomHairline;
@property (nonatomic, strong) UIStackView *topChromeHostStack;
@property (nonatomic, strong) UIStackView *bottomChromeOuterStack;
@property (nonatomic, strong) UIStackView *bottomNavRow;
@property (nonatomic, strong) UIView *omnibarPill;

@property (nonatomic, strong) PDMGlassPillButton *shieldBtn;
@property (nonatomic, strong) UITextField *omnibarField;
@property (nonatomic, strong) PDMGlassPillButton *mediaGrabBtn;
@property (nonatomic, strong) PDMChromeTabCounterButton *tabsBtn;
@property (nonatomic, strong) PDMGlassPillButton *downloadsBtn;
@property (nonatomic, strong) PDMGlassPillButton *menuBtn;
@property (nonatomic, strong) PDMGlassPillButton *backBtn;
@property (nonatomic, strong) PDMGlassPillButton *forwardBtn;
@property (nonatomic, strong) PDMGlassPillButton *reloadBtn;

// Find in Page Bar
@property (nonatomic, strong) PDMGlassView *findBar;
@property (nonatomic, strong) UITextField *findField;
@property (nonatomic, strong) UILabel *findCountLabel;

@property (nonatomic, strong, nullable) PDMTabItem *observedWebViewTab;
@end

@implementation PDMRootBrowserViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.standardTabs = [NSMutableArray array];
    self.privateTabs = [NSMutableArray array];
    self.closedTabsHistory = [NSMutableArray array];

    [self loadPersistedBrowserData];
    [self buildRootLayout];
    [self rebuildChromeForCurrentLayoutPreset];
    [self applyTheme];

    // Prepare WKContentRuleList asynchronously and create first tab
    __weak typeof(self) weakSelf = self;
    [[PDMPrivacyShieldEngine sharedEngine] prepareContentRuleListsWithCompletion:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (strongSelf.activeTab.webView) {
            [[PDMPrivacyShieldEngine sharedEngine] applyRulesToUserContentController:strongSelf.activeTab.webView.configuration.userContentController
                                                                             forHost:strongSelf.activeTab.webView.URL.host];
        }
    }];

    [self createAndActivateTabIsPrivate:NO initialURL:nil];
    [self refreshPrivacyStatsUI];
    [self refreshDownloadsIndicators];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyTheme) name:PDMThemeDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleLayoutPresetChanged) name:PDMLayoutDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshPrivacyStatsUI) name:PDMPrivacyStatsDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshDownloadsIndicators) name:PDMDownloadsDidUpdateNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshSearchEnginePill) name:PDMSettingsDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(checkClipboardForURL) name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self checkClipboardForURL];
}

- (void)dealloc {
    [self detachObserversFromCurrentTab];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Persistence (Bookmarks, History, Speed Dial)

- (void)loadPersistedBrowserData {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *bm = [defaults arrayForKey:kPDMBookmarksKey];
    self.bookmarks = bm ? [bm mutableCopy] : [NSMutableArray arrayWithArray:@[
        @{@"title": @"Apple", @"url": @"https://www.apple.com", @"folder": @"Favorites"},
        @{@"title": @"GitHub", @"url": @"https://github.com", @"folder": @"Developer"},
        @{@"title": @"Wikipedia", @"url": @"https://en.wikipedia.org", @"folder": @"Reading"}
    ]];

    NSArray *hist = [defaults arrayForKey:kPDMHistoryKey];
    self.historyEntries = hist ? [hist mutableCopy] : [NSMutableArray array];

    NSArray *sd = [defaults arrayForKey:kPDMSpeedDialKey];
    self.speedDials = sd ? [sd mutableCopy] : [NSMutableArray arrayWithArray:@[
        @{@"title": @"YouTube", @"url": @"https://m.youtube.com", @"symbol": @"play.rectangle"},
        @{@"title": @"GitHub", @"url": @"https://github.com", @"symbol": @"chevron.left.forwardslash.chevron.right"},
        @{@"title": @"Reddit", @"url": @"https://www.reddit.com", @"symbol": @"bubble.left.and.bubble.right"},
        @{@"title": @"Wikipedia", @"url": @"https://en.wikipedia.org", @"symbol": @"book"},
        @{@"title": @"Archive", @"url": @"https://archive.org", @"symbol": @"archivebox"},
        @{@"title": @"Vimeo", @"url": @"https://vimeo.com", @"symbol": @"film"},
        @{@"title": @"SoundCloud", @"url": @"https://soundcloud.com", @"symbol": @"waveform"}
    ]];
}

- (void)saveBookmarks {
    [[NSUserDefaults standardUserDefaults] setObject:self.bookmarks forKey:kPDMBookmarksKey];
}

- (void)saveHistory {
    if (self.historyEntries.count > 250) {
        [self.historyEntries removeObjectsInRange:NSMakeRange(250, self.historyEntries.count - 250)];
    }
    [[NSUserDefaults standardUserDefaults] setObject:self.historyEntries forKey:kPDMHistoryKey];
}

- (void)saveSpeedDials {
    [[NSUserDefaults standardUserDefaults] setObject:self.speedDials forKey:kPDMSpeedDialKey];
}

- (void)recordHistoryTitle:(NSString *)title urlString:(NSString *)urlString {
    if (self.activeTab.isPrivate || urlString.length == 0) return;
    [self.historyEntries insertObject:@{
        @"title": (title.length > 0 ? title : urlString),
        @"url": urlString,
        @"date": @([[NSDate date] timeIntervalSince1970])
    } atIndex:0];
    [self saveHistory];
}

#pragma mark - Root UI Construction (Chrome iOS Minimalist Architecture)

- (void)buildRootLayout {
    // 1. WebView container
    self.webContainerView = [[UIView alloc] init];
    self.webContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.webContainerView];

    // 2. Minimalist Chrome New Tab Page
    [self buildStartPageUI];

    // 3. Flush Top Chrome Bar (contains Omnibox Pill when in Top Bar mode)
    self.topChromeBar = [[UIView alloc] init];
    self.topChromeBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.topChromeBar];

    self.topChromeHostStack = [[UIStackView alloc] init];
    self.topChromeHostStack.axis = UILayoutConstraintAxisVertical;
    self.topChromeHostStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.topChromeBar addSubview:self.topChromeHostStack];

    self.topHairline = [[UIView alloc] init];
    self.topHairline.translatesAutoresizingMaskIntoConstraints = NO;
    [self.topChromeBar addSubview:self.topHairline];

    // 4. Thin Chrome Loading Progress Bar
    self.loadProgressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
    self.loadProgressView.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadProgressView.hidden = YES;
    [self.view addSubview:self.loadProgressView];

    // 5. Flush Bottom Chrome Toolbar (5 borderless icons + optional bottom omnibox)
    self.bottomChromeBar = [[UIView alloc] init];
    self.bottomChromeBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.bottomChromeBar];

    self.bottomHairline = [[UIView alloc] init];
    self.bottomHairline.translatesAutoresizingMaskIntoConstraints = NO;
    [self.bottomChromeBar addSubview:self.bottomHairline];

    self.bottomChromeOuterStack = [[UIStackView alloc] init];
    self.bottomChromeOuterStack.axis = UILayoutConstraintAxisVertical;
    self.bottomChromeOuterStack.spacing = 4.0;
    self.bottomChromeOuterStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.bottomChromeBar addSubview:self.bottomChromeOuterStack];

    // 6. Signature Chrome Omnibox Pill (#F1F3F4 light / #303134 dark, 40pt pill)
    self.omnibarPill = [[UIView alloc] init];
    self.omnibarPill.translatesAutoresizingMaskIntoConstraints = NO;
    self.omnibarPill.layer.cornerRadius = 20.0;
    self.omnibarPill.layer.cornerCurve = kCACornerCurveContinuous;

    UIStackView *pillRow = [[UIStackView alloc] init];
    pillRow.axis = UILayoutConstraintAxisHorizontal;
    pillRow.alignment = UIStackViewAlignmentCenter;
    pillRow.spacing = 4.0;
    pillRow.translatesAutoresizingMaskIntoConstraints = NO;
    [self.omnibarPill addSubview:pillRow];

    self.shieldBtn = [[PDMGlassPillButton alloc] initWithTitle:nil symbolName:@"lock.fill"];
    self.shieldBtn.borderless = YES;
    self.shieldBtn.symbolPointSize = 13.5;
    self.shieldBtn.horizontalPadding = 8.0;
    self.shieldBtn.verticalPadding = 6.0;
    [self.shieldBtn setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.shieldBtn addTarget:self action:@selector(handleShieldTap) forControlEvents:UIControlEventTouchUpInside];

    self.omnibarField = [[UITextField alloc] init];
    self.omnibarField.placeholder = @"Search or type URL";
    self.omnibarField.font = [[PDMThemeManager sharedManager] bodyFontOfSize:15.0 weight:UIFontWeightRegular];
    self.omnibarField.returnKeyType = UIReturnKeyGo;
    self.omnibarField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.omnibarField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.omnibarField.keyboardType = UIKeyboardTypeWebSearch;
    self.omnibarField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.omnibarField.delegate = self;
    [self.omnibarField setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    self.mediaGrabBtn = [[PDMGlassPillButton alloc] initWithTitle:@"Save" symbolName:@"arrow.down.circle.fill"];
    self.mediaGrabBtn.glowing = YES;
    self.mediaGrabBtn.symbolPointSize = 12.5;
    self.mediaGrabBtn.horizontalPadding = 8.0;
    self.mediaGrabBtn.verticalPadding = 5.0;
    self.mediaGrabBtn.hidden = YES;
    [self.mediaGrabBtn setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.mediaGrabBtn addTarget:self action:@selector(handleMediaGrabTap) forControlEvents:UIControlEventTouchUpInside];

    self.reloadBtn = [[PDMGlassPillButton alloc] initWithTitle:nil symbolName:@"arrow.clockwise"];
    self.reloadBtn.borderless = YES;
    self.reloadBtn.symbolPointSize = 14.5;
    self.reloadBtn.horizontalPadding = 8.0;
    self.reloadBtn.verticalPadding = 6.0;
    [self.reloadBtn setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.reloadBtn addTarget:self action:@selector(handleReloadTap) forControlEvents:UIControlEventTouchUpInside];

    [pillRow addArrangedSubview:self.shieldBtn];
    [pillRow addArrangedSubview:self.omnibarField];
    [pillRow addArrangedSubview:self.mediaGrabBtn];
    [pillRow addArrangedSubview:self.reloadBtn];

    [NSLayoutConstraint activateConstraints:@[
        [self.omnibarPill.heightAnchor constraintEqualToConstant:40.0],
        [pillRow.topAnchor constraintEqualToAnchor:self.omnibarPill.topAnchor constant:2.0],
        [pillRow.bottomAnchor constraintEqualToAnchor:self.omnibarPill.bottomAnchor constant:-2.0],
        [pillRow.leadingAnchor constraintEqualToAnchor:self.omnibarPill.leadingAnchor constant:6.0],
        [pillRow.trailingAnchor constraintEqualToAnchor:self.omnibarPill.trailingAnchor constant:-6.0]
    ]];

    // 7. Borderless 5-Icon Chrome Bottom Navigation Strip
    self.backBtn = [[PDMGlassPillButton alloc] initWithTitle:nil symbolName:@"chevron.left"];
    self.backBtn.borderless = YES;
    self.backBtn.symbolPointSize = 18.5;
    self.backBtn.horizontalPadding = 10.0;
    self.backBtn.verticalPadding = 8.0;
    [self.backBtn addTarget:self action:@selector(handleBackTap) forControlEvents:UIControlEventTouchUpInside];

    self.forwardBtn = [[PDMGlassPillButton alloc] initWithTitle:nil symbolName:@"chevron.right"];
    self.forwardBtn.borderless = YES;
    self.forwardBtn.symbolPointSize = 18.5;
    self.forwardBtn.horizontalPadding = 10.0;
    self.forwardBtn.verticalPadding = 8.0;
    [self.forwardBtn addTarget:self action:@selector(handleForwardTap) forControlEvents:UIControlEventTouchUpInside];

    self.downloadsBtn = [[PDMGlassPillButton alloc] initWithTitle:nil symbolName:@"arrow.down.circle"];
    self.downloadsBtn.borderless = YES;
    self.downloadsBtn.symbolPointSize = 19.0;
    self.downloadsBtn.horizontalPadding = 10.0;
    self.downloadsBtn.verticalPadding = 8.0;
    [self.downloadsBtn addTarget:self action:@selector(handleDownloadsTap) forControlEvents:UIControlEventTouchUpInside];

    self.tabsBtn = [[PDMChromeTabCounterButton alloc] init];
    [self.tabsBtn addTarget:self action:@selector(handleTabsTap) forControlEvents:UIControlEventTouchUpInside];

    self.menuBtn = [[PDMGlassPillButton alloc] initWithTitle:nil symbolName:@"ellipsis"];
    self.menuBtn.borderless = YES;
    self.menuBtn.symbolPointSize = 18.5;
    self.menuBtn.horizontalPadding = 10.0;
    self.menuBtn.verticalPadding = 8.0;
    [self.menuBtn addTarget:self action:@selector(handleMenuTap) forControlEvents:UIControlEventTouchUpInside];

    self.bottomNavRow = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.backBtn,
        self.forwardBtn,
        self.downloadsBtn,
        self.tabsBtn,
        self.menuBtn
    ]];
    self.bottomNavRow.axis = UILayoutConstraintAxisHorizontal;
    self.bottomNavRow.alignment = UIStackViewAlignmentCenter;
    self.bottomNavRow.distribution = UIStackViewDistributionEqualCentering;
    [self.bottomNavRow.heightAnchor constraintEqualToConstant:44.0].active = YES;

    // 8. Find in Page Bar
    [self buildFindInPageBar];

    self.webTopToTopBar = [self.webContainerView.topAnchor constraintEqualToAnchor:self.topChromeBar.bottomAnchor];
    self.webTopToSafeArea = [self.webContainerView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor];

    [NSLayoutConstraint activateConstraints:@[
        [self.topChromeBar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.topChromeBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.topChromeBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [self.topChromeHostStack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:6.0],
        [self.topChromeHostStack.bottomAnchor constraintEqualToAnchor:self.topChromeBar.bottomAnchor constant:-8.0],
        [self.topChromeHostStack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:14.0],
        [self.topChromeHostStack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-14.0],

        [self.topHairline.leadingAnchor constraintEqualToAnchor:self.topChromeBar.leadingAnchor],
        [self.topHairline.trailingAnchor constraintEqualToAnchor:self.topChromeBar.trailingAnchor],
        [self.topHairline.bottomAnchor constraintEqualToAnchor:self.topChromeBar.bottomAnchor],
        [self.topHairline.heightAnchor constraintEqualToConstant:0.5],

        [self.loadProgressView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.loadProgressView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.loadProgressView.topAnchor constraintEqualToAnchor:self.topChromeBar.bottomAnchor],
        [self.loadProgressView.heightAnchor constraintEqualToConstant:2.0],

        [self.bottomChromeBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.bottomChromeBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.bottomChromeBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.bottomHairline.topAnchor constraintEqualToAnchor:self.bottomChromeBar.topAnchor],
        [self.bottomHairline.leadingAnchor constraintEqualToAnchor:self.bottomChromeBar.leadingAnchor],
        [self.bottomHairline.trailingAnchor constraintEqualToAnchor:self.bottomChromeBar.trailingAnchor],
        [self.bottomHairline.heightAnchor constraintEqualToConstant:0.5],

        [self.bottomChromeOuterStack.topAnchor constraintEqualToAnchor:self.bottomChromeBar.topAnchor constant:6.0],
        [self.bottomChromeOuterStack.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-4.0],
        [self.bottomChromeOuterStack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16.0],
        [self.bottomChromeOuterStack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16.0],

        self.webTopToTopBar,
        [self.webContainerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.webContainerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.webContainerView.bottomAnchor constraintEqualToAnchor:self.bottomChromeBar.topAnchor],

        [self.startPageScroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.startPageScroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.startPageScroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.startPageScroll.bottomAnchor constraintEqualToAnchor:self.bottomChromeBar.topAnchor]
    ]];
}

- (void)buildStartPageUI {
    PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;

    self.startPageScroll = [[UIScrollView alloc] init];
    self.startPageScroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.startPageScroll.alwaysBounceVertical = YES;
    self.startPageScroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.startPageScroll];

    self.startPageStack = [[UIStackView alloc] init];
    self.startPageStack.axis = UILayoutConstraintAxisVertical;
    self.startPageStack.spacing = 22.0;
    self.startPageStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.startPageScroll addSubview:self.startPageStack];

    // Minimalist Wordmark (clean Chrome-like presence, zero clutter)
    UILabel *brandTitle = [[UILabel alloc] init];
    brandTitle.text = @"PrismDM";
    brandTitle.tag = 8001;
    brandTitle.textAlignment = NSTextAlignmentCenter;
    brandTitle.font = [[PDMThemeManager sharedManager] displayFontOfSize:34.0 weight:UIFontWeightSemibold];
    [self.startPageStack addArrangedSubview:brandTitle];

    // Iconic Chrome Large Pill Search Bar
    self.heroSearchPill = [[UIView alloc] init];
    self.heroSearchPill.translatesAutoresizingMaskIntoConstraints = NO;
    self.heroSearchPill.layer.cornerRadius = 26.0;
    self.heroSearchPill.layer.cornerCurve = kCACornerCurveContinuous;

    UIStackView *searchRow = [[UIStackView alloc] init];
    searchRow.axis = UILayoutConstraintAxisHorizontal;
    searchRow.alignment = UIStackViewAlignmentCenter;
    searchRow.spacing = 10.0;
    searchRow.translatesAutoresizingMaskIntoConstraints = NO;
    [self.heroSearchPill addSubview:searchRow];

    UIImageSymbolConfiguration *mgCfg = [UIImageSymbolConfiguration configurationWithPointSize:17.0 weight:UIImageSymbolWeightMedium];
    self.heroSearchIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass" withConfiguration:mgCfg]];
    self.heroSearchIcon.contentMode = UIViewContentModeScaleAspectFit;
    [self.heroSearchIcon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [searchRow addArrangedSubview:self.heroSearchIcon];

    self.startSearchField = [[UITextField alloc] init];
    self.startSearchField.placeholder = @"Search or type URL";
    self.startSearchField.font = [[PDMThemeManager sharedManager] bodyFontOfSize:16.0 weight:UIFontWeightRegular];
    self.startSearchField.returnKeyType = UIReturnKeyGo;
    self.startSearchField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.startSearchField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.startSearchField.keyboardType = UIKeyboardTypeWebSearch;
    self.startSearchField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.startSearchField.delegate = self;
    [searchRow addArrangedSubview:self.startSearchField];

    self.startEnginePill = [[PDMGlassPillButton alloc] initWithTitle:@"Google" symbolName:nil];
    self.startEnginePill.borderless = YES;
    self.startEnginePill.horizontalPadding = 6.0;
    self.startEnginePill.verticalPadding = 4.0;
    [self.startEnginePill setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.startEnginePill addTarget:self action:@selector(handleQuickSearchEngineSwitch) forControlEvents:UIControlEventTouchUpInside];
    [searchRow addArrangedSubview:self.startEnginePill];

    [NSLayoutConstraint activateConstraints:@[
        [self.heroSearchPill.heightAnchor constraintEqualToConstant:52.0],
        [searchRow.topAnchor constraintEqualToAnchor:self.heroSearchPill.topAnchor constant:6.0],
        [searchRow.bottomAnchor constraintEqualToAnchor:self.heroSearchPill.bottomAnchor constant:-6.0],
        [searchRow.leadingAnchor constraintEqualToAnchor:self.heroSearchPill.leadingAnchor constant:18.0],
        [searchRow.trailingAnchor constraintEqualToAnchor:self.heroSearchPill.trailingAnchor constant:-12.0]
    ]];
    [self.startPageStack addArrangedSubview:self.heroSearchPill];

    // Clipboard URL Quick-Paste Pill (hidden unless URL copied)
    self.clipboardPasteCard = [[PDMGlassView alloc] initWithCornerRadius:14.0 elevated:NO];
    self.clipboardPasteCard.hidden = YES;
    self.clipboardPasteCard.showAmbientShadow = NO;
    UIControl *clipTap = [[UIControl alloc] init];
    clipTap.translatesAutoresizingMaskIntoConstraints = NO;
    [clipTap addTarget:self action:@selector(handleClipboardQuickPasteTap) forControlEvents:UIControlEventTouchUpInside];
    [self.clipboardPasteCard.contentView addSubview:clipTap];

    UIStackView *clipRow = [[UIStackView alloc] init];
    clipRow.axis = UILayoutConstraintAxisHorizontal;
    clipRow.alignment = UIStackViewAlignmentCenter;
    clipRow.spacing = 10.0;
    clipRow.userInteractionEnabled = NO;
    clipRow.translatesAutoresizingMaskIntoConstraints = NO;
    [clipTap addSubview:clipRow];

    UIImageSymbolConfiguration *clipCfg = [UIImageSymbolConfiguration configurationWithPointSize:15.0 weight:UIImageSymbolWeightMedium];
    UIImageView *clipIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"link" withConfiguration:clipCfg]];
    clipIcon.tintColor = spec.accentColor;
    [clipIcon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [clipRow addArrangedSubview:clipIcon];

    self.clipboardURLLabel = [[UILabel alloc] init];
    self.clipboardURLLabel.font = [[PDMThemeManager sharedManager] bodyFontOfSize:13.0 weight:UIFontWeightRegular];
    self.clipboardURLLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [clipRow addArrangedSubview:self.clipboardURLLabel];

    [NSLayoutConstraint activateConstraints:@[
        [clipTap.topAnchor constraintEqualToAnchor:self.clipboardPasteCard.contentView.topAnchor],
        [clipTap.bottomAnchor constraintEqualToAnchor:self.clipboardPasteCard.contentView.bottomAnchor],
        [clipTap.leadingAnchor constraintEqualToAnchor:self.clipboardPasteCard.contentView.leadingAnchor],
        [clipTap.trailingAnchor constraintEqualToAnchor:self.clipboardPasteCard.contentView.trailingAnchor],
        [clipRow.topAnchor constraintEqualToAnchor:clipTap.topAnchor constant:10.0],
        [clipRow.bottomAnchor constraintEqualToAnchor:clipTap.bottomAnchor constant:-10.0],
        [clipRow.leadingAnchor constraintEqualToAnchor:clipTap.leadingAnchor constant:14.0],
        [clipRow.trailingAnchor constraintEqualToAnchor:clipTap.trailingAnchor constant:-14.0]
    ]];
    [self.startPageStack addArrangedSubview:self.clipboardPasteCard];

    // Active Downloads Compact Card (only visible while downloading)
    self.activeDownloadsMiniCard = [[PDMGlassView alloc] initWithCornerRadius:14.0 elevated:NO];
    self.activeDownloadsMiniCard.hidden = YES;
    self.activeDownloadsMiniCard.showAmbientShadow = NO;
    UIControl *miniTap = [[UIControl alloc] init];
    miniTap.translatesAutoresizingMaskIntoConstraints = NO;
    [miniTap addTarget:self action:@selector(handleDownloadsTap) forControlEvents:UIControlEventTouchUpInside];
    [self.activeDownloadsMiniCard.contentView addSubview:miniTap];

    UIStackView *miniRow = [[UIStackView alloc] init];
    miniRow.axis = UILayoutConstraintAxisHorizontal;
    miniRow.alignment = UIStackViewAlignmentCenter;
    miniRow.spacing = 12.0;
    miniRow.userInteractionEnabled = NO;
    miniRow.translatesAutoresizingMaskIntoConstraints = NO;
    [miniTap addSubview:miniRow];

    UIImageSymbolConfiguration *dlCfg = [UIImageSymbolConfiguration configurationWithPointSize:20.0 weight:UIImageSymbolWeightMedium];
    UIImageView *dlIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.down.circle.fill" withConfiguration:dlCfg]];
    dlIcon.tintColor = spec.accentColor;
    [dlIcon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [miniRow addArrangedSubview:dlIcon];

    UIStackView *miniText = [[UIStackView alloc] init];
    miniText.axis = UILayoutConstraintAxisVertical;
    miniText.spacing = 2.0;
    self.miniCardTitleLabel = [[UILabel alloc] init];
    self.miniCardTitleLabel.font = [[PDMThemeManager sharedManager] bodyFontOfSize:13.5 weight:UIFontWeightSemibold];
    self.miniCardTitleLabel.textColor = spec.primaryTextColor;
    [miniText addArrangedSubview:self.miniCardTitleLabel];
    self.miniCardSubtitleLabel = [[UILabel alloc] init];
    self.miniCardSubtitleLabel.font = [[PDMThemeManager sharedManager] tabularFontOfSize:12.0 weight:UIFontWeightRegular];
    self.miniCardSubtitleLabel.textColor = spec.secondaryTextColor;
    [miniText addArrangedSubview:self.miniCardSubtitleLabel];
    [miniRow addArrangedSubview:miniText];

    [NSLayoutConstraint activateConstraints:@[
        [miniTap.topAnchor constraintEqualToAnchor:self.activeDownloadsMiniCard.contentView.topAnchor],
        [miniTap.bottomAnchor constraintEqualToAnchor:self.activeDownloadsMiniCard.contentView.bottomAnchor],
        [miniTap.leadingAnchor constraintEqualToAnchor:self.activeDownloadsMiniCard.contentView.leadingAnchor],
        [miniTap.trailingAnchor constraintEqualToAnchor:self.activeDownloadsMiniCard.contentView.trailingAnchor],
        [miniRow.topAnchor constraintEqualToAnchor:miniTap.topAnchor constant:11.0],
        [miniRow.bottomAnchor constraintEqualToAnchor:miniTap.bottomAnchor constant:-11.0],
        [miniRow.leadingAnchor constraintEqualToAnchor:miniTap.leadingAnchor constant:14.0],
        [miniRow.trailingAnchor constraintEqualToAnchor:miniTap.trailingAnchor constant:-14.0]
    ]];
    [self.startPageStack addArrangedSubview:self.activeDownloadsMiniCard];

    // Chrome-Style 4-Column Circular Shortcuts Grid
    self.speedDialGridStack = [[UIStackView alloc] init];
    self.speedDialGridStack.axis = UILayoutConstraintAxisVertical;
    self.speedDialGridStack.spacing = 18.0;
    [self.startPageStack addArrangedSubview:self.speedDialGridStack];

    // Subtle single-line Privacy Shield status pill (tappable to open Shields)
    UIStackView *footerCenter = [[UIStackView alloc] init];
    footerCenter.axis = UILayoutConstraintAxisVertical;
    footerCenter.alignment = UIStackViewAlignmentCenter;
    self.shieldSummaryPill = [[PDMGlassPillButton alloc] initWithTitle:@"Shields Active" symbolName:@"shield.lefthalf.filled"];
    self.shieldSummaryPill.borderless = YES;
    self.shieldSummaryPill.symbolPointSize = 12.5;
    self.shieldSummaryPill.horizontalPadding = 10.0;
    self.shieldSummaryPill.verticalPadding = 6.0;
    [self.shieldSummaryPill addTarget:self action:@selector(handleShieldTap) forControlEvents:UIControlEventTouchUpInside];
    [footerCenter addArrangedSubview:self.shieldSummaryPill];
    [self.startPageStack addArrangedSubview:footerCenter];

    [NSLayoutConstraint activateConstraints:@[
        [self.startPageStack.topAnchor constraintEqualToAnchor:self.startPageScroll.contentLayoutGuide.topAnchor constant:72.0],
        [self.startPageStack.bottomAnchor constraintEqualToAnchor:self.startPageScroll.contentLayoutGuide.bottomAnchor constant:-32.0],
        [self.startPageStack.leadingAnchor constraintEqualToAnchor:self.startPageScroll.frameLayoutGuide.leadingAnchor constant:20.0],
        [self.startPageStack.trailingAnchor constraintEqualToAnchor:self.startPageScroll.frameLayoutGuide.trailingAnchor constant:-20.0]
    ]];

    [self refreshSearchEnginePill];
    [self rebuildSpeedDialGrid];
}

- (void)rebuildSpeedDialGrid {
    PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;
    for (UIView *v in [self.speedDialGridStack.arrangedSubviews copy]) {
        [self.speedDialGridStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    NSInteger cols = 4;
    NSUInteger totalItems = self.speedDials.count + 1; // +1 for Chrome-style Add Shortcut circle
    NSUInteger idx = 0;
    while (idx < totalItems) {
        UIStackView *row = [[UIStackView alloc] init];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.spacing = 10.0;
        row.distribution = UIStackViewDistributionFillEqually;
        for (NSInteger c = 0; c < cols; c++) {
            if (idx < totalItems) {
                BOOL isAddTile = (idx == self.speedDials.count);
                UIControl *btn = [[UIControl alloc] init];
                btn.tag = (NSInteger)idx;
                if (isAddTile) {
                    [btn addTarget:self action:@selector(handleAddSpeedDialTap) forControlEvents:UIControlEventTouchUpInside];
                } else {
                    [btn addTarget:self action:@selector(handleSpeedDialTileTap:) forControlEvents:UIControlEventTouchUpInside];
                    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleSpeedDialLongPress:)];
                    [btn addGestureRecognizer:lp];
                }

                UIStackView *v = [[UIStackView alloc] init];
                v.axis = UILayoutConstraintAxisVertical;
                v.alignment = UIStackViewAlignmentCenter;
                v.spacing = 8.0;
                v.userInteractionEnabled = NO;
                v.translatesAutoresizingMaskIntoConstraints = NO;
                [btn addSubview:v];

                UIView *circle = [[UIView alloc] init];
                circle.translatesAutoresizingMaskIntoConstraints = NO;
                circle.backgroundColor = spec.secondaryCanvasColor;
                circle.layer.cornerRadius = 26.0;
                circle.userInteractionEnabled = NO;

                NSString *sym = isAddTile ? @"plus" : self.speedDials[idx][@"symbol"];
                UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:19.0 weight:UIImageSymbolWeightMedium];
                UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:(sym.length > 0 ? sym : @"globe") withConfiguration:cfg]];
                iv.contentMode = UIViewContentModeScaleAspectFit;
                iv.tintColor = isAddTile ? spec.secondaryTextColor : spec.primaryTextColor;
                iv.translatesAutoresizingMaskIntoConstraints = NO;
                [circle addSubview:iv];

                [NSLayoutConstraint activateConstraints:@[
                    [circle.widthAnchor constraintEqualToConstant:52.0],
                    [circle.heightAnchor constraintEqualToConstant:52.0],
                    [iv.centerXAnchor constraintEqualToAnchor:circle.centerXAnchor],
                    [iv.centerYAnchor constraintEqualToAnchor:circle.centerYAnchor]
                ]];
                [v addArrangedSubview:circle];

                UILabel *lbl = [[UILabel alloc] init];
                lbl.text = isAddTile ? @"Add" : (self.speedDials[idx][@"title"] ?: @"Site");
                lbl.font = [[PDMThemeManager sharedManager] bodyFontOfSize:11.5 weight:UIFontWeightRegular];
                lbl.textColor = isAddTile ? spec.secondaryTextColor : spec.primaryTextColor;
                lbl.textAlignment = NSTextAlignmentCenter;
                lbl.lineBreakMode = NSLineBreakByTruncatingTail;
                [v addArrangedSubview:lbl];

                [NSLayoutConstraint activateConstraints:@[
                    [v.topAnchor constraintEqualToAnchor:btn.topAnchor constant:2.0],
                    [v.bottomAnchor constraintEqualToAnchor:btn.bottomAnchor constant:-2.0],
                    [v.leadingAnchor constraintEqualToAnchor:btn.leadingAnchor constant:2.0],
                    [v.trailingAnchor constraintEqualToAnchor:btn.trailingAnchor constant:-2.0]
                ]];
                [row addArrangedSubview:btn];
                idx++;
            } else {
                [row addArrangedSubview:[[UIView alloc] init]];
            }
        }
        [self.speedDialGridStack addArrangedSubview:row];
    }
}

- (void)buildFindInPageBar {
    PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;
    self.findBar = [[PDMGlassView alloc] initWithCornerRadius:14.0 elevated:YES];
    self.findBar.hidden = YES;
    self.findBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.findBar];

    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 6.0;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [self.findBar.contentView addSubview:row];

    self.findField = [[UITextField alloc] init];
    self.findField.placeholder = @"Find in page";
    self.findField.font = [[PDMThemeManager sharedManager] bodyFontOfSize:14.5 weight:UIFontWeightRegular];
    self.findField.textColor = spec.primaryTextColor;
    self.findField.tintColor = spec.accentColor;
    [self.findField addTarget:self action:@selector(handleFindTextChanged) forControlEvents:UIControlEventEditingChanged];
    [row addArrangedSubview:self.findField];

    self.findCountLabel = [[UILabel alloc] init];
    self.findCountLabel.text = @"0/0";
    self.findCountLabel.font = [[PDMThemeManager sharedManager] tabularFontOfSize:12.0 weight:UIFontWeightMedium];
    self.findCountLabel.textColor = spec.secondaryTextColor;
    [row addArrangedSubview:self.findCountLabel];

    PDMGlassPillButton *prevBtn = [[PDMGlassPillButton alloc] initWithTitle:nil symbolName:@"chevron.up"];
    prevBtn.borderless = YES;
    prevBtn.horizontalPadding = 8.0; prevBtn.verticalPadding = 6.0;
    [prevBtn addTarget:self action:@selector(handleFindPrev) forControlEvents:UIControlEventTouchUpInside];
    [row addArrangedSubview:prevBtn];

    PDMGlassPillButton *nextBtn = [[PDMGlassPillButton alloc] initWithTitle:nil symbolName:@"chevron.down"];
    nextBtn.borderless = YES;
    nextBtn.horizontalPadding = 8.0; nextBtn.verticalPadding = 6.0;
    [nextBtn addTarget:self action:@selector(handleFindNext) forControlEvents:UIControlEventTouchUpInside];
    [row addArrangedSubview:nextBtn];

    PDMGlassPillButton *closeFind = [[PDMGlassPillButton alloc] initWithTitle:nil symbolName:@"xmark"];
    closeFind.borderless = YES;
    closeFind.horizontalPadding = 8.0; closeFind.verticalPadding = 6.0;
    [closeFind addTarget:self action:@selector(handleCloseFindBar) forControlEvents:UIControlEventTouchUpInside];
    [row addArrangedSubview:closeFind];

    [NSLayoutConstraint activateConstraints:@[
        [self.findBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8.0],
        [self.findBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12.0],
        [self.findBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12.0],
        [row.topAnchor constraintEqualToAnchor:self.findBar.contentView.topAnchor constant:8.0],
        [row.bottomAnchor constraintEqualToAnchor:self.findBar.contentView.bottomAnchor constant:-8.0],
        [row.leadingAnchor constraintEqualToAnchor:self.findBar.contentView.leadingAnchor constant:12.0],
        [row.trailingAnchor constraintEqualToAnchor:self.findBar.contentView.trailingAnchor constant:-8.0]
    ]];
}

#pragma mark - Chrome Address Bar Position (Top / Bottom)

- (void)handleLayoutPresetChanged {
    [self rebuildChromeForCurrentLayoutPreset];
}

- (void)rebuildChromeForCurrentLayoutPreset {
    for (UIView *v in [self.topChromeHostStack.arrangedSubviews copy]) {
        [self.topChromeHostStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    for (UIView *v in [self.bottomChromeOuterStack.arrangedSubviews copy]) {
        [self.bottomChromeOuterStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }

    PDMLayoutPreset preset = [PDMThemeManager sharedManager].layoutPreset;
    if (preset == PDMLayoutChromeTop) {
        [self.topChromeHostStack addArrangedSubview:self.omnibarPill];
        [self.bottomChromeOuterStack addArrangedSubview:self.bottomNavRow];
    } else {
        [self.bottomChromeOuterStack addArrangedSubview:self.omnibarPill];
        [self.bottomChromeOuterStack addArrangedSubview:self.bottomNavRow];
    }
    [self syncChromeVisibility];
    [self updateNavigationUI];
}

- (void)syncChromeVisibility {
    PDMLayoutPreset preset = [PDMThemeManager sharedManager].layoutPreset;
    BOOL isNewTab = (self.activeTab == nil || self.activeTab.isNewTab);
    BOOL showTopBar = (preset == PDMLayoutChromeTop && !isNewTab);

    self.topChromeBar.hidden = !showTopBar;
    self.webTopToTopBar.active = showTopBar;
    self.webTopToSafeArea.active = !showTopBar;
    self.omnibarPill.hidden = (preset == PDMLayoutChromeBottom && isNewTab);
}

#pragma mark - Theme Refresh

- (void)applyTheme {
    PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;
    self.overrideUserInterfaceStyle = spec.interfaceStyle;
    self.view.backgroundColor = spec.canvasColor;
    self.startPageScroll.backgroundColor = spec.canvasColor;
    self.webContainerView.backgroundColor = spec.canvasColor;

    self.topChromeBar.backgroundColor = spec.canvasColor;
    self.bottomChromeBar.backgroundColor = spec.canvasColor;
    self.topHairline.backgroundColor = spec.glassSpecularBorderColor;
    self.bottomHairline.backgroundColor = spec.glassSpecularBorderColor;

    self.omnibarPill.backgroundColor = spec.secondaryCanvasColor;
    self.heroSearchPill.backgroundColor = spec.secondaryCanvasColor;
    self.heroSearchIcon.tintColor = spec.secondaryTextColor;

    self.loadProgressView.progressTintColor = spec.accentColor;
    self.loadProgressView.trackTintColor = [UIColor clearColor];

    self.omnibarField.textColor = spec.primaryTextColor;
    self.omnibarField.tintColor = spec.accentColor;
    self.startSearchField.textColor = spec.primaryTextColor;
    self.startSearchField.tintColor = spec.accentColor;
    self.clipboardURLLabel.textColor = spec.primaryTextColor;
    self.findField.textColor = spec.primaryTextColor;
    self.findField.tintColor = spec.accentColor;

    self.shieldBtn.customAccentColor = spec.secondaryTextColor;
    self.reloadBtn.customAccentColor = spec.secondaryTextColor;
    self.startEnginePill.customAccentColor = spec.secondaryTextColor;
    self.shieldSummaryPill.customAccentColor = spec.secondaryTextColor;
    [self.tabsBtn applyTheme];

    UILabel *bTitle = (UILabel *)[self.view viewWithTag:8001];
    if ([bTitle isKindOfClass:[UILabel class]]) bTitle.textColor = spec.primaryTextColor;

    [self rebuildSpeedDialGrid];
}

#pragma mark - Tab & WebView Lifecycle

- (WKWebView *)createWebViewForPrivate:(BOOL)isPrivate {
    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    cfg.websiteDataStore = isPrivate ? [WKWebsiteDataStore nonPersistentDataStore] : [WKWebsiteDataStore defaultDataStore];
    cfg.allowsInlineMediaPlayback = YES;
    cfg.allowsPictureInPictureMediaPlayback = YES;
    cfg.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;

    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    PDMWeakScriptMessageHandler *weakHandler = [[PDMWeakScriptMessageHandler alloc] initWithDelegate:self];
    [ucc addScriptMessageHandler:weakHandler name:@"pdmMedia"];
    [ucc addScriptMessageHandler:weakHandler name:@"pdmShield"];
    [ucc addUserScript:[PDMMediaSniffer mediaSnifferUserScript]];
    [ucc addUserScript:[[PDMPrivacyShieldEngine sharedEngine] cosmeticAdHiderUserScript]];
    [[PDMPrivacyShieldEngine sharedEngine] applyRulesToUserContentController:ucc forHost:nil];
    cfg.userContentController = ucc;

    WKWebView *wv = [[WKWebView alloc] initWithFrame:self.webContainerView.bounds configuration:cfg];
    wv.translatesAutoresizingMaskIntoConstraints = NO;
    wv.navigationDelegate = self;
    wv.UIDelegate = self;
    wv.allowsBackForwardNavigationGestures = YES;
    wv.scrollView.delegate = self;
    wv.customUserAgent = [[PDMPrivacyShieldEngine sharedEngine] mobileUserAgent];
    return wv;
}

- (void)createAndActivateTabIsPrivate:(BOOL)isPrivate initialURL:(nullable NSURL *)url {
    NSMutableArray<PDMTabItem *> *list = isPrivate ? self.privateTabs : self.standardTabs;
    if ((NSInteger)list.count >= kPDMMaxTabCount) {
        [list removeObjectAtIndex:0];
    }
    PDMTabItem *tab = [[PDMTabItem alloc] init];
    tab.isPrivate = isPrivate;
    tab.isNewTab = (url == nil);
    tab.title = isPrivate ? @"Private Tab" : @"New Tab";
    tab.webView = [self createWebViewForPrivate:isPrivate];
    [list addObject:tab];

    [self activateTab:tab];
    if (url) {
        [self loadURL:url inTab:tab];
    }
}

- (void)detachObserversFromCurrentTab {
    if (self.observedWebViewTab && self.observedWebViewTab.webView) {
        @try {
            [self.observedWebViewTab.webView removeObserver:self forKeyPath:@"estimatedProgress"];
            [self.observedWebViewTab.webView removeObserver:self forKeyPath:@"title"];
            [self.observedWebViewTab.webView removeObserver:self forKeyPath:@"URL"];
        } @catch (NSException *__unused e) {
        }
    }
    self.observedWebViewTab = nil;
}

- (void)captureSnapshotForTab:(nullable PDMTabItem *)tab {
    if (!tab || tab.isNewTab || !tab.webView) return;
    WKSnapshotConfiguration *sc = [[WKSnapshotConfiguration alloc] init];
    sc.snapshotWidth = @280;
    [tab.webView takeSnapshotWithConfiguration:sc completionHandler:^(UIImage * _Nullable image, NSError * _Nullable __unused error) {
        if (image) {
            tab.snapshot = image;
        }
    }];
}

- (void)activateTab:(PDMTabItem *)tab {
    [self captureSnapshotForTab:self.activeTab];
    [self detachObserversFromCurrentTab];

    for (UIView *sub in [self.webContainerView.subviews copy]) {
        [sub removeFromSuperview];
    }

    self.activeTab = tab;
    if (tab.webView) {
        [self.webContainerView addSubview:tab.webView];
        [NSLayoutConstraint activateConstraints:@[
            [tab.webView.topAnchor constraintEqualToAnchor:self.webContainerView.topAnchor],
            [tab.webView.leadingAnchor constraintEqualToAnchor:self.webContainerView.leadingAnchor],
            [tab.webView.trailingAnchor constraintEqualToAnchor:self.webContainerView.trailingAnchor],
            [tab.webView.bottomAnchor constraintEqualToAnchor:self.webContainerView.bottomAnchor]
        ]];
        [tab.webView addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:nil];
        [tab.webView addObserver:self forKeyPath:@"title" options:NSKeyValueObservingOptionNew context:nil];
        [tab.webView addObserver:self forKeyPath:@"URL" options:NSKeyValueObservingOptionNew context:nil];
        self.observedWebViewTab = tab;
    }

    self.startPageScroll.hidden = !tab.isNewTab;
    self.webContainerView.hidden = tab.isNewTab;
    [self syncChromeVisibility];
    [self updateNavigationUI];
}

- (void)loadURL:(NSURL *)url inTab:(PDMTabItem *)tab {
    NSURL *finalURL = [[PDMPrivacyShieldEngine sharedEngine] upgradedURLIfNeeded:url];
    NSString *host = finalURL.host;
    PDMSiteShieldSettings *settings = [[PDMPrivacyShieldEngine sharedEngine] settingsForHost:host];
    tab.webView.customUserAgent = settings.useDesktopUserAgent
        ? [[PDMPrivacyShieldEngine sharedEngine] desktopUserAgent]
        : [[PDMPrivacyShieldEngine sharedEngine] mobileUserAgent];
    [[PDMPrivacyShieldEngine sharedEngine] applyRulesToUserContentController:tab.webView.configuration.userContentController forHost:host];

    tab.isNewTab = NO;
    tab.urlString = finalURL.absoluteString;
    [tab.detectedMedia removeAllObjects];
    self.startPageScroll.hidden = YES;
    self.webContainerView.hidden = NO;
    [self syncChromeVisibility];

    [tab.webView loadRequest:[NSURLRequest requestWithURL:finalURL]];
    [self updateNavigationUI];
}

- (void)openExternalURL:(NSURL *)url {
    if (!url) return;
    if (!self.activeTab) {
        [self createAndActivateTabIsPrivate:NO initialURL:url];
    } else {
        [self loadURL:url inTab:self.activeTab];
    }
}

- (void)performExitCleanupIfEnabled {
    if ([PDMThemeManager sharedManager].clearDataOnExit) {
        [self.historyEntries removeAllObjects];
        [self saveHistory];
        [[PDMPrivacyShieldEngine sharedEngine] clearAllBrowsingDataWithCompletion:nil];
    }
}

#pragma mark - KVO & UI Sync

- (void)observeValueForKeyPath:(nullable NSString *)keyPath
                      ofObject:(nullable id)object
                        change:(nullable NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(nullable void *)context {
    (void)change;
    (void)context;
    if (object != self.activeTab.webView) return;
    if ([keyPath isEqualToString:@"estimatedProgress"]) {
        float prog = (float)self.activeTab.webView.estimatedProgress;
        self.loadProgressView.hidden = (prog >= 1.0f || self.activeTab.isNewTab);
        [self.loadProgressView setProgress:prog animated:YES];
        self.reloadBtn.symbolName = (prog < 1.0f && self.activeTab.webView.isLoading) ? @"xmark" : @"arrow.clockwise";
    } else if ([keyPath isEqualToString:@"title"] || [keyPath isEqualToString:@"URL"]) {
        self.activeTab.title = self.activeTab.webView.title ?: self.activeTab.title;
        if (self.activeTab.webView.URL.absoluteString.length > 0) {
            self.activeTab.urlString = self.activeTab.webView.URL.absoluteString;
        }
        [self updateNavigationUI];
    }
}

- (void)updateNavigationUI {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateNavigationUI];
        });
        return;
    }
    PDMTabItem *tab = self.activeTab;
    NSArray *list = tab.isPrivate ? self.privateTabs : self.standardTabs;
    self.tabsBtn.tabCount = (NSInteger)MAX((NSUInteger)1, list.count);
    self.tabsBtn.privateMode = tab.isPrivate;

    if (!self.omnibarField.isFirstResponder) {
        if (tab.isNewTab) {
            self.omnibarField.text = @"";
        } else {
            self.omnibarField.text = tab.webView.URL.host ?: tab.urlString;
        }
    }

    BOOL isHTTPS = [tab.webView.URL.scheme.lowercaseString isEqualToString:@"https"];
    self.shieldBtn.symbolName = isHTTPS ? @"lock.fill" : @"shield.lefthalf.filled";
    self.shieldBtn.badgeText = nil;

    NSUInteger mediaCount = tab.detectedMedia.count;
    self.mediaGrabBtn.hidden = (mediaCount == 0 || tab.isNewTab);
    if (mediaCount > 0) {
        self.mediaGrabBtn.titleText = (mediaCount == 1) ? @"Save" : [NSString stringWithFormat:@"%lu", (unsigned long)mediaCount];
    }

    self.backBtn.enabled = tab.webView.canGoBack;
    self.backBtn.alpha = tab.webView.canGoBack ? 1.0 : 0.32;
    self.forwardBtn.enabled = tab.webView.canGoForward;
    self.forwardBtn.alpha = tab.webView.canGoForward ? 1.0 : 0.32;
}

- (void)refreshPrivacyStatsUI {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self refreshPrivacyStatsUI];
        });
        return;
    }
    PDMPrivacyShieldEngine *e = [PDMPrivacyShieldEngine sharedEngine];
    NSInteger totalBlocked = e.adsBlocked + e.trackersBlocked + e.popupsBlocked;
    if (totalBlocked > 0) {
        self.shieldSummaryPill.titleText = [NSString stringWithFormat:@"Shields Active · %ld blocked", (long)totalBlocked];
    } else {
        self.shieldSummaryPill.titleText = @"Shields Active";
    }
    [self updateNavigationUI];
}

- (void)refreshDownloadsIndicators {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self refreshDownloadsIndicators];
        });
        return;
    }
    PDMDownloadManager *dm = [PDMDownloadManager sharedManager];
    NSInteger active = dm.activeCount + dm.queuedCount;
    self.downloadsBtn.badgeText = (active > 0) ? [NSString stringWithFormat:@"%ld", (long)active] : nil;

    self.activeDownloadsMiniCard.hidden = (active == 0);
    if (active > 0) {
        self.miniCardTitleLabel.text = [NSString stringWithFormat:@"%ld active download%@", (long)active, active == 1 ? @"" : @"s"];
        self.miniCardSubtitleLabel.text = [NSString stringWithFormat:@"%@ · Tap to view", [PDMThemeManager formatSpeed:dm.aggregateSpeedBytesPerSec]];
    }
}

- (void)refreshSearchEnginePill {
    PDMThemeManager *tm = [PDMThemeManager sharedManager];
    self.startEnginePill.titleText = [tm displayNameForSearchEngine:tm.searchEngine];
}

- (void)checkClipboardForURL {
    NSString *clip = [UIPasteboard generalPasteboard].string;
    if (clip.length > 7 && ([clip.lowercaseString hasPrefix:@"http://"] || [clip.lowercaseString hasPrefix:@"https://"])) {
        self.detectedClipboardURL = clip;
        self.clipboardURLLabel.text = [NSString stringWithFormat:@"Link you copied: %@", clip];
        self.clipboardPasteCard.hidden = NO;
    } else {
        self.detectedClipboardURL = nil;
        self.clipboardPasteCard.hidden = YES;
    }
}

#pragma mark - WKScriptMessageHandler (Media Sniffer & Cosmetic Shield)

- (void)userContentController:(WKUserContentController *__unused)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.name isEqualToString:@"pdmShield"]) {
        if ([message.body isKindOfClass:[NSDictionary class]]) {
            NSDictionary *d = (NSDictionary *)message.body;
            NSInteger count = [d[@"count"] integerValue];
            NSString *host = [d[@"host"] isKindOfClass:[NSString class]] ? d[@"host"] : self.activeTab.webView.URL.host;
            if (count > 0) {
                [[PDMPrivacyShieldEngine sharedEngine] recordBlockedAdForHost:host count:count];
            }
        }
        return;
    }

    if ([message.name isEqualToString:@"pdmMedia"]) {
        PDMTabItem *tab = self.activeTab;
        if (!tab) return;
        __weak typeof(self) weakSelf = self;
        [tab.webView.configuration.websiteDataStore.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            NSMutableArray<NSString *> *ckPairs = [NSMutableArray array];
            NSString *host = tab.webView.URL.host.lowercaseString ?: @"";
            for (NSHTTPCookie *c in cookies) {
                if (host.length == 0 || [host hasSuffix:c.domain.lowercaseString] || [c.domain.lowercaseString containsString:host]) {
                    [ckPairs addObject:[NSString stringWithFormat:@"%@=%@", c.name, c.value]];
                }
            }
            NSString *cookieHeader = (ckPairs.count > 0) ? [ckPairs componentsJoinedByString:@"; "] : nil;
            PDMDetectedMedia *detected = [PDMMediaSniffer mediaFromMessageBody:message.body
                                                                       pageURL:tab.webView.URL.absoluteString
                                                                     pageTitle:tab.webView.title
                                                                     userAgent:tab.webView.customUserAgent
                                                                  cookieHeader:cookieHeader];
            if (!detected) return;
            for (PDMDetectedMedia *existing in tab.detectedMedia) {
                if ([existing.urlString isEqualToString:detected.urlString]) return;
            }
            [tab.detectedMedia insertObject:detected atIndex:0];
            [strongSelf updateNavigationUI];
        }];
    }
}

#pragma mark - WKNavigationDelegate & WKUIDelegate

- (void)webView:(WKWebView *)webView
decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = navigationAction.request.URL;
    if (!url) {
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    if (navigationAction.targetFrame.isMainFrame && [url.scheme.lowercaseString isEqualToString:@"http"]) {
        NSURL *upgraded = [[PDMPrivacyShieldEngine sharedEngine] upgradedURLIfNeeded:url];
        if (![upgraded.absoluteString isEqualToString:url.absoluteString]) {
            decisionHandler(WKNavigationActionPolicyCancel);
            [webView loadRequest:[NSURLRequest requestWithURL:upgraded]];
            return;
        }
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView
decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse
decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    if (!navigationResponse.canShowMIMEType || [PDMMediaSniffer isDownloadableResponse:navigationResponse.response]) {
        NSURL *url = navigationResponse.response.URL;
        if (url) {
            PDMDetectedMedia *m = [[PDMDetectedMedia alloc] init];
            m.urlString = url.absoluteString;
            m.pageURLString = webView.URL.absoluteString;
            m.referer = webView.URL.absoluteString;
            m.userAgent = webView.customUserAgent;
            m.mimeType = navigationResponse.response.MIMEType;
            m.contentLength = navigationResponse.response.expectedContentLength;
            m.title = navigationResponse.response.suggestedFilename ?: url.lastPathComponent;
            m.filename = [PDMThemeManager sanitizeFilename:m.title fallbackExtension:url.pathExtension];
            m.sourceBadge = [PDMMediaSniffer sourceBadgeForURLString:m.urlString mimeType:m.mimeType];
            m.isHLS = [m.sourceBadge isEqualToString:@"HLS"];
            [self presentMediaPickerForDetectedMedia:m];
        }
        decisionHandler(WKNavigationResponsePolicyCancel);
        return;
    }
    decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *__unused)navigation {
    if (webView == self.activeTab.webView) {
        NSString *host = webView.URL.host;
        PDMSiteShieldSettings *settings = [[PDMPrivacyShieldEngine sharedEngine] settingsForHost:host];
        if (settings.forceDarkMode) {
            [webView evaluateJavaScript:[[PDMPrivacyShieldEngine sharedEngine] toggleDarkModeJavaScript:YES] completionHandler:nil];
        }
        if (webView.URL.absoluteString.length > 0) {
            [self recordHistoryTitle:(webView.title ?: webView.URL.host) urlString:webView.URL.absoluteString];
        }
        if (settings.shieldsEnabled && host.length > 0) {
            [[PDMPrivacyShieldEngine sharedEngine] recordBlockedTrackerForHost:host count:1];
        }
        [self updateNavigationUI];
    }
}

- (nullable WKWebView *)webView:(WKWebView *)webView
 createWebViewWithConfiguration:(WKWebViewConfiguration *__unused)configuration
            forNavigationAction:(WKNavigationAction *)navigationAction
                 windowFeatures:(WKWindowFeatures *__unused)windowFeatures {
    NSString *host = webView.URL.host;
    PDMSiteShieldSettings *settings = [[PDMPrivacyShieldEngine sharedEngine] settingsForHost:host];
    BOOL isUserLink = (navigationAction.navigationType == WKNavigationTypeLinkActivated);
    if (settings.shieldsEnabled && settings.blockPopups && !isUserLink) {
        [[PDMPrivacyShieldEngine sharedEngine] recordBlockedPopupForHost:host];
        [PDMToastBanner showInView:self.view message:@"Blocked popup" symbolName:@"shield.lefthalf.filled"];
        return nil;
    }
    if (navigationAction.request.URL) {
        [self createAndActivateTabIsPrivate:self.activeTab.isPrivate initialURL:navigationAction.request.URL];
    }
    return nil;
}

#pragma mark - TextField Navigation

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    if (textField == self.omnibarField && !self.activeTab.isNewTab && self.activeTab.urlString.length > 0) {
        textField.text = self.activeTab.urlString;
        dispatch_async(dispatch_get_main_queue(), ^{
            [textField selectAll:nil];
        });
    }
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    if (textField == self.omnibarField) {
        [self updateNavigationUI];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    NSString *input = textField.text ?: @"";
    [textField resignFirstResponder];
    NSURL *url = [[PDMThemeManager sharedManager] searchURLForQuery:input];
    if (url && self.activeTab) {
        [self loadURL:url inTab:self.activeTab];
    }
    return YES;
}

#pragma mark - Chrome Button Handlers

- (void)handleQuickSearchEngineSwitch {
    [[PDMThemeManager sharedManager] triggerLightImpact];
    PDMThemeManager *tm = [PDMThemeManager sharedManager];
    NSMutableArray<PDMGlassActionItem *> *actions = [NSMutableArray array];
    for (NSInteger i = 0; i <= PDMSearchEngineCustom; i++) {
        PDMSearchEngine eng = (PDMSearchEngine)i;
        BOOL isCur = (tm.searchEngine == eng);
        PDMGlassActionItem *act = [PDMGlassActionItem actionWithTitle:[tm displayNameForSearchEngine:eng]
                                                             subtitle:(isCur ? @"Active search engine" : nil)
                                                           symbolName:[tm symbolNameForSearchEngine:eng]
                                                          destructive:NO
                                                              handler:^{
            tm.searchEngine = eng;
            [self refreshSearchEnginePill];
        }];
        act.prominent = isCur;
        [actions addObject:act];
    }
    [PDMGlassActionSheetController presentFrom:self
                                         title:@"Search Engine"
                                      subtitle:@"Switch instantly for Speed Dial & Omnibar"
                                    symbolName:@"magnifyingglass.circle.fill"
                                       actions:actions];
}

- (void)handleClipboardQuickPasteTap {
    if (self.detectedClipboardURL.length == 0) return;
    NSURL *u = [NSURL URLWithString:self.detectedClipboardURL];
    if (u && self.activeTab) {
        [[PDMThemeManager sharedManager] triggerLightImpact];
        [self loadURL:u inTab:self.activeTab];
    }
}

- (void)handleSpeedDialTileTap:(UIControl *)sender {
    if (sender.tag < 0 || sender.tag >= (NSInteger)self.speedDials.count) return;
    NSString *urlStr = self.speedDials[(NSUInteger)sender.tag][@"url"];
    NSURL *u = [NSURL URLWithString:urlStr];
    if (u && self.activeTab) {
        [[PDMThemeManager sharedManager] triggerLightImpact];
        [self loadURL:u inTab:self.activeTab];
    }
}

- (void)handleSpeedDialLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    NSInteger idx = gr.view.tag;
    if (idx < 0 || idx >= (NSInteger)self.speedDials.count) return;
    NSString *title = self.speedDials[(NSUInteger)idx][@"title"] ?: @"Tile";
    __weak typeof(self) weakSelf = self;
    PDMGlassActionItem *rm = [PDMGlassActionItem actionWithTitle:@"Remove from Speed Dial"
                                                        subtitle:title
                                                      symbolName:@"trash"
                                                     destructive:YES
                                                         handler:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf.speedDials removeObjectAtIndex:(NSUInteger)idx];
        [strongSelf saveSpeedDials];
        [strongSelf rebuildSpeedDialGrid];
    }];
    [PDMGlassActionSheetController presentFrom:self title:title subtitle:@"Speed Dial Tile" symbolName:@"pin.slash" actions:@[rm]];
}

- (void)handleAddSpeedDialTap {
    [[PDMThemeManager sharedManager] triggerLightImpact];
    __weak typeof(self) weakSelf = self;
    [PDMGlassActionSheetController presentTextInputFrom:self
                                                  title:@"Pin to Speed Dial"
                                               subtitle:@"Enter website URL to pin to your Start Page"
                                            placeholder:@"https://example.com"
                                            initialText:self.activeTab.urlString
                                           confirmTitle:@"Pin Tile"
                                              onConfirm:^(NSString *value) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSURL *u = [[PDMThemeManager sharedManager] searchURLForQuery:value];
        if (!u) return;
        NSString *name = u.host ?: @"Pinned Site";
        [strongSelf.speedDials addObject:@{@"title": name, @"url": u.absoluteString, @"symbol": @"star.fill"}];
        [strongSelf saveSpeedDials];
        [strongSelf rebuildSpeedDialGrid];
    }];
}

- (void)handleShieldTap {
    [[PDMThemeManager sharedManager] triggerMediumImpact];
    PDMShieldSheetViewController *sheet = [[PDMShieldSheetViewController alloc] init];
    sheet.currentHost = self.activeTab.webView.URL.host ?: @"";
    __weak typeof(self) weakSelf = self;
    sheet.onSettingsChanged = ^(PDMSiteShieldSettings *settings) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.activeTab.webView) return;
        WKWebView *wv = strongSelf.activeTab.webView;
        [[PDMPrivacyShieldEngine sharedEngine] applyRulesToUserContentController:wv.configuration.userContentController forHost:settings.host];
        wv.customUserAgent = settings.useDesktopUserAgent
            ? [[PDMPrivacyShieldEngine sharedEngine] desktopUserAgent]
            : [[PDMPrivacyShieldEngine sharedEngine] mobileUserAgent];
        [wv evaluateJavaScript:[[PDMPrivacyShieldEngine sharedEngine] toggleDarkModeJavaScript:settings.forceDarkMode] completionHandler:nil];
        [wv reload];
    };
    sheet.onClearSiteData = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf && strongSelf.activeTab.webView) {
            [strongSelf.activeTab.webView reload];
        }
    };
    [sheet presentFromViewController:self];
}

- (void)presentMediaPickerForDetectedMedia:(PDMDetectedMedia *)media {
    PDMMediaPickerSheetViewController *picker = [[PDMMediaPickerSheetViewController alloc] init];
    picker.media = media;
    __weak typeof(self) weakSelf = self;
    picker.onStreamPreviewRequested = ^(NSURL *streamURL, NSString *title, NSDictionary<NSString *, NSString *> *headers) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        PDMMediaPlayerViewController *player = [[PDMMediaPlayerViewController alloc] initWithURL:streamURL title:title httpHeaders:headers];
        [strongSelf presentViewController:player animated:YES completion:nil];
    };
    picker.onDownloadRequested = ^(PDMDetectedMedia *m,
                                   PDMMediaVideoVariant *v,
                                   PDMMediaAudioTrack *a,
                                   PDMMediaFormatConfig *cfg,
                                   NSString *finalName,
                                   BOOL startNow) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *dlURL = (v.uri.length > 0 && !v.isAudioOnly) ? v.uri : m.urlString;
        if (v.isAudioOnly && a.uri.length > 0) {
            dlURL = a.uri;
        }
        BOOL isHLSStream = m.isHLS || [dlURL.lowercaseString containsString:@".m3u8"];
        [[PDMDownloadManager sharedManager] enqueueDownloadWithURL:dlURL
                                                          filename:finalName
                                                           referer:m.referer
                                                         userAgent:m.userAgent
                                                      cookieHeader:m.cookieHeader
                                                      formatConfig:cfg
                                                      qualityLabel:v.label
                                                   audioTrackLabel:[a displayLabel]
                                                             isHLS:isHLSStream
                                                  hlsAudioTrackURL:a.uri
                                                  startImmediately:startNow];
        [PDMToastBanner showInView:strongSelf.view
                           message:[NSString stringWithFormat:(startNow ? @"Downloading %@" : @"Queued %@"), finalName]
                        symbolName:@"arrow.down.circle.fill"];
    };
    [picker presentFromViewController:self];
}

- (void)handleMediaGrabTap {
    [[PDMThemeManager sharedManager] triggerMediumImpact];
    NSArray<PDMDetectedMedia *> *list = self.activeTab.detectedMedia;
    if (list.count == 0) return;
    if (list.count == 1) {
        [self presentMediaPickerForDetectedMedia:list.firstObject];
        return;
    }
    NSMutableArray<PDMGlassActionItem *> *actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (PDMDetectedMedia *m in list) {
        PDMGlassActionItem *act = [PDMGlassActionItem actionWithTitle:m.filename
                                                             subtitle:[NSString stringWithFormat:@"%@ · %@", m.sourceBadge, m.urlString]
                                                           symbolName:(m.isHLS ? @"sparkles.tv.fill" : @"film.fill")
                                                          destructive:NO
                                                              handler:^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) [strongSelf presentMediaPickerForDetectedMedia:m];
        }];
        [actions addObject:act];
    }
    [PDMGlassActionSheetController presentFrom:self
                                         title:@"Detected Media Streams"
                                      subtitle:@"Choose a stream to pick quality, multi-audio & format"
                                    symbolName:@"arrow.down.circle.fill"
                                       actions:actions];
}

- (void)handleTabsTap {
    [[PDMThemeManager sharedManager] triggerLightImpact];
    [self captureSnapshotForTab:self.activeTab];

    PDMTabGridViewController *grid = [[PDMTabGridViewController alloc] init];
    grid.modalPresentationStyle = UIModalPresentationPageSheet;
    grid.standardTabs = self.standardTabs;
    grid.privateTabs = self.privateTabs;
    grid.activeTabID = self.activeTab.tabID;
    grid.showingPrivateSegment = self.activeTab.isPrivate;
    grid.canReopenClosedTab = (self.closedTabsHistory.count > 0);

    __weak typeof(self) weakSelf = self;
    grid.onSelectTab = ^(PDMTabItem *tab) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) [strongSelf activateTab:tab];
    };
    grid.onNewTab = ^(BOOL isPrivate) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) [strongSelf createAndActivateTabIsPrivate:isPrivate initialURL:nil];
    };
    grid.onCloseTab = ^(PDMTabItem *tab) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (!tab.isPrivate && tab.urlString.length > 0) {
            [strongSelf.closedTabsHistory addObject:@{@"url": tab.urlString, @"title": tab.title ?: @""}];
        }
        NSMutableArray *list = tab.isPrivate ? strongSelf.privateTabs : strongSelf.standardTabs;
        [list removeObject:tab];
        if (tab == strongSelf.activeTab) {
            if (list.count > 0) {
                [strongSelf activateTab:list.lastObject];
            } else {
                [strongSelf createAndActivateTabIsPrivate:tab.isPrivate initialURL:nil];
            }
        }
        [strongSelf updateNavigationUI];
    };
    grid.onCloseAllTabs = ^(BOOL isPrivate) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSMutableArray *list = isPrivate ? strongSelf.privateTabs : strongSelf.standardTabs;
        [list removeAllObjects];
        [strongSelf createAndActivateTabIsPrivate:isPrivate initialURL:nil];
    };
    grid.onReopenLastClosed = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.closedTabsHistory.count == 0) return;
        NSDictionary *last = strongSelf.closedTabsHistory.lastObject;
        [strongSelf.closedTabsHistory removeLastObject];
        NSURL *u = [NSURL URLWithString:last[@"url"]];
        [strongSelf createAndActivateTabIsPrivate:NO initialURL:u];
    };

    [self presentViewController:grid animated:YES completion:nil];
}

- (void)handleDownloadsTap {
    [[PDMThemeManager sharedManager] triggerLightImpact];
    PDMDownloadManagerViewController *dlVC = [[PDMDownloadManagerViewController alloc] init];
    dlVC.modalPresentationStyle = UIModalPresentationPageSheet;
    __weak typeof(self) weakSelf = self;
    dlVC.onOpenLibraryRequested = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) [strongSelf presentLibrary];
    };
    dlVC.onOpenSettingsRequested = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) [strongSelf presentSettingsStudio];
    };
    [self presentViewController:dlVC animated:YES completion:nil];
}

- (void)presentLibrary {
    PDMLibraryViewController *lib = [[PDMLibraryViewController alloc] init];
    lib.modalPresentationStyle = UIModalPresentationPageSheet;
    __weak typeof(self) weakSelf = self;
    lib.onOpenDownloadsRequested = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) [strongSelf handleDownloadsTap];
    };
    [self presentViewController:lib animated:YES completion:nil];
}

- (void)presentSettingsStudio {
    PDMSettingsSheetViewController *settings = [[PDMSettingsSheetViewController alloc] init];
    __weak typeof(self) weakSelf = self;
    settings.onClearAllDataRequested = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf.historyEntries removeAllObjects];
        [strongSelf saveHistory];
        [[PDMPrivacyShieldEngine sharedEngine] clearAllBrowsingDataWithCompletion:nil];
    };
    [settings presentFromViewController:self];
}

- (void)handleBackTap {
    [self.activeTab.webView goBack];
}

- (void)handleForwardTap {
    [self.activeTab.webView goForward];
}

- (void)handleReloadTap {
    if (self.activeTab.webView.isLoading) {
        [self.activeTab.webView stopLoading];
    } else {
        [self.activeTab.webView reload];
    }
}

#pragma mark - Pro Browsing Utilities Menu

- (void)handleMenuTap {
    [[PDMThemeManager sharedManager] triggerLightImpact];
    BOOL onWebpage = !self.activeTab.isNewTab;
    NSString *host = self.activeTab.webView.URL.host ?: @"";
    PDMSiteShieldSettings *siteSettings = [[PDMPrivacyShieldEngine sharedEngine] settingsForHost:host];

    NSMutableArray<PDMGlassActionItem *> *actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;

    [actions addObject:[PDMGlassActionItem actionWithTitle:@"New Tab"
                                                  subtitle:nil
                                                symbolName:@"plus.square"
                                               destructive:NO
                                                   handler:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) [strongSelf createAndActivateTabIsPrivate:NO initialURL:nil];
    }]];

    [actions addObject:[PDMGlassActionItem actionWithTitle:@"New Private Tab"
                                                  subtitle:nil
                                                symbolName:@"eye.slash"
                                               destructive:NO
                                                   handler:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) [strongSelf createAndActivateTabIsPrivate:YES initialURL:nil];
    }]];

    [actions addObject:[PDMGlassActionItem actionWithTitle:@"Downloads"
                                                  subtitle:@"Active transfers & format conversions"
                                                symbolName:@"arrow.down.circle"
                                               destructive:NO
                                                   handler:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) [strongSelf handleDownloadsTap];
    }]];

    [actions addObject:[PDMGlassActionItem actionWithTitle:@"Library"
                                                  subtitle:@"Saved videos, audio, documents & private vault"
                                                symbolName:@"folder"
                                               destructive:NO
                                                   handler:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) [strongSelf presentLibrary];
    }]];

    if (onWebpage) {
        [actions addObject:[PDMGlassActionItem actionWithTitle:@"Grab Page Media & Links"
                                                      subtitle:@"Videos, audio, images & files on this page"
                                                    symbolName:@"square.stack.3d.down.right"
                                                   destructive:NO
                                                       handler:^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) [strongSelf launchResourceGrabber];
        }]];

        [actions addObject:[PDMGlassActionItem actionWithTitle:(siteSettings.forceDarkMode ? @"Disable Dark Webpage" : @"Force Dark Webpage")
                                                      subtitle:@"Apply dark styling to this site"
                                                    symbolName:@"moon"
                                                   destructive:NO
                                                       handler:^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            siteSettings.forceDarkMode = !siteSettings.forceDarkMode;
            [[PDMPrivacyShieldEngine sharedEngine] saveSettings:siteSettings];
            [strongSelf.activeTab.webView evaluateJavaScript:[[PDMPrivacyShieldEngine sharedEngine] toggleDarkModeJavaScript:siteSettings.forceDarkMode] completionHandler:nil];
        }]];

        [actions addObject:[PDMGlassActionItem actionWithTitle:@"Reader Mode"
                                                      subtitle:@"Clean reading view"
                                                    symbolName:@"doc.plaintext"
                                                   destructive:NO
                                                       handler:^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) [strongSelf launchReaderMode];
        }]];

        [actions addObject:[PDMGlassActionItem actionWithTitle:@"Find in Page"
                                                      subtitle:nil
                                                    symbolName:@"magnifyingglass"
                                                   destructive:NO
                                                       handler:^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) [strongSelf showFindInPageBar];
        }]];

        [actions addObject:[PDMGlassActionItem actionWithTitle:@"Add Bookmark"
                                                      subtitle:(self.activeTab.title ?: host)
                                                    symbolName:@"bookmark"
                                                   destructive:NO
                                                       handler:^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || strongSelf.activeTab.urlString.length == 0) return;
            [strongSelf.bookmarks insertObject:@{
                @"title": (strongSelf.activeTab.title ?: host),
                @"url": strongSelf.activeTab.urlString,
                @"folder": @"Favorites"
            } atIndex:0];
            [strongSelf saveBookmarks];
            [PDMToastBanner showInView:strongSelf.view message:@"Saved to Bookmarks" symbolName:@"bookmark.fill"];
        }]];

        [actions addObject:[PDMGlassActionItem actionWithTitle:@"Save as PDF"
                                                      subtitle:@"Export webpage to Library"
                                                    symbolName:@"doc.richtext"
                                                   destructive:NO
                                                       handler:^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) [strongSelf saveCurrentPageAsPDF];
        }]];
    }

    [actions addObject:[PDMGlassActionItem actionWithTitle:@"Bookmarks"
                                                  subtitle:[NSString stringWithFormat:@"%lu saved", (unsigned long)self.bookmarks.count]
                                                symbolName:@"book"
                                               destructive:NO
                                                   handler:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) [strongSelf presentBookmarksSheet];
    }]];

    [actions addObject:[PDMGlassActionItem actionWithTitle:@"History"
                                                  subtitle:[NSString stringWithFormat:@"%lu pages", (unsigned long)self.historyEntries.count]
                                                symbolName:@"clock"
                                               destructive:NO
                                                   handler:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) [strongSelf presentHistorySheet];
    }]];

    PDMGlassActionItem *studioItem = [PDMGlassActionItem actionWithTitle:@"Settings"
                                                                subtitle:@"Appearance, address bar, search & downloads"
                                                              symbolName:@"gearshape"
                                                             destructive:NO
                                                                 handler:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) [strongSelf presentSettingsStudio];
    }];
    studioItem.prominent = YES;
    [actions addObject:studioItem];

    [PDMGlassActionSheetController presentFrom:self
                                         title:@"Menu"
                                      subtitle:(onWebpage ? host : @"New Tab")
                                    symbolName:@"ellipsis.circle"
                                       actions:actions];
}

#pragma mark - Reader Mode, Resource Grabber, Find in Page, Save PDF, Bookmarks, History

- (void)launchReaderMode {
    WKWebView *wv = self.activeTab.webView;
    if (!wv) return;
    __weak typeof(self) weakSelf = self;
    [wv evaluateJavaScript:[[PDMPrivacyShieldEngine sharedEngine] readerModeExtractionJavaScript]
         completionHandler:^(id _Nullable result, NSError * _Nullable __unused error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || ![result isKindOfClass:[NSString class]]) return;
        NSData *d = [(NSString *)result dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *parsed = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
        if (![parsed isKindOfClass:[NSDictionary class]]) return;

        PDMReaderViewController *reader = [[PDMReaderViewController alloc] init];
        reader.articleTitle = parsed[@"title"];
        reader.articleHost = parsed[@"host"];
        reader.blocks = [parsed[@"blocks"] isKindOfClass:[NSArray class]] ? parsed[@"blocks"] : @[];
        [reader presentFromViewController:strongSelf];
    }];
}

- (void)launchResourceGrabber {
    WKWebView *wv = self.activeTab.webView;
    if (!wv) return;
    __weak typeof(self) weakSelf = self;
    [wv evaluateJavaScript:[PDMMediaSniffer pageResourceExtractionJavaScript]
         completionHandler:^(id _Nullable result, NSError * _Nullable __unused error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || ![result isKindOfClass:[NSString class]]) return;
        NSData *d = [(NSString *)result dataUsingEncoding:NSUTF8StringEncoding];
        NSArray *arr = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
        NSMutableArray<PDMPageResource *> *resources = [NSMutableArray array];
        // Include sniffed dynamic media first
        for (PDMDetectedMedia *m in strongSelf.activeTab.detectedMedia) {
            PDMPageResource *r = [[PDMPageResource alloc] init];
            r.urlString = m.urlString;
            r.title = m.filename;
            r.category = [PDMThemeManager categoryForFilename:m.filename mimeType:m.mimeType];
            r.fileExtension = m.filename.pathExtension;
            r.selected = YES;
            [resources addObject:r];
        }
        if ([arr isKindOfClass:[NSArray class]]) {
            for (NSDictionary *entry in arr) {
                if (![entry isKindOfClass:[NSDictionary class]]) continue;
                PDMPageResource *r = [[PDMPageResource alloc] init];
                r.urlString = entry[@"url"] ?: @"";
                r.title = entry[@"title"] ?: @"";
                r.category = entry[@"category"] ?: @"Documents";
                r.fileExtension = entry[@"ext"] ?: @"";
                if (r.urlString.length > 0) [resources addObject:r];
            }
        }
        PDMResourceGrabberSheetViewController *sheet = [[PDMResourceGrabberSheetViewController alloc] init];
        sheet.resources = resources;
        sheet.referer = wv.URL.absoluteString;
        sheet.userAgent = wv.customUserAgent;
        sheet.onBatchDownload = ^(NSArray<PDMPageResource *> *selectedResources) {
            for (PDMPageResource *res in selectedResources) {
                BOOL isHLS = [res.urlString.lowercaseString containsString:@".m3u8"];
                [[PDMDownloadManager sharedManager] enqueueDownloadWithURL:res.urlString
                                                                  filename:res.title
                                                                   referer:wv.URL.absoluteString
                                                                 userAgent:wv.customUserAgent
                                                              cookieHeader:nil
                                                              formatConfig:[PDMMediaFormatConfig defaultConfig]
                                                              qualityLabel:nil
                                                           audioTrackLabel:nil
                                                                     isHLS:isHLS
                                                          hlsAudioTrackURL:nil
                                                          startImmediately:YES];
            }
            [PDMToastBanner showInView:strongSelf.view
                               message:[NSString stringWithFormat:@"Queued %lu item(s) to Download Manager", (unsigned long)selectedResources.count]
                            symbolName:@"arrow.down.circle.fill"];
        };
        [sheet presentFromViewController:strongSelf];
    }];
}

- (void)showFindInPageBar {
    self.findBar.hidden = NO;
    [self.findField becomeFirstResponder];
}

- (void)handleCloseFindBar {
    self.findBar.hidden = YES;
    [self.findField resignFirstResponder];
    [self.activeTab.webView evaluateJavaScript:@"window.getSelection().removeAllRanges();" completionHandler:nil];
}

- (void)runFindInPageBackwards:(BOOL)backwards {
    NSString *term = self.findField.text ?: @"";
    if (term.length == 0) {
        self.findCountLabel.text = @"0/0";
        return;
    }
    NSString *escaped = [[term stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
                         stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
    NSString *js = [NSString stringWithFormat:@"(function(){ var ok = window.find('%@', false, %@, true, false, true, false); var cnt = (document.body.innerText.toLowerCase().split('%@'.toLowerCase()).length - 1); return ok ? ('Found / ' + cnt) : ('0 / ' + cnt); })();",
                    escaped, backwards ? @"true" : @"false", escaped];
    __weak typeof(self) weakSelf = self;
    [self.activeTab.webView evaluateJavaScript:js completionHandler:^(id _Nullable result, NSError * _Nullable __unused error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf && [result isKindOfClass:[NSString class]]) {
            strongSelf.findCountLabel.text = (NSString *)result;
        }
    }];
}

- (void)handleFindTextChanged {
    [self runFindInPageBackwards:NO];
}

- (void)handleFindNext {
    [self runFindInPageBackwards:NO];
}

- (void)handleFindPrev {
    [self runFindInPageBackwards:YES];
}

- (void)saveCurrentPageAsPDF {
    WKWebView *wv = self.activeTab.webView;
    if (!wv) return;
    WKPDFConfiguration *pdfCfg = [[WKPDFConfiguration alloc] init];
    __weak typeof(self) weakSelf = self;
    [wv createPDFWithConfiguration:pdfCfg completionHandler:^(NSData * _Nullable pdfData, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (pdfData.length > 0) {
            NSString *name = [PDMThemeManager sanitizeFilename:(wv.title ?: wv.URL.host ?: @"Webpage") fallbackExtension:@"pdf"];
            NSURL *dest = [[PDMDownloadManager directoryForCategory:@"Documents" isPrivateVault:strongSelf.activeTab.isPrivate]
                           URLByAppendingPathComponent:name];
            [pdfData writeToURL:dest atomically:YES];
            [PDMToastBanner showInView:strongSelf.view
                               message:[NSString stringWithFormat:@"Saved PDF: %@", name]
                            symbolName:@"doc.richtext.fill"];
        } else {
            [PDMToastBanner showInView:strongSelf.view
                               message:(error.localizedDescription ?: @"Could not generate PDF")
                            symbolName:@"exclamationmark.triangle"];
        }
    }];
}

- (void)presentBookmarksSheet {
    NSMutableArray<PDMGlassActionItem *> *actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;

    [actions addObject:[PDMGlassActionItem actionWithTitle:@"Export Bookmarks (JSON)"
                                                  subtitle:@"Share portable JSON backup file"
                                                symbolName:@"square.and.arrow.up"
                                               destructive:NO
                                                   handler:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSData *json = [NSJSONSerialization dataWithJSONObject:strongSelf.bookmarks options:NSJSONWritingPrettyPrinted error:nil];
        NSURL *tmp = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"PrismDM_Bookmarks.json"]];
        [json writeToURL:tmp atomically:YES];
        UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:@[tmp] applicationActivities:nil];
        av.popoverPresentationController.sourceView = strongSelf.view;
        [strongSelf presentViewController:av animated:YES completion:nil];
    }]];

    [actions addObject:[PDMGlassActionItem actionWithTitle:@"Import Bookmarks (JSON)"
                                                  subtitle:@"Load bookmarks from JSON file"
                                                symbolName:@"square.and.arrow.down"
                                               destructive:NO
                                                   handler:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        UIDocumentPickerViewController *dp = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeJSON]];
        dp.delegate = strongSelf;
        [strongSelf presentViewController:dp animated:YES completion:nil];
    }]];

    for (NSDictionary *bm in self.bookmarks) {
        NSString *t = bm[@"title"] ?: @"Bookmark";
        NSString *uStr = bm[@"url"] ?: @"";
        NSString *folder = bm[@"folder"] ?: @"Favorites";
        [actions addObject:[PDMGlassActionItem actionWithTitle:t
                                                      subtitle:[NSString stringWithFormat:@"%@ · %@", folder, uStr]
                                                    symbolName:@"bookmark.fill"
                                                   destructive:NO
                                                       handler:^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            NSURL *u = [NSURL URLWithString:uStr];
            if (strongSelf && u && strongSelf.activeTab) {
                [strongSelf loadURL:u inTab:strongSelf.activeTab];
            }
        }]];
    }

    [PDMGlassActionSheetController presentFrom:self
                                         title:@"Bookmarks"
                                      subtitle:[NSString stringWithFormat:@"%lu saved sites", (unsigned long)self.bookmarks.count]
                                    symbolName:@"books.vertical.fill"
                                       actions:actions];
}

- (void)documentPicker:(UIDocumentPickerViewController *__unused)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *u = urls.firstObject;
    if (!u) return;
    BOOL scoped = [u startAccessingSecurityScopedResource];
    NSData *d = [NSData dataWithContentsOfURL:u];
    if (scoped) [u stopAccessingSecurityScopedResource];
    if (!d) return;
    id parsed = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
    if ([parsed isKindOfClass:[NSArray class]]) {
        NSInteger imported = 0;
        for (id entry in (NSArray *)parsed) {
            if ([entry isKindOfClass:[NSDictionary class]] && entry[@"url"]) {
                [self.bookmarks addObject:entry];
                imported++;
            }
        }
        [self saveBookmarks];
        [PDMToastBanner showInView:self.view message:[NSString stringWithFormat:@"Imported %ld bookmark(s)", (long)imported] symbolName:@"checkmark.circle.fill"];
    }
}

- (void)presentHistorySheet {
    NSMutableArray<PDMGlassActionItem *> *actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;

    if (self.historyEntries.count > 0) {
        [actions addObject:[PDMGlassActionItem actionWithTitle:@"Clear All History"
                                                      subtitle:@"Remove all recorded page visits"
                                                    symbolName:@"trash.fill"
                                                   destructive:YES
                                                       handler:^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf.historyEntries removeAllObjects];
            [strongSelf saveHistory];
            [PDMToastBanner showInView:strongSelf.view message:@"History cleared" symbolName:@"checkmark.circle.fill"];
        }]];
    }

    NSUInteger limit = MIN((NSUInteger)35, self.historyEntries.count);
    for (NSUInteger i = 0; i < limit; i++) {
        NSDictionary *h = self.historyEntries[i];
        NSString *uStr = h[@"url"] ?: @"";
        [actions addObject:[PDMGlassActionItem actionWithTitle:(h[@"title"] ?: uStr)
                                                      subtitle:uStr
                                                    symbolName:@"clock"
                                                   destructive:NO
                                                       handler:^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            NSURL *u = [NSURL URLWithString:uStr];
            if (strongSelf && u && strongSelf.activeTab) {
                [strongSelf loadURL:u inTab:strongSelf.activeTab];
            }
        }]];
    }

    [PDMGlassActionSheetController presentFrom:self
                                         title:@"Browsing History"
                                      subtitle:@"Standard tabs only · Private tabs are never logged"
                                    symbolName:@"clock.arrow.circlepath"
                                       actions:actions];
}

@end
