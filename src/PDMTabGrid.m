// Copyright © 2026 PrismDM. All Rights Reserved. Proprietary and Confidential.

#import "PDMTabGrid.h"

@implementation PDMTabItem

- (instancetype)init {
    self = [super init];
    if (self) {
        _tabID = [NSUUID UUID].UUIDString;
        _title = @"New Tab";
        _isNewTab = YES;
        _detectedMedia = [NSMutableArray array];
    }
    return self;
}

@end

#pragma mark - PDMTabCardCell

@interface PDMTabCardCell : UICollectionViewCell
@property (nonatomic, strong) PDMGlassView *cardGlass;
@property (nonatomic, strong) UIImageView *snapshotView;
@property (nonatomic, strong) UIImageView *placeholderIcon;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *hostLabel;
@property (nonatomic, strong) PDMGlassPillButton *closeBtn;
@property (nonatomic, copy, nullable) dispatch_block_t onCloseTap;
- (void)configureWithTab:(PDMTabItem *)tab isActive:(BOOL)isActive;
@end

@implementation PDMTabCardCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];

        _cardGlass = [[PDMGlassView alloc] initWithCornerRadius:20.0 elevated:NO];
        _cardGlass.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_cardGlass];

        UIView *headerRow = [[UIView alloc] init];
        headerRow.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardGlass.contentView addSubview:headerRow];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [[PDMThemeManager sharedManager] bodyFontOfSize:12.5 weight:UIFontWeightBold];
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [headerRow addSubview:_titleLabel];

        _hostLabel = [[UILabel alloc] init];
        _hostLabel.font = [[PDMThemeManager sharedManager] tabularFontOfSize:10.5 weight:UIFontWeightMedium];
        _hostLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _hostLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [headerRow addSubview:_hostLabel];

        _closeBtn = [[PDMGlassPillButton alloc] initWithTitle:nil symbolName:@"xmark"];
        _closeBtn.borderless = YES;
        _closeBtn.symbolPointSize = 12.5;
        _closeBtn.horizontalPadding = 6.0;
        _closeBtn.verticalPadding = 6.0;
        _closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [_closeBtn addTarget:self action:@selector(handleClose) forControlEvents:UIControlEventTouchUpInside];
        [headerRow addSubview:_closeBtn];

        _snapshotView = [[UIImageView alloc] init];
        _snapshotView.contentMode = UIViewContentModeScaleAspectFill;
        _snapshotView.clipsToBounds = YES;
        _snapshotView.layer.cornerRadius = 10.0;
        _snapshotView.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardGlass.contentView addSubview:_snapshotView];

        _placeholderIcon = [[UIImageView alloc] init];
        _placeholderIcon.contentMode = UIViewContentModeScaleAspectFit;
        _placeholderIcon.translatesAutoresizingMaskIntoConstraints = NO;
        [_snapshotView addSubview:_placeholderIcon];

        [NSLayoutConstraint activateConstraints:@[
            [_cardGlass.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_cardGlass.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_cardGlass.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [_cardGlass.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

            [headerRow.topAnchor constraintEqualToAnchor:_cardGlass.contentView.topAnchor constant:8.0],
            [headerRow.leadingAnchor constraintEqualToAnchor:_cardGlass.contentView.leadingAnchor constant:10.0],
            [headerRow.trailingAnchor constraintEqualToAnchor:_cardGlass.contentView.trailingAnchor constant:-6.0],
            [headerRow.heightAnchor constraintEqualToConstant:30.0],

            [_titleLabel.topAnchor constraintEqualToAnchor:headerRow.topAnchor],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:headerRow.leadingAnchor],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:_closeBtn.leadingAnchor constant:-4.0],

            [_hostLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:1.0],
            [_hostLabel.leadingAnchor constraintEqualToAnchor:headerRow.leadingAnchor],
            [_hostLabel.trailingAnchor constraintEqualToAnchor:_closeBtn.leadingAnchor constant:-4.0],

            [_closeBtn.trailingAnchor constraintEqualToAnchor:headerRow.trailingAnchor],
            [_closeBtn.centerYAnchor constraintEqualToAnchor:headerRow.centerYAnchor],

            [_snapshotView.topAnchor constraintEqualToAnchor:headerRow.bottomAnchor constant:6.0],
            [_snapshotView.leadingAnchor constraintEqualToAnchor:_cardGlass.contentView.leadingAnchor constant:8.0],
            [_snapshotView.trailingAnchor constraintEqualToAnchor:_cardGlass.contentView.trailingAnchor constant:-8.0],
            [_snapshotView.bottomAnchor constraintEqualToAnchor:_cardGlass.contentView.bottomAnchor constant:-8.0],

            [_placeholderIcon.centerXAnchor constraintEqualToAnchor:_snapshotView.centerXAnchor],
            [_placeholderIcon.centerYAnchor constraintEqualToAnchor:_snapshotView.centerYAnchor]
        ]];

        UISwipeGestureRecognizer *swipeLeft = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleClose)];
        swipeLeft.direction = UISwipeGestureRecognizerDirectionLeft;
        [self addGestureRecognizer:swipeLeft];
    }
    return self;
}

- (void)handleClose {
    if (self.onCloseTap) self.onCloseTap();
}

- (void)configureWithTab:(PDMTabItem *)tab isActive:(BOOL)isActive {
    PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;
    self.cardGlass.customBorderColor = isActive ? spec.accentColor : nil;
    self.cardGlass.customTintColor = isActive ? [spec.accentColor colorWithAlphaComponent:0.08] : nil;
    [self.cardGlass applyTheme];

    self.titleLabel.text = tab.title.length > 0 ? tab.title : (tab.isPrivate ? @"Private Tab" : @"New Tab");
    self.titleLabel.textColor = spec.primaryTextColor;

    NSURL *u = tab.urlString.length > 0 ? [NSURL URLWithString:tab.urlString] : nil;
    self.hostLabel.text = u.host ?: (tab.isPrivate ? @"Private" : @"New Tab");
    self.hostLabel.textColor = spec.secondaryTextColor;
    self.closeBtn.customAccentColor = spec.secondaryTextColor;

    if (tab.snapshot) {
        self.snapshotView.image = tab.snapshot;
        self.snapshotView.backgroundColor = [UIColor clearColor];
        self.placeholderIcon.hidden = YES;
    } else {
        self.snapshotView.image = nil;
        self.snapshotView.backgroundColor = spec.canvasColor;
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:26.0 weight:UIImageSymbolWeightLight];
        self.placeholderIcon.image = [UIImage systemImageNamed:(tab.isPrivate ? @"eye.slash" : @"globe") withConfiguration:cfg];
        self.placeholderIcon.tintColor = spec.tertiaryTextColor;
        self.placeholderIcon.hidden = NO;
    }
}

@end

#pragma mark - PDMTabGridViewController

@interface PDMTabGridViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UITextFieldDelegate>
@property (nonatomic, strong) PDMGlassChip *standardChip;
@property (nonatomic, strong) PDMGlassChip *privateChip;
@property (nonatomic, strong) UITextField *searchField;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) PDMGlassPillButton *reopenBtn;
@property (nonatomic, assign) BOOL privateUnlocked;
@property (nonatomic, copy) NSArray<PDMTabItem *> *visibleTabs;
@end

@implementation PDMTabGridViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.visibleTabs = @[];
    self.privateUnlocked = self.showingPrivateSegment || [[PDMBiometricGuard sharedGuard] isUnlockedRecently];

    [self buildUI];
    [self applyTheme];
    [self refreshGrid];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyTheme) name:PDMThemeDidChangeNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)buildUI {
    PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;

    // Top Segmented Switcher + Close
    UIStackView *topRow = [[UIStackView alloc] init];
    topRow.axis = UILayoutConstraintAxisHorizontal;
    topRow.alignment = UIStackViewAlignmentCenter;
    topRow.spacing = 8.0;
    topRow.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:topRow];

    self.standardChip = [[PDMGlassChip alloc] initWithTitle:@"Tabs" subtitle:nil];
    self.standardChip.symbolName = @"square.on.square";
    [self.standardChip addTarget:self action:@selector(handleStandardSegmentTap) forControlEvents:UIControlEventTouchUpInside];
    [topRow addArrangedSubview:self.standardChip];

    self.privateChip = [[PDMGlassChip alloc] initWithTitle:@"Private" subtitle:nil];
    self.privateChip.symbolName = @"lock.shield.fill";
    [self.privateChip addTarget:self action:@selector(handlePrivateSegmentTap) forControlEvents:UIControlEventTouchUpInside];
    [topRow addArrangedSubview:self.privateChip];

    UIView *spacer = [[UIView alloc] init];
    [topRow addArrangedSubview:spacer];

    PDMGlassPillButton *doneBtn = [[PDMGlassPillButton alloc] initWithTitle:@"Done" symbolName:nil];
    doneBtn.prominentAccent = YES;
    [doneBtn addTarget:self action:@selector(handleDoneTap) forControlEvents:UIControlEventTouchUpInside];
    [topRow addArrangedSubview:doneBtn];

    // Live Tab Search
    PDMGlassView *searchGlass = [[PDMGlassView alloc] initWithCornerRadius:18.0 elevated:NO];
    searchGlass.pillShape = YES;
    searchGlass.showAmbientShadow = NO;
    searchGlass.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:searchGlass];

    self.searchField = [[UITextField alloc] init];
    self.searchField.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchField.placeholder = @"Search open tabs...";
    self.searchField.textColor = spec.primaryTextColor;
    self.searchField.tintColor = spec.accentColor;
    self.searchField.font = [[PDMThemeManager sharedManager] bodyFontOfSize:14.0 weight:UIFontWeightMedium];
    self.searchField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.searchField.delegate = self;
    [self.searchField addTarget:self action:@selector(refreshGrid) forControlEvents:UIControlEventEditingChanged];
    [searchGlass.contentView addSubview:self.searchField];
    [NSLayoutConstraint activateConstraints:@[
        [self.searchField.topAnchor constraintEqualToAnchor:searchGlass.contentView.topAnchor constant:9.0],
        [self.searchField.bottomAnchor constraintEqualToAnchor:searchGlass.contentView.bottomAnchor constant:-9.0],
        [self.searchField.leadingAnchor constraintEqualToAnchor:searchGlass.contentView.leadingAnchor constant:16.0],
        [self.searchField.trailingAnchor constraintEqualToAnchor:searchGlass.contentView.trailingAnchor constant:-16.0]
    ]];

    // CollectionView (2-col iPhone / 4-col iPad)
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumLineSpacing = 12.0;
    layout.minimumInteritemSpacing = 12.0;
    layout.sectionInset = UIEdgeInsetsMake(12.0, 14.0, 96.0, 14.0);

    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    self.collectionView.backgroundColor = [UIColor clearColor];
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    [self.collectionView registerClass:[PDMTabCardCell class] forCellWithReuseIdentifier:@"PDMTabCardCell"];
    [self.view addSubview:self.collectionView];

    // Floating Bottom Liquid Glass Toolbar
    PDMGlassView *bottomDock = [[PDMGlassView alloc] initWithCornerRadius:24.0 elevated:YES];
    bottomDock.pillShape = YES;
    bottomDock.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:bottomDock];

    UIStackView *dockRow = [[UIStackView alloc] init];
    dockRow.axis = UILayoutConstraintAxisHorizontal;
    dockRow.alignment = UIStackViewAlignmentCenter;
    dockRow.spacing = 8.0;
    dockRow.distribution = UIStackViewDistributionEqualSpacing;
    dockRow.translatesAutoresizingMaskIntoConstraints = NO;
    [bottomDock.contentView addSubview:dockRow];

    PDMGlassPillButton *closeAllBtn = [[PDMGlassPillButton alloc] initWithTitle:@"Close All" symbolName:@"trash"];
    closeAllBtn.customAccentColor = spec.dangerColor;
    [closeAllBtn addTarget:self action:@selector(handleCloseAllTap) forControlEvents:UIControlEventTouchUpInside];
    [dockRow addArrangedSubview:closeAllBtn];

    self.reopenBtn = [[PDMGlassPillButton alloc] initWithTitle:@"Reopen" symbolName:@"arrow.uturn.backward"];
    self.reopenBtn.enabled = self.canReopenClosedTab;
    self.reopenBtn.alpha = self.canReopenClosedTab ? 1.0 : 0.45;
    [self.reopenBtn addTarget:self action:@selector(handleReopenTap) forControlEvents:UIControlEventTouchUpInside];
    [dockRow addArrangedSubview:self.reopenBtn];

    PDMGlassPillButton *newTabBtn = [[PDMGlassPillButton alloc] initWithTitle:@"New Tab" symbolName:@"plus"];
    newTabBtn.prominentAccent = YES;
    [newTabBtn addTarget:self action:@selector(handleNewTabTap) forControlEvents:UIControlEventTouchUpInside];
    [dockRow addArrangedSubview:newTabBtn];

    [NSLayoutConstraint activateConstraints:@[
        [topRow.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12.0],
        [topRow.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14.0],
        [topRow.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14.0],

        [searchGlass.topAnchor constraintEqualToAnchor:topRow.bottomAnchor constant:12.0],
        [searchGlass.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14.0],
        [searchGlass.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14.0],

        [self.collectionView.topAnchor constraintEqualToAnchor:searchGlass.bottomAnchor constant:6.0],
        [self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [bottomDock.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16.0],
        [bottomDock.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],
        [bottomDock.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10.0],

        [dockRow.topAnchor constraintEqualToAnchor:bottomDock.contentView.topAnchor constant:8.0],
        [dockRow.bottomAnchor constraintEqualToAnchor:bottomDock.contentView.bottomAnchor constant:-8.0],
        [dockRow.leadingAnchor constraintEqualToAnchor:bottomDock.contentView.leadingAnchor constant:10.0],
        [dockRow.trailingAnchor constraintEqualToAnchor:bottomDock.contentView.trailingAnchor constant:-10.0]
    ]];
}

- (void)applyTheme {
    PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;
    self.overrideUserInterfaceStyle = spec.interfaceStyle;
    self.view.backgroundColor = spec.canvasColor;
    self.searchField.textColor = spec.primaryTextColor;
    [self.collectionView reloadData];
}

- (void)refreshGrid {
    self.standardChip.titleText = [NSString stringWithFormat:@"Tabs (%lu)", (unsigned long)self.standardTabs.count];
    self.privateChip.titleText = [NSString stringWithFormat:@"Private (%lu)", (unsigned long)self.privateTabs.count];
    self.standardChip.chipSelected = !self.showingPrivateSegment;
    self.privateChip.chipSelected = self.showingPrivateSegment;

    NSArray<PDMTabItem *> *source = self.showingPrivateSegment ? self.privateTabs : self.standardTabs;
    NSString *q = [self.searchField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
    if (q.length == 0) {
        self.visibleTabs = source ?: @[];
    } else {
        NSMutableArray<PDMTabItem *> *f = [NSMutableArray array];
        for (PDMTabItem *t in source) {
            if ([t.title.lowercaseString containsString:q] || [t.urlString.lowercaseString containsString:q]) {
                [f addObject:t];
            }
        }
        self.visibleTabs = f;
    }
    [self.collectionView reloadData];
}

#pragma mark - Actions

- (void)handleStandardSegmentTap {
    [[PDMThemeManager sharedManager] triggerSelectionHaptic];
    self.showingPrivateSegment = NO;
    [self refreshGrid];
}

- (void)handlePrivateSegmentTap {
    [[PDMThemeManager sharedManager] triggerSelectionHaptic];
    if (self.privateUnlocked) {
        self.showingPrivateSegment = YES;
        [self refreshGrid];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [[PDMBiometricGuard sharedGuard] authenticateWithReason:@"Unlock PrismDM Private Tabs"
                                                 completion:^(BOOL success, NSString * _Nullable errorMessage) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (success) {
            strongSelf.privateUnlocked = YES;
            strongSelf.showingPrivateSegment = YES;
            [strongSelf refreshGrid];
        } else {
            [PDMToastBanner showInView:strongSelf.view message:(errorMessage ?: @"Authentication required") symbolName:@"lock.fill"];
        }
    }];
}

- (void)handleDoneTap {
    [[PDMThemeManager sharedManager] triggerLightImpact];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)handleNewTabTap {
    NSArray<PDMTabItem *> *cur = self.showingPrivateSegment ? self.privateTabs : self.standardTabs;
    if ((NSInteger)cur.count >= kPDMMaxTabCount) {
        [[PDMThemeManager sharedManager] triggerWarningHaptic];
        [PDMToastBanner showInView:self.view message:[NSString stringWithFormat:@"Maximum of %ld tabs reached.", (long)kPDMMaxTabCount] symbolName:@"exclamationmark.circle"];
        return;
    }
    [[PDMThemeManager sharedManager] triggerMediumImpact];
    BOOL isPriv = self.showingPrivateSegment;
    void (^cb)(BOOL) = self.onNewTab;
    [self dismissViewControllerAnimated:YES completion:^{
        if (cb) cb(isPriv);
    }];
}

- (void)handleCloseAllTap {
    [[PDMThemeManager sharedManager] triggerWarningHaptic];
    BOOL isPriv = self.showingPrivateSegment;
    void (^cb)(BOOL) = self.onCloseAllTabs;
    [self dismissViewControllerAnimated:YES completion:^{
        if (cb) cb(isPriv);
    }];
}

- (void)handleReopenTap {
    if (!self.canReopenClosedTab) return;
    [[PDMThemeManager sharedManager] triggerLightImpact];
    dispatch_block_t cb = self.onReopenLastClosed;
    [self dismissViewControllerAnimated:YES completion:^{
        if (cb) cb();
    }];
}

#pragma mark - UICollectionViewDataSource & DelegateFlowLayout

- (NSInteger)collectionView:(UICollectionView *__unused)collectionView numberOfItemsInSection:(NSInteger __unused)section {
    return (NSInteger)self.visibleTabs.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    PDMTabCardCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"PDMTabCardCell" forIndexPath:indexPath];
    PDMTabItem *tab = self.visibleTabs[(NSUInteger)indexPath.item];
    [cell configureWithTab:tab isActive:[tab.tabID isEqualToString:self.activeTabID]];

    __weak typeof(self) weakSelf = self;
    cell.onCloseTap = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [[PDMThemeManager sharedManager] triggerLightImpact];
        if (strongSelf.onCloseTab) {
            strongSelf.onCloseTab(tab);
        }
        NSMutableArray<PDMTabItem *> *m = [strongSelf.visibleTabs mutableCopy];
        [m removeObject:tab];
        strongSelf.visibleTabs = m;
        if (strongSelf.showingPrivateSegment) {
            NSMutableArray<PDMTabItem *> *pm = [strongSelf.privateTabs mutableCopy];
            [pm removeObject:tab];
            strongSelf.privateTabs = pm;
        } else {
            NSMutableArray<PDMTabItem *> *sm = [strongSelf.standardTabs mutableCopy];
            [sm removeObject:tab];
            strongSelf.standardTabs = sm;
        }
        [strongSelf refreshGrid];
    };
    return cell;
}

- (void)collectionView:(UICollectionView *__unused)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    PDMTabItem *tab = self.visibleTabs[(NSUInteger)indexPath.item];
    [[PDMThemeManager sharedManager] triggerLightImpact];
    void (^cb)(PDMTabItem *) = self.onSelectTab;
    [self dismissViewControllerAnimated:YES completion:^{
        if (cb) cb(tab);
    }];
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *__unused)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *__unused)indexPath {
    CGFloat width = CGRectGetWidth(collectionView.bounds);
    BOOL isPad = (self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular && width >= 680.0);
    NSInteger cols = isPad ? 4 : 2;
    CGFloat totalPad = 28.0 + 12.0 * (CGFloat)(cols - 1);
    CGFloat itemW = floor((width - totalPad) / (CGFloat)cols);
    return CGSizeMake(MAX(120.0, itemW), MAX(170.0, itemW * 1.25));
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:^(__unused id<UIViewControllerTransitionCoordinatorContext> ctx) {
        [self.collectionView.collectionViewLayout invalidateLayout];
    } completion:nil];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end
