// Copyright © 2026 PrismDM. All Rights Reserved. Proprietary and Confidential.

#import "PDMUI.h"
#import <LocalAuthentication/LocalAuthentication.h>

#pragma mark - PDMGlassView

@interface PDMGlassView ()
@property (nonatomic, strong) UIView *tintOverlay;
@property (nonatomic, strong) UIView *clippingContainer;
@property (nonatomic, strong, readwrite) UIView *contentView;
@end

@implementation PDMGlassView

- (instancetype)initWithCornerRadius:(CGFloat)radius elevated:(BOOL)elevated {
    self = [self initWithFrame:CGRectZero];
    if (self) {
        _glassCornerRadius = radius;
        _elevated = elevated;
        _showAmbientShadow = elevated;
        [self applyTheme];
        [self setNeedsLayout];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _glassCornerRadius = 16.0;
        _elevated = NO;
        _showAmbientShadow = NO;
        self.backgroundColor = [UIColor clearColor];

        _clippingContainer = [[UIView alloc] init];
        _clippingContainer.translatesAutoresizingMaskIntoConstraints = NO;
        _clippingContainer.clipsToBounds = YES;
        _clippingContainer.layer.cornerCurve = kCACornerCurveContinuous;
        [self addSubview:_clippingContainer];

        _tintOverlay = [[UIView alloc] init];
        _tintOverlay.translatesAutoresizingMaskIntoConstraints = NO;
        _tintOverlay.userInteractionEnabled = NO;
        [_clippingContainer addSubview:_tintOverlay];

        _contentView = [[UIView alloc] init];
        _contentView.translatesAutoresizingMaskIntoConstraints = NO;
        _contentView.backgroundColor = [UIColor clearColor];
        [_clippingContainer addSubview:_contentView];

        [NSLayoutConstraint activateConstraints:@[
            [_clippingContainer.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_clippingContainer.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_clippingContainer.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_clippingContainer.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

            [_tintOverlay.topAnchor constraintEqualToAnchor:_clippingContainer.topAnchor],
            [_tintOverlay.leadingAnchor constraintEqualToAnchor:_clippingContainer.leadingAnchor],
            [_tintOverlay.trailingAnchor constraintEqualToAnchor:_clippingContainer.trailingAnchor],
            [_tintOverlay.bottomAnchor constraintEqualToAnchor:_clippingContainer.bottomAnchor],

            [_contentView.topAnchor constraintEqualToAnchor:_clippingContainer.topAnchor],
            [_contentView.leadingAnchor constraintEqualToAnchor:_clippingContainer.leadingAnchor],
            [_contentView.trailingAnchor constraintEqualToAnchor:_clippingContainer.trailingAnchor],
            [_contentView.bottomAnchor constraintEqualToAnchor:_clippingContainer.bottomAnchor],
        ]];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applyTheme)
                                                     name:PDMThemeDidChangeNotification
                                                   object:nil];
        [self applyTheme];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat radius = self.pillShape ? (CGRectGetHeight(self.bounds) * 0.5) : self.glassCornerRadius;
    self.clippingContainer.layer.cornerRadius = radius;
    self.layer.cornerRadius = radius;

    PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;
    UIColor *border = self.customBorderColor ?: spec.glassSpecularBorderColor;
    self.clippingContainer.layer.borderColor = [border resolvedColorWithTraitCollection:self.traitCollection].CGColor;

    if (self.showAmbientShadow) {
        self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:radius].CGPath;
    } else {
        self.layer.shadowPath = nil;
    }
}

- (void)setGlassCornerRadius:(CGFloat)glassCornerRadius {
    _glassCornerRadius = glassCornerRadius;
    [self setNeedsLayout];
}

- (void)setPillShape:(BOOL)pillShape {
    _pillShape = pillShape;
    [self setNeedsLayout];
}

- (void)setCustomBorderColor:(nullable UIColor *)customBorderColor {
    _customBorderColor = customBorderColor;
    [self applyTheme];
}

- (void)setCustomTintColor:(nullable UIColor *)customTintColor {
    _customTintColor = customTintColor;
    [self applyTheme];
}

- (void)applyTheme {
    PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;
    self.tintOverlay.backgroundColor = self.customTintColor ?: (self.elevated ? spec.glassElevatedTintColor : spec.glassTintColor);
    UIColor *border = self.customBorderColor ?: spec.glassSpecularBorderColor;
    self.clippingContainer.layer.borderWidth = 0.5;
    self.clippingContainer.layer.borderColor = [border resolvedColorWithTraitCollection:self.traitCollection].CGColor;

    if (self.showAmbientShadow) {
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.08f;
        self.layer.shadowOffset = CGSizeMake(0.0, 2.0);
        self.layer.shadowRadius = 8.0;
    } else {
        self.layer.shadowOpacity = 0.0f;
    }
}

@end

#pragma mark - PDMGlassPillButton

@interface PDMGlassPillButton ()
@property (nonatomic, strong) PDMGlassView *glassBackground;
@property (nonatomic, strong) UIStackView *stackView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *badgeLabel;
@property (nonatomic, strong) NSLayoutConstraint *leadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *trailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *topConstraint;
@property (nonatomic, strong) NSLayoutConstraint *bottomConstraint;
@end

@implementation PDMGlassPillButton

- (instancetype)initWithTitle:(nullable NSString *)title symbolName:(nullable NSString *)symbolName {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _titleText = [title copy];
        _symbolName = [symbolName copy];
        _horizontalPadding = 12.0;
        _verticalPadding = 8.0;
        _symbolPointSize = 14.5;

        _glassBackground = [[PDMGlassView alloc] initWithCornerRadius:18.0 elevated:NO];
        _glassBackground.pillShape = YES;
        _glassBackground.showAmbientShadow = NO;
        _glassBackground.userInteractionEnabled = NO;
        _glassBackground.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_glassBackground];

        _stackView = [[UIStackView alloc] init];
        _stackView.axis = UILayoutConstraintAxisHorizontal;
        _stackView.alignment = UIStackViewAlignmentCenter;
        _stackView.spacing = 6.0;
        _stackView.userInteractionEnabled = NO;
        _stackView.translatesAutoresizingMaskIntoConstraints = NO;
        [_glassBackground.contentView addSubview:_stackView];

        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [_iconView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_stackView addArrangedSubview:_iconView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [[PDMThemeManager sharedManager] bodyFontOfSize:13.5 weight:UIFontWeightMedium];
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [_stackView addArrangedSubview:_titleLabel];

        _badgeLabel = [[UILabel alloc] init];
        _badgeLabel.font = [[PDMThemeManager sharedManager] tabularFontOfSize:10.5 weight:UIFontWeightSemibold];
        _badgeLabel.textAlignment = NSTextAlignmentCenter;
        _badgeLabel.clipsToBounds = YES;
        _badgeLabel.layer.cornerRadius = 8.0;
        [_badgeLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_stackView addArrangedSubview:_badgeLabel];

        _leadingConstraint = [_stackView.leadingAnchor constraintEqualToAnchor:_glassBackground.contentView.leadingAnchor constant:_horizontalPadding];
        _trailingConstraint = [_stackView.trailingAnchor constraintEqualToAnchor:_glassBackground.contentView.trailingAnchor constant:-_horizontalPadding];
        _topConstraint = [_stackView.topAnchor constraintEqualToAnchor:_glassBackground.contentView.topAnchor constant:_verticalPadding];
        _bottomConstraint = [_stackView.bottomAnchor constraintEqualToAnchor:_glassBackground.contentView.bottomAnchor constant:-_verticalPadding];

        [NSLayoutConstraint activateConstraints:@[
            [_glassBackground.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_glassBackground.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_glassBackground.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_glassBackground.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            _leadingConstraint,
            _trailingConstraint,
            _topConstraint,
            _bottomConstraint,
            [_badgeLabel.heightAnchor constraintEqualToConstant:16.0],
            [_badgeLabel.widthAnchor constraintGreaterThanOrEqualToConstant:16.0]
        ]];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applyTheme)
                                                     name:PDMThemeDidChangeNotification
                                                   object:nil];
        [self refreshContent];
        [self applyTheme];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setHorizontalPadding:(CGFloat)horizontalPadding {
    _horizontalPadding = horizontalPadding;
    self.leadingConstraint.constant = horizontalPadding;
    self.trailingConstraint.constant = -horizontalPadding;
}

- (void)setVerticalPadding:(CGFloat)verticalPadding {
    _verticalPadding = verticalPadding;
    self.topConstraint.constant = verticalPadding;
    self.bottomConstraint.constant = -verticalPadding;
}

- (void)setTitleText:(nullable NSString *)titleText {
    _titleText = [titleText copy];
    [self refreshContent];
}

- (void)setSymbolName:(nullable NSString *)symbolName {
    _symbolName = [symbolName copy];
    [self refreshContent];
}

- (void)setSymbolPointSize:(CGFloat)symbolPointSize {
    _symbolPointSize = symbolPointSize;
    [self refreshContent];
}

- (void)setBadgeText:(nullable NSString *)badgeText {
    _badgeText = [badgeText copy];
    [self refreshContent];
}

- (void)setProminentAccent:(BOOL)prominentAccent {
    _prominentAccent = prominentAccent;
    [self applyTheme];
}

- (void)setGlowing:(BOOL)glowing {
    _glowing = glowing;
    [self applyTheme];
}

- (void)setBorderless:(BOOL)borderless {
    _borderless = borderless;
    [self applyTheme];
}

- (void)setCustomAccentColor:(nullable UIColor *)customAccentColor {
    _customAccentColor = customAccentColor;
    [self applyTheme];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:0.12 delay:0.0 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        self.transform = highlighted ? CGAffineTransformMakeScale(0.96, 0.96) : CGAffineTransformIdentity;
        self.alpha = highlighted ? 0.65 : 1.0;
    } completion:nil];
}

- (void)refreshContent {
    if (self.symbolName.length > 0) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:self.symbolPointSize weight:UIImageSymbolWeightMedium];
        self.iconView.image = [UIImage systemImageNamed:self.symbolName withConfiguration:cfg];
        self.iconView.hidden = NO;
    } else {
        self.iconView.image = nil;
        self.iconView.hidden = YES;
    }

    self.titleLabel.text = self.titleText;
    self.titleLabel.hidden = (self.titleText.length == 0);

    if (self.badgeText.length > 0) {
        self.badgeLabel.text = [NSString stringWithFormat:@" %@ ", self.badgeText];
        self.badgeLabel.hidden = NO;
    } else {
        self.badgeLabel.text = nil;
        self.badgeLabel.hidden = YES;
    }
}

- (void)applyTheme {
    PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;
    UIColor *accent = self.customAccentColor ?: spec.accentColor;
    self.layer.shadowOpacity = 0.0f;

    if (self.prominentAccent) {
        self.glassBackground.customTintColor = accent;
        self.glassBackground.customBorderColor = [UIColor clearColor];
        UIColor *onAccent = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
            return (tc.userInterfaceStyle == UIUserInterfaceStyleDark)
                ? [UIColor colorWithRed:0.12 green:0.13 blue:0.14 alpha:1.0]
                : [UIColor whiteColor];
        }];
        self.titleLabel.textColor = onAccent;
        self.iconView.tintColor = onAccent;
        self.badgeLabel.backgroundColor = [onAccent colorWithAlphaComponent:0.22];
        self.badgeLabel.textColor = onAccent;
    } else if (self.glowing) {
        UIColor *tone = self.customAccentColor ?: spec.accentColor;
        self.glassBackground.customTintColor = [tone colorWithAlphaComponent:0.14];
        self.glassBackground.customBorderColor = [UIColor clearColor];
        self.titleLabel.textColor = tone;
        self.iconView.tintColor = tone;
        self.badgeLabel.backgroundColor = tone;
        self.badgeLabel.textColor = [UIColor whiteColor];
    } else if (self.borderless) {
        self.glassBackground.customTintColor = [UIColor clearColor];
        self.glassBackground.customBorderColor = [UIColor clearColor];
        self.titleLabel.textColor = spec.primaryTextColor;
        self.iconView.tintColor = self.customAccentColor ?: spec.primaryTextColor;
        self.badgeLabel.backgroundColor = accent;
        self.badgeLabel.textColor = [UIColor whiteColor];
    } else {
        self.glassBackground.customTintColor = nil;
        self.glassBackground.customBorderColor = [UIColor clearColor];
        self.titleLabel.textColor = spec.primaryTextColor;
        self.iconView.tintColor = self.customAccentColor ?: spec.primaryTextColor;
        self.badgeLabel.backgroundColor = accent;
        self.badgeLabel.textColor = [UIColor whiteColor];
    }
    [self.glassBackground applyTheme];
}

@end

#pragma mark - PDMGlassChip

@interface PDMGlassChip ()
@property (nonatomic, strong) PDMGlassView *glassBackground;
@property (nonatomic, strong) UIStackView *outerStack;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UIStackView *textStack;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@end

@implementation PDMGlassChip

- (instancetype)initWithTitle:(NSString *)title subtitle:(nullable NSString *)subtitle {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _titleText = [title copy];
        _subtitleText = [subtitle copy];

        _glassBackground = [[PDMGlassView alloc] initWithCornerRadius:12.0 elevated:NO];
        _glassBackground.showAmbientShadow = NO;
        _glassBackground.userInteractionEnabled = NO;
        _glassBackground.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_glassBackground];

        _outerStack = [[UIStackView alloc] init];
        _outerStack.axis = UILayoutConstraintAxisHorizontal;
        _outerStack.alignment = UIStackViewAlignmentCenter;
        _outerStack.spacing = 6.0;
        _outerStack.userInteractionEnabled = NO;
        _outerStack.translatesAutoresizingMaskIntoConstraints = NO;
        [_glassBackground.contentView addSubview:_outerStack];

        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.hidden = YES;
        [_outerStack addArrangedSubview:_iconView];

        _textStack = [[UIStackView alloc] init];
        _textStack.axis = UILayoutConstraintAxisVertical;
        _textStack.alignment = UIStackViewAlignmentCenter;
        _textStack.spacing = 1.0;
        _textStack.userInteractionEnabled = NO;
        [_outerStack addArrangedSubview:_textStack];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [[PDMThemeManager sharedManager] bodyFontOfSize:13.0 weight:UIFontWeightMedium];
        _titleLabel.text = _titleText;
        [_textStack addArrangedSubview:_titleLabel];

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.font = [[PDMThemeManager sharedManager] tabularFontOfSize:10.5 weight:UIFontWeightRegular];
        _subtitleLabel.text = _subtitleText;
        _subtitleLabel.hidden = (_subtitleText.length == 0);
        [_textStack addArrangedSubview:_subtitleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_glassBackground.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_glassBackground.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_glassBackground.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_glassBackground.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_outerStack.topAnchor constraintEqualToAnchor:_glassBackground.contentView.topAnchor constant:8.0],
            [_outerStack.bottomAnchor constraintEqualToAnchor:_glassBackground.contentView.bottomAnchor constant:-8.0],
            [_outerStack.leadingAnchor constraintEqualToAnchor:_glassBackground.contentView.leadingAnchor constant:12.0],
            [_outerStack.trailingAnchor constraintEqualToAnchor:_glassBackground.contentView.trailingAnchor constant:-12.0]
        ]];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applyTheme)
                                                     name:PDMThemeDidChangeNotification
                                                   object:nil];
        [self applyTheme];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setTitleText:(NSString *)titleText {
    _titleText = [titleText copy];
    self.titleLabel.text = _titleText;
}

- (void)setSubtitleText:(nullable NSString *)subtitleText {
    _subtitleText = [subtitleText copy];
    self.subtitleLabel.text = _subtitleText;
    self.subtitleLabel.hidden = (_subtitleText.length == 0);
}

- (void)setSymbolName:(nullable NSString *)symbolName {
    _symbolName = [symbolName copy];
    if (symbolName.length > 0) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:12.5 weight:UIImageSymbolWeightMedium];
        self.iconView.image = [UIImage systemImageNamed:symbolName withConfiguration:cfg];
        self.iconView.hidden = NO;
    } else {
        self.iconView.hidden = YES;
    }
}

- (void)setChipSelected:(BOOL)chipSelected {
    _chipSelected = chipSelected;
    [self applyTheme];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:0.12 animations:^{
        self.transform = highlighted ? CGAffineTransformMakeScale(0.97, 0.97) : CGAffineTransformIdentity;
    }];
}

- (void)applyTheme {
    PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;
    UIColor *accent = self.customAccentColor ?: spec.accentColor;
    self.layer.shadowOpacity = 0.0f;
    if (self.chipSelected) {
        self.glassBackground.customTintColor = [accent colorWithAlphaComponent:0.14];
        self.glassBackground.customBorderColor = [accent colorWithAlphaComponent:0.65];
        self.titleLabel.textColor = accent;
        self.subtitleLabel.textColor = accent;
        self.iconView.tintColor = accent;
    } else {
        self.glassBackground.customTintColor = nil;
        self.glassBackground.customBorderColor = [UIColor clearColor];
        self.titleLabel.textColor = spec.primaryTextColor;
        self.subtitleLabel.textColor = spec.secondaryTextColor;
        self.iconView.tintColor = spec.secondaryTextColor;
    }
    [self.glassBackground applyTheme];
}

@end

#pragma mark - PDMSegmentProgressView

@interface PDMSegmentProgressView ()
@property (nonatomic, strong) NSMutableArray<UIView *> *cellTracks;
@property (nonatomic, strong) NSMutableArray<UIView *> *cellFills;
@property (nonatomic, strong) UIView *conversionTrack;
@property (nonatomic, strong) CAGradientLayer *conversionGradient;
@end

@implementation PDMSegmentProgressView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _segmentCount = 8;
        _segmentProgress = @[];
        _cellTracks = [NSMutableArray array];
        _cellFills = [NSMutableArray array];

        _conversionTrack = [[UIView alloc] init];
        _conversionTrack.clipsToBounds = YES;
        _conversionTrack.hidden = YES;
        [self addSubview:_conversionTrack];

        _conversionGradient = [CAGradientLayer layer];
        _conversionGradient.startPoint = CGPointMake(0.0, 0.5);
        _conversionGradient.endPoint = CGPointMake(1.0, 0.5);
        [_conversionTrack.layer addSublayer:_conversionGradient];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applyTheme)
                                                     name:PDMThemeDidChangeNotification
                                                   object:nil];
        [self rebuildCells];
        [self applyTheme];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setSegmentCount:(NSInteger)segmentCount {
    NSInteger clamped = MAX(1, MIN(16, segmentCount));
    if (_segmentCount == clamped && (NSInteger)self.cellTracks.count == clamped) {
        return;
    }
    _segmentCount = clamped;
    [self rebuildCells];
    [self applyTheme];
    [self setNeedsLayout];
}

- (void)setSegmentProgress:(NSArray<NSNumber *> *)segmentProgress {
    _segmentProgress = [segmentProgress copy] ?: @[];
    [self setNeedsLayout];
}

- (void)setConvertingMode:(BOOL)convertingMode {
    _convertingMode = convertingMode;
    self.conversionTrack.hidden = !convertingMode;
    for (UIView *track in self.cellTracks) {
        track.hidden = convertingMode;
    }
    [self setNeedsLayout];
}

- (void)setConversionProgress:(double)conversionProgress {
    _conversionProgress = MAX(0.0, MIN(1.0, conversionProgress));
    [self setNeedsLayout];
}

- (void)setPausedState:(BOOL)pausedState {
    _pausedState = pausedState;
    [self applyTheme];
}

- (void)setFailedState:(BOOL)failedState {
    _failedState = failedState;
    [self applyTheme];
}

- (void)rebuildCells {
    for (UIView *v in self.cellTracks) {
        [v removeFromSuperview];
    }
    [self.cellTracks removeAllObjects];
    [self.cellFills removeAllObjects];

    for (NSInteger i = 0; i < self.segmentCount; i++) {
        UIView *track = [[UIView alloc] init];
        track.clipsToBounds = YES;
        track.layer.cornerRadius = 3.5;
        track.hidden = self.convertingMode;

        UIView *fill = [[UIView alloc] init];
        fill.layer.cornerRadius = 3.0;
        [track addSubview:fill];

        [self addSubview:track];
        [self.cellTracks addObject:track];
        [self.cellFills addObject:fill];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = CGRectGetWidth(self.bounds);
    CGFloat h = CGRectGetHeight(self.bounds);
    if (w <= 0.0 || h <= 0.0) {
        return;
    }

    self.conversionTrack.frame = self.bounds;
    self.conversionTrack.layer.cornerRadius = h * 0.5;
    self.conversionGradient.frame = CGRectMake(0.0, 0.0, w * (CGFloat)self.conversionProgress, h);

    NSInteger count = (NSInteger)self.cellTracks.count;
    if (count <= 0) {
        return;
    }
    CGFloat spacing = (count > 8) ? 2.5 : 3.5;
    CGFloat cellW = MAX(2.0, (w - spacing * (CGFloat)(count - 1)) / (CGFloat)count);

    for (NSInteger i = 0; i < count; i++) {
        UIView *track = self.cellTracks[(NSUInteger)i];
        UIView *fill = self.cellFills[(NSUInteger)i];
        CGFloat x = (CGFloat)i * (cellW + spacing);
        track.frame = CGRectMake(x, 0.0, cellW, h);
        track.layer.cornerRadius = MIN(4.0, h * 0.5);

        double frac = 0.0;
        if (i < (NSInteger)self.segmentProgress.count) {
            frac = self.segmentProgress[(NSUInteger)i].doubleValue;
        } else if (self.segmentProgress.count == 1) {
            frac = self.segmentProgress[0].doubleValue;
        }
        frac = MAX(0.0, MIN(1.0, frac));
        fill.frame = CGRectMake(0.0, 0.0, cellW * (CGFloat)frac, h);
    }
}

- (void)applyTheme {
    PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;
    UIColor *trackColor = [spec.primaryTextColor colorWithAlphaComponent:0.12];
    UIColor *fillColor = spec.accentColor;
    if (self.failedState) {
        fillColor = spec.dangerColor;
    } else if (self.pausedState) {
        fillColor = spec.warningColor;
    }

    for (NSUInteger i = 0; i < self.cellTracks.count; i++) {
        self.cellTracks[i].backgroundColor = trackColor;
        self.cellFills[i].backgroundColor = fillColor;
    }

    self.conversionTrack.backgroundColor = trackColor;
    self.conversionGradient.colors = @[(__bridge id)spec.accentColor.CGColor, (__bridge id)spec.secondaryAccentColor.CGColor];
}

@end

#pragma mark - PDMGlassSheetViewController

@interface PDMGlassSheetViewController ()
@property (nonatomic, strong) UIView *headerContainer;
@property (nonatomic, strong) UIImageView *headerIcon;
@property (nonatomic, strong) UILabel *headerTitleLabel;
@property (nonatomic, strong) UILabel *headerSubtitleLabel;
@property (nonatomic, strong) PDMGlassPillButton *closeButton;
@property (nonatomic, strong) UIView *headerSeparator;
@property (nonatomic, strong, readwrite) UIScrollView *scrollView;
@property (nonatomic, strong, readwrite) UIStackView *contentStack;
@property (nonatomic, strong, readwrite) UIView *bottomBarContainer;
@property (nonatomic, strong, readwrite) UIStackView *bottomBarStack;
@property (nonatomic, strong) PDMGlassView *bottomBarGlass;
@property (nonatomic, strong) NSLayoutConstraint *scrollBottomToSafeArea;
@property (nonatomic, strong) NSLayoutConstraint *scrollBottomToBottomBar;
@end

@implementation PDMGlassSheetViewController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _sheetTitle = @"PrismDM";
        _allowsMediumDetent = YES;
        _prefersLargeDefaultDetent = NO;
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)configureSheetPresentation {
    self.modalPresentationStyle = UIModalPresentationPageSheet;
    UISheetPresentationController *sheet = self.sheetPresentationController;
    if (sheet) {
        NSMutableArray<UISheetPresentationControllerDetent *> *detents = [NSMutableArray array];
        if (self.allowsMediumDetent) {
            [detents addObject:[UISheetPresentationControllerDetent mediumDetent]];
        }
        [detents addObject:[UISheetPresentationControllerDetent largeDetent]];
        sheet.detents = detents;
        sheet.selectedDetentIdentifier = self.prefersLargeDefaultDetent
            ? UISheetPresentationControllerDetentIdentifierLarge
            : (self.allowsMediumDetent ? UISheetPresentationControllerDetentIdentifierMedium : UISheetPresentationControllerDetentIdentifierLarge);
        sheet.prefersGrabberVisible = YES;
        sheet.preferredCornerRadius = 24.0;
        sheet.prefersScrollingExpandsWhenScrolledToEdge = YES;
    }
}

- (void)presentFromViewController:(UIViewController *)presenter {
    [self configureSheetPresentation];
    [presenter presentViewController:self animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [PDMThemeManager sharedManager].currentSpec.canvasColor;

    self.headerContainer = [[UIView alloc] init];
    self.headerContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.headerContainer];

    self.headerIcon = [[UIImageView alloc] init];
    self.headerIcon.contentMode = UIViewContentModeScaleAspectFit;
    self.headerIcon.translatesAutoresizingMaskIntoConstraints = NO;
    [self.headerContainer addSubview:self.headerIcon];

    UIStackView *titleStack = [[UIStackView alloc] init];
    titleStack.axis = UILayoutConstraintAxisVertical;
    titleStack.spacing = 2.0;
    titleStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.headerContainer addSubview:titleStack];

    self.headerTitleLabel = [[UILabel alloc] init];
    self.headerTitleLabel.font = [[PDMThemeManager sharedManager] displayFontOfSize:18.5 weight:UIFontWeightSemibold];
    self.headerTitleLabel.numberOfLines = 1;
    [titleStack addArrangedSubview:self.headerTitleLabel];

    self.headerSubtitleLabel = [[UILabel alloc] init];
    self.headerSubtitleLabel.font = [[PDMThemeManager sharedManager] bodyFontOfSize:12.5 weight:UIFontWeightRegular];
    self.headerSubtitleLabel.numberOfLines = 2;
    [titleStack addArrangedSubview:self.headerSubtitleLabel];

    self.closeButton = [[PDMGlassPillButton alloc] initWithTitle:nil symbolName:@"xmark"];
    self.closeButton.symbolPointSize = 13.0;
    self.closeButton.horizontalPadding = 9.0;
    self.closeButton.verticalPadding = 9.0;
    self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.closeButton addTarget:self action:@selector(handleCloseTap) forControlEvents:UIControlEventTouchUpInside];
    [self.headerContainer addSubview:self.closeButton];

    self.headerSeparator = [[UIView alloc] init];
    self.headerSeparator.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.headerSeparator];

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.scrollView];

    self.contentStack = [[UIStackView alloc] init];
    self.contentStack.axis = UILayoutConstraintAxisVertical;
    self.contentStack.spacing = 14.0;
    self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentStack];

    self.bottomBarContainer = [[UIView alloc] init];
    self.bottomBarContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.bottomBarContainer.hidden = YES;
    [self.view addSubview:self.bottomBarContainer];

    self.bottomBarGlass = [[PDMGlassView alloc] initWithCornerRadius:18.0 elevated:YES];
    self.bottomBarGlass.translatesAutoresizingMaskIntoConstraints = NO;
    [self.bottomBarContainer addSubview:self.bottomBarGlass];

    self.bottomBarStack = [[UIStackView alloc] init];
    self.bottomBarStack.axis = UILayoutConstraintAxisHorizontal;
    self.bottomBarStack.spacing = 10.0;
    self.bottomBarStack.distribution = UIStackViewDistributionFillEqually;
    self.bottomBarStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.bottomBarGlass.contentView addSubview:self.bottomBarStack];

    self.scrollBottomToSafeArea = [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor];
    self.scrollBottomToBottomBar = [self.scrollView.bottomAnchor constraintEqualToAnchor:self.bottomBarContainer.topAnchor constant:-6.0];

    [NSLayoutConstraint activateConstraints:@[
        [self.headerContainer.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16.0],
        [self.headerContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:18.0],
        [self.headerContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-18.0],

        [self.headerIcon.leadingAnchor constraintEqualToAnchor:self.headerContainer.leadingAnchor],
        [self.headerIcon.centerYAnchor constraintEqualToAnchor:self.headerContainer.centerYAnchor],
        [self.headerIcon.widthAnchor constraintEqualToConstant:24.0],
        [self.headerIcon.heightAnchor constraintEqualToConstant:24.0],

        [titleStack.leadingAnchor constraintEqualToAnchor:self.headerIcon.trailingAnchor constant:10.0],
        [titleStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.closeButton.leadingAnchor constant:-10.0],
        [titleStack.topAnchor constraintEqualToAnchor:self.headerContainer.topAnchor],
        [titleStack.bottomAnchor constraintEqualToAnchor:self.headerContainer.bottomAnchor],

        [self.closeButton.trailingAnchor constraintEqualToAnchor:self.headerContainer.trailingAnchor],
        [self.closeButton.centerYAnchor constraintEqualToAnchor:self.headerContainer.centerYAnchor],

        [self.headerSeparator.topAnchor constraintEqualToAnchor:self.headerContainer.bottomAnchor constant:12.0],
        [self.headerSeparator.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.headerSeparator.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.headerSeparator.heightAnchor constraintEqualToConstant:0.5],

        [self.scrollView.topAnchor constraintEqualToAnchor:self.headerSeparator.bottomAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        self.scrollBottomToSafeArea,

        [self.contentStack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:14.0],
        [self.contentStack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-24.0],
        [self.contentStack.leadingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.leadingAnchor constant:16.0],
        [self.contentStack.trailingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.trailingAnchor constant:-16.0],

        [self.bottomBarContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14.0],
        [self.bottomBarContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14.0],
        [self.bottomBarContainer.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10.0],

        [self.bottomBarGlass.topAnchor constraintEqualToAnchor:self.bottomBarContainer.topAnchor],
        [self.bottomBarGlass.leadingAnchor constraintEqualToAnchor:self.bottomBarContainer.leadingAnchor],
        [self.bottomBarGlass.trailingAnchor constraintEqualToAnchor:self.bottomBarContainer.trailingAnchor],
        [self.bottomBarGlass.bottomAnchor constraintEqualToAnchor:self.bottomBarContainer.bottomAnchor],

        [self.bottomBarStack.topAnchor constraintEqualToAnchor:self.bottomBarGlass.contentView.topAnchor constant:10.0],
        [self.bottomBarStack.bottomAnchor constraintEqualToAnchor:self.bottomBarGlass.contentView.bottomAnchor constant:-10.0],
        [self.bottomBarStack.leadingAnchor constraintEqualToAnchor:self.bottomBarGlass.contentView.leadingAnchor constant:10.0],
        [self.bottomBarStack.trailingAnchor constraintEqualToAnchor:self.bottomBarGlass.contentView.trailingAnchor constant:-10.0]
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applyTheme)
                                                 name:PDMThemeDidChangeNotification
                                               object:nil];
    [self refreshHeader];
    [self applyTheme];
}

- (void)refreshHeader {
    self.headerTitleLabel.text = self.sheetTitle;
    self.headerSubtitleLabel.text = self.sheetSubtitle;
    self.headerSubtitleLabel.hidden = (self.sheetSubtitle.length == 0);
    if (self.sheetSymbolName.length > 0) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18.0 weight:UIImageSymbolWeightMedium];
        self.headerIcon.image = [UIImage systemImageNamed:self.sheetSymbolName withConfiguration:cfg];
        self.headerIcon.hidden = NO;
    } else {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18.0 weight:UIImageSymbolWeightMedium];
        self.headerIcon.image = [UIImage systemImageNamed:@"slider.horizontal.3" withConfiguration:cfg];
        self.headerIcon.hidden = NO;
    }
}

- (void)showBottomBar:(BOOL)show {
    self.bottomBarContainer.hidden = !show;
    self.scrollBottomToSafeArea.active = !show;
    self.scrollBottomToBottomBar.active = show;
}

- (void)handleCloseTap {
    [[PDMThemeManager sharedManager] triggerLightImpact];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)applyTheme {
    PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;
    self.overrideUserInterfaceStyle = spec.interfaceStyle;
    self.view.backgroundColor = spec.canvasColor;
    self.headerTitleLabel.textColor = spec.primaryTextColor;
    self.headerSubtitleLabel.textColor = spec.secondaryTextColor;
    self.headerIcon.tintColor = self.sheetSymbolTint ?: spec.accentColor;
    self.headerSeparator.backgroundColor = spec.glassSpecularBorderColor;
    [self.closeButton applyTheme];
    [self.bottomBarGlass applyTheme];
}

- (UIView *)sectionHeaderWithTitle:(NSString *)title detail:(nullable NSString *)detail {
    PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;
    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentBottom;

    UILabel *titleLbl = [[UILabel alloc] init];
    titleLbl.text = title.uppercaseString;
    titleLbl.font = [[PDMThemeManager sharedManager] bodyFontOfSize:11.5 weight:UIFontWeightBold];
    titleLbl.textColor = spec.secondaryTextColor;
    [row addArrangedSubview:titleLbl];

    if (detail.length > 0) {
        UILabel *detailLbl = [[UILabel alloc] init];
        detailLbl.text = detail;
        detailLbl.font = [[PDMThemeManager sharedManager] tabularFontOfSize:11.5 weight:UIFontWeightMedium];
        detailLbl.textColor = spec.tertiaryTextColor;
        detailLbl.textAlignment = NSTextAlignmentRight;
        [row addArrangedSubview:detailLbl];
    }
    return row;
}

@end

#pragma mark - PDMGlassActionSheetController

@implementation PDMGlassActionItem

+ (instancetype)actionWithTitle:(NSString *)title
                       subtitle:(nullable NSString *)subtitle
                     symbolName:(nullable NSString *)symbolName
                    destructive:(BOOL)destructive
                        handler:(nullable dispatch_block_t)handler {
    PDMGlassActionItem *item = [[PDMGlassActionItem alloc] init];
    item.title = title;
    item.subtitle = subtitle;
    item.symbolName = symbolName;
    item.destructive = destructive;
    item.handler = handler;
    return item;
}

@end

@interface PDMGlassActionSheetController ()
@property (nonatomic, copy) NSArray<PDMGlassActionItem *> *actionItems;
@property (nonatomic, assign) BOOL textInputMode;
@property (nonatomic, copy, nullable) NSString *inputPlaceholder;
@property (nonatomic, copy, nullable) NSString *inputInitialText;
@property (nonatomic, copy, nullable) NSString *inputConfirmTitle;
@property (nonatomic, copy, nullable) void (^onTextConfirm)(NSString *value);
@property (nonatomic, strong, nullable) UITextField *inputField;
@end

@implementation PDMGlassActionSheetController

+ (void)presentFrom:(UIViewController *)presenter
              title:(NSString *)title
           subtitle:(nullable NSString *)subtitle
         symbolName:(nullable NSString *)symbolName
            actions:(NSArray<PDMGlassActionItem *> *)actions {
    PDMGlassActionSheetController *vc = [[PDMGlassActionSheetController alloc] init];
    vc.sheetTitle = title;
    vc.sheetSubtitle = subtitle;
    vc.sheetSymbolName = symbolName ?: @"ellipsis.circle.fill";
    vc.actionItems = actions;
    vc.allowsMediumDetent = YES;
    vc.prefersLargeDefaultDetent = (actions.count > 6);
    [vc presentFromViewController:presenter];
}

+ (void)presentTextInputFrom:(UIViewController *)presenter
                       title:(NSString *)title
                    subtitle:(nullable NSString *)subtitle
                 placeholder:(nullable NSString *)placeholder
                 initialText:(nullable NSString *)initialText
                confirmTitle:(NSString *)confirmTitle
                  onConfirm:(void (^)(NSString *value))onConfirm {
    PDMGlassActionSheetController *vc = [[PDMGlassActionSheetController alloc] init];
    vc.sheetTitle = title;
    vc.sheetSubtitle = subtitle;
    vc.sheetSymbolName = @"pencil.circle.fill";
    vc.textInputMode = YES;
    vc.inputPlaceholder = placeholder;
    vc.inputInitialText = initialText;
    vc.inputConfirmTitle = confirmTitle;
    vc.onTextConfirm = onConfirm;
    vc.allowsMediumDetent = YES;
    vc.prefersLargeDefaultDetent = NO;
    [vc presentFromViewController:presenter];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;

    if (self.textInputMode) {
        PDMGlassView *fieldCard = [[PDMGlassView alloc] initWithCornerRadius:16.0 elevated:YES];
        fieldCard.showAmbientShadow = NO;
        UITextField *tf = [[UITextField alloc] init];
        tf.translatesAutoresizingMaskIntoConstraints = NO;
        tf.text = self.inputInitialText;
        tf.placeholder = self.inputPlaceholder;
        tf.textColor = spec.primaryTextColor;
        tf.tintColor = spec.accentColor;
        tf.font = [[PDMThemeManager sharedManager] bodyFontOfSize:15.5 weight:UIFontWeightMedium];
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        [fieldCard.contentView addSubview:tf];
        [NSLayoutConstraint activateConstraints:@[
            [tf.topAnchor constraintEqualToAnchor:fieldCard.contentView.topAnchor constant:14.0],
            [tf.bottomAnchor constraintEqualToAnchor:fieldCard.contentView.bottomAnchor constant:-14.0],
            [tf.leadingAnchor constraintEqualToAnchor:fieldCard.contentView.leadingAnchor constant:14.0],
            [tf.trailingAnchor constraintEqualToAnchor:fieldCard.contentView.trailingAnchor constant:-14.0]
        ]];
        self.inputField = tf;
        [self.contentStack addArrangedSubview:fieldCard];

        PDMGlassPillButton *confirmBtn = [[PDMGlassPillButton alloc] initWithTitle:self.inputConfirmTitle ?: @"Confirm" symbolName:@"checkmark.circle.fill"];
        confirmBtn.prominentAccent = YES;
        confirmBtn.verticalPadding = 13.0;
        [confirmBtn addTarget:self action:@selector(handleTextConfirmTap) forControlEvents:UIControlEventTouchUpInside];
        [self.contentStack addArrangedSubview:confirmBtn];
        return;
    }

    for (NSUInteger i = 0; i < self.actionItems.count; i++) {
        PDMGlassActionItem *item = self.actionItems[i];
        PDMGlassView *rowCard = [[PDMGlassView alloc] initWithCornerRadius:16.0 elevated:item.prominent];
        rowCard.showAmbientShadow = NO;
        if (item.destructive) {
            rowCard.customBorderColor = [spec.dangerColor colorWithAlphaComponent:0.45];
            rowCard.customTintColor = [spec.dangerColor colorWithAlphaComponent:0.12];
        } else if (item.prominent) {
            rowCard.customBorderColor = [spec.accentColor colorWithAlphaComponent:0.55];
            rowCard.customTintColor = [spec.accentColor colorWithAlphaComponent:0.16];
        }

        UIControl *tapControl = [[UIControl alloc] init];
        tapControl.tag = (NSInteger)i;
        tapControl.translatesAutoresizingMaskIntoConstraints = NO;
        [tapControl addTarget:self action:@selector(handleActionRowTap:) forControlEvents:UIControlEventTouchUpInside];
        [rowCard.contentView addSubview:tapControl];

        UIStackView *hStack = [[UIStackView alloc] init];
        hStack.axis = UILayoutConstraintAxisHorizontal;
        hStack.alignment = UIStackViewAlignmentCenter;
        hStack.spacing = 12.0;
        hStack.userInteractionEnabled = NO;
        hStack.translatesAutoresizingMaskIntoConstraints = NO;
        [tapControl addSubview:hStack];

        if (item.symbolName.length > 0) {
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:17.0 weight:UIImageSymbolWeightSemibold];
            UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:item.symbolName withConfiguration:cfg]];
            iv.contentMode = UIViewContentModeScaleAspectFit;
            iv.tintColor = item.destructive ? spec.dangerColor : (item.prominent ? spec.accentColor : spec.primaryTextColor);
            [iv.widthAnchor constraintEqualToConstant:24.0].active = YES;
            [hStack addArrangedSubview:iv];
        }

        UIStackView *vStack = [[UIStackView alloc] init];
        vStack.axis = UILayoutConstraintAxisVertical;
        vStack.spacing = 2.0;
        vStack.userInteractionEnabled = NO;
        [hStack addArrangedSubview:vStack];

        UILabel *titleLbl = [[UILabel alloc] init];
        titleLbl.text = item.title;
        titleLbl.font = [[PDMThemeManager sharedManager] bodyFontOfSize:15.0 weight:UIFontWeightSemibold];
        titleLbl.textColor = item.destructive ? spec.dangerColor : spec.primaryTextColor;
        [vStack addArrangedSubview:titleLbl];

        if (item.subtitle.length > 0) {
            UILabel *subLbl = [[UILabel alloc] init];
            subLbl.text = item.subtitle;
            subLbl.font = [[PDMThemeManager sharedManager] bodyFontOfSize:12.0 weight:UIFontWeightRegular];
            subLbl.textColor = spec.secondaryTextColor;
            subLbl.numberOfLines = 2;
            [vStack addArrangedSubview:subLbl];
        }

        UIImageSymbolConfiguration *chevCfg = [UIImageSymbolConfiguration configurationWithPointSize:12.0 weight:UIImageSymbolWeightSemibold];
        UIImageView *chev = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right" withConfiguration:chevCfg]];
        chev.tintColor = spec.tertiaryTextColor;
        [chev setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [hStack addArrangedSubview:chev];

        [NSLayoutConstraint activateConstraints:@[
            [tapControl.topAnchor constraintEqualToAnchor:rowCard.contentView.topAnchor],
            [tapControl.bottomAnchor constraintEqualToAnchor:rowCard.contentView.bottomAnchor],
            [tapControl.leadingAnchor constraintEqualToAnchor:rowCard.contentView.leadingAnchor],
            [tapControl.trailingAnchor constraintEqualToAnchor:rowCard.contentView.trailingAnchor],

            [hStack.topAnchor constraintEqualToAnchor:tapControl.topAnchor constant:13.0],
            [hStack.bottomAnchor constraintEqualToAnchor:tapControl.bottomAnchor constant:-13.0],
            [hStack.leadingAnchor constraintEqualToAnchor:tapControl.leadingAnchor constant:14.0],
            [hStack.trailingAnchor constraintEqualToAnchor:tapControl.trailingAnchor constant:-14.0]
        ]];

        [self.contentStack addArrangedSubview:rowCard];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.textInputMode) {
        [self.inputField becomeFirstResponder];
    }
}

- (void)handleActionRowTap:(UIControl *)sender {
    NSInteger idx = sender.tag;
    if (idx < 0 || idx >= (NSInteger)self.actionItems.count) {
        return;
    }
    [[PDMThemeManager sharedManager] triggerLightImpact];
    dispatch_block_t handler = self.actionItems[(NSUInteger)idx].handler;
    [self dismissViewControllerAnimated:YES completion:^{
        if (handler) {
            handler();
        }
    }];
}

- (void)handleTextConfirmTap {
    NSString *value = self.inputField.text ?: @"";
    void (^cb)(NSString *) = self.onTextConfirm;
    [[PDMThemeManager sharedManager] triggerMediumImpact];
    [self dismissViewControllerAnimated:YES completion:^{
        if (cb) {
            cb(value);
        }
    }];
}

@end

#pragma mark - PDMToastBanner

@implementation PDMToastBanner

+ (void)showInView:(UIView *)hostView message:(NSString *)message symbolName:(nullable NSString *)symbolName {
    [self showInView:hostView message:message symbolName:symbolName accentColor:nil];
}

+ (void)showInView:(UIView *)hostView message:(NSString *)message symbolName:(nullable NSString *)symbolName accentColor:(nullable UIColor *)accentColor {
    if (!hostView || message.length == 0) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;
        PDMGlassView *toast = [[PDMGlassView alloc] initWithCornerRadius:22.0 elevated:YES];
        toast.pillShape = YES;
        toast.customBorderColor = [(accentColor ?: spec.accentColor) colorWithAlphaComponent:0.55];
        toast.translatesAutoresizingMaskIntoConstraints = NO;
        toast.alpha = 0.0;
        toast.transform = CGAffineTransformMakeTranslation(0.0, -18.0);

        UIStackView *stack = [[UIStackView alloc] init];
        stack.axis = UILayoutConstraintAxisHorizontal;
        stack.alignment = UIStackViewAlignmentCenter;
        stack.spacing = 8.0;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [toast.contentView addSubview:stack];

        if (symbolName.length > 0) {
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15.0 weight:UIImageSymbolWeightSemibold];
            UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbolName withConfiguration:cfg]];
            iv.tintColor = accentColor ?: spec.accentColor;
            [stack addArrangedSubview:iv];
        }

        UILabel *lbl = [[UILabel alloc] init];
        lbl.text = message;
        lbl.font = [[PDMThemeManager sharedManager] bodyFontOfSize:13.5 weight:UIFontWeightSemibold];
        lbl.textColor = spec.primaryTextColor;
        lbl.numberOfLines = 2;
        [stack addArrangedSubview:lbl];

        [hostView addSubview:toast];
        [NSLayoutConstraint activateConstraints:@[
            [toast.topAnchor constraintEqualToAnchor:hostView.safeAreaLayoutGuide.topAnchor constant:12.0],
            [toast.centerXAnchor constraintEqualToAnchor:hostView.centerXAnchor],
            [toast.widthAnchor constraintLessThanOrEqualToAnchor:hostView.widthAnchor constant:-32.0],
            [stack.topAnchor constraintEqualToAnchor:toast.contentView.topAnchor constant:10.0],
            [stack.bottomAnchor constraintEqualToAnchor:toast.contentView.bottomAnchor constant:-10.0],
            [stack.leadingAnchor constraintEqualToAnchor:toast.contentView.leadingAnchor constant:16.0],
            [stack.trailingAnchor constraintEqualToAnchor:toast.contentView.trailingAnchor constant:-16.0]
        ]];

        [UIView animateWithDuration:0.28 delay:0.0 usingSpringWithDamping:0.82 initialSpringVelocity:0.6 options:UIViewAnimationOptionCurveEaseOut animations:^{
            toast.alpha = 1.0;
            toast.transform = CGAffineTransformIdentity;
        } completion:^(__unused BOOL finished) {
            [UIView animateWithDuration:0.25 delay:2.1 options:UIViewAnimationOptionCurveEaseIn animations:^{
                toast.alpha = 0.0;
                toast.transform = CGAffineTransformMakeTranslation(0.0, -14.0);
            } completion:^(__unused BOOL done) {
                [toast removeFromSuperview];
            }];
        }];
    });
}

@end

#pragma mark - PDMBiometricGuard

@interface PDMBiometricGuard ()
@property (nonatomic, strong, nullable) NSDate *lastUnlockDate;
@end

@implementation PDMBiometricGuard

+ (instancetype)sharedGuard {
    static PDMBiometricGuard *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[PDMBiometricGuard alloc] init];
    });
    return instance;
}

- (BOOL)isUnlockedRecently {
    if (![PDMThemeManager sharedManager].biometricVaultLockEnabled) {
        return YES;
    }
    if (!self.lastUnlockDate) {
        return NO;
    }
    return ([[NSDate date] timeIntervalSinceDate:self.lastUnlockDate] < 180.0);
}

- (void)invalidateSession {
    self.lastUnlockDate = nil;
}

- (void)authenticateWithReason:(NSString *)reason completion:(void (^)(BOOL success, NSString * _Nullable errorMessage))completion {
    if ([self isUnlockedRecently]) {
        if (completion) {
            completion(YES, nil);
        }
        return;
    }

    LAContext *context = [[LAContext alloc] init];
    context.localizedFallbackTitle = @"Use Passcode";
    NSError *evalError = nil;
    LAPolicy policy = LAPolicyDeviceOwnerAuthentication;

    if ([context canEvaluatePolicy:policy error:&evalError]) {
        __weak typeof(self) weakSelf = self;
        [context evaluatePolicy:policy localizedReason:reason reply:^(BOOL success, NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (success && strongSelf) {
                    strongSelf.lastUnlockDate = [NSDate date];
                }
                if (completion) {
                    completion(success, error.localizedDescription);
                }
            });
        }];
    } else {
        // Simulator or device without passcode configured: allow with graceful notice
        self.lastUnlockDate = [NSDate date];
        if (completion) {
            completion(YES, nil);
        }
    }
}

@end
