// Copyright © 2026 PrismDM. All Rights Reserved. Proprietary and Confidential.

#import "PDMLibrary.h"
#import "PDMDownloadManager.h"
#import "PDMMediaPlayer.h"
#import "PDMMediaSniffer.h"
#import "PDMTranscoder.h"
#import <AVFoundation/AVFoundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <zlib.h>
#import <fcntl.h>
#import <unistd.h>

@implementation PDMLibraryFileEntry
@end

typedef NS_ENUM(NSInteger, PDMLibrarySortMode) {
    PDMLibrarySortDate = 0,
    PDMLibrarySortName = 1,
    PDMLibrarySortSize = 2
};

static uint16_t PDMReadLE16(const uint8_t *p) {
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}

static uint32_t PDMReadLE32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

@interface PDMLibraryViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, copy) NSString *activeCategory;
@property (nonatomic, assign) PDMLibrarySortMode sortMode;
@property (nonatomic, assign) BOOL bulkSelectMode;
@property (nonatomic, assign) BOOL vaultUnlocked;
@property (nonatomic, strong) NSMutableArray<PDMLibraryFileEntry *> *allFiles;
@property (nonatomic, strong) NSArray<PDMLibraryFileEntry *> *visibleFiles;

@property (nonatomic, strong) UITextField *searchField;
@property (nonatomic, strong) UIStackView *categoryStack;
@property (nonatomic, strong) PDMGlassPillButton *sortBtn;
@property (nonatomic, strong) PDMGlassPillButton *selectBtn;
@property (nonatomic, strong) PDMGlassView *bulkBar;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@end

@implementation PDMLibraryViewController

#pragma mark - SHA-256 & Pure-C/zlib ZIP Extraction Utilities

+ (nullable NSString *)sha256HexForFileAtPath:(NSString *)filePath {
    int fd = open(filePath.fileSystemRepresentation, O_RDONLY);
    if (fd < 0) return nil;

    CC_SHA256_CTX ctx;
    CC_SHA256_Init(&ctx);

    uint8_t buf[32768];
    ssize_t n = 0;
    while ((n = read(fd, buf, sizeof(buf))) > 0) {
        CC_SHA256_Update(&ctx, buf, (CC_LONG)n);
    }
    close(fd);

    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &ctx);

    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return hex;
}

+ (BOOL)extractZipAtURL:(NSURL *)zipURL
            toDirectory:(NSURL *)destDir
         extractedCount:(NSInteger * _Nullable)outCount
                  error:(NSError **)outError {
    NSData *zipData = [NSData dataWithContentsOfURL:zipURL options:NSDataReadingMappedIfSafe error:outError];
    if (!zipData || zipData.length < 22) {
        if (outError && !*outError) {
            *outError = [NSError errorWithDomain:@"com.prismdm.zip" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid or empty ZIP archive."}];
        }
        return NO;
    }

    const uint8_t *bytes = (const uint8_t *)zipData.bytes;
    size_t len = zipData.length;

    // Locate End of Central Directory (EOCD) signature 0x06054b50
    size_t searchStart = (len > 65557) ? (len - 65557) : 0;
    ssize_t eocdOffset = -1;
    for (ssize_t pos = (ssize_t)len - 22; pos >= (ssize_t)searchStart; pos--) {
        if (PDMReadLE32(bytes + pos) == 0x06054b50U) {
            eocdOffset = pos;
            break;
        }
    }
    if (eocdOffset < 0) {
        if (outError) *outError = [NSError errorWithDomain:@"com.prismdm.zip" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"ZIP central directory not found."}];
        return NO;
    }

    uint16_t totalEntries = PDMReadLE16(bytes + eocdOffset + 10);
    uint32_t cdOffset = PDMReadLE32(bytes + eocdOffset + 16);
    if ((size_t)cdOffset >= len) {
        if (outError) *outError = [NSError errorWithDomain:@"com.prismdm.zip" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"Corrupt ZIP central directory offset."}];
        return NO;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtURL:destDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *canonicalDest = destDir.URLByStandardizingPath.path;

    size_t cur = (size_t)cdOffset;
    NSInteger extracted = 0;

    for (uint16_t i = 0; i < totalEntries && cur + 46 <= len; i++) {
        if (PDMReadLE32(bytes + cur) != 0x02014b50U) break;
        uint16_t method = PDMReadLE16(bytes + cur + 10);
        uint32_t compSize = PDMReadLE32(bytes + cur + 20);
        uint32_t uncompSize = PDMReadLE32(bytes + cur + 24);
        uint16_t nameLen = PDMReadLE16(bytes + cur + 28);
        uint16_t extraLen = PDMReadLE16(bytes + cur + 30);
        uint16_t commentLen = PDMReadLE16(bytes + cur + 32);
        uint32_t localHeaderOffset = PDMReadLE32(bytes + cur + 42);

        if (cur + 46 + nameLen > len) break;
        NSString *entryName = [[NSString alloc] initWithBytes:(bytes + cur + 46) length:nameLen encoding:NSUTF8StringEncoding];
        cur += 46 + nameLen + extraLen + commentLen;
        if (entryName.length == 0) continue;

        // Zip-Slip path traversal protection
        NSURL *targetURL = [[destDir URLByAppendingPathComponent:entryName] URLByStandardizingPath];
        if (![targetURL.path hasPrefix:canonicalDest]) {
            continue;
        }
        if ([entryName hasSuffix:@"/"]) {
            [fm createDirectoryAtURL:targetURL withIntermediateDirectories:YES attributes:nil error:nil];
            continue;
        }
        [fm createDirectoryAtURL:[targetURL URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];

        if ((size_t)localHeaderOffset + 30 > len) continue;
        if (PDMReadLE32(bytes + localHeaderOffset) != 0x04034b50U) continue;
        uint16_t lhNameLen = PDMReadLE16(bytes + localHeaderOffset + 26);
        uint16_t lhExtraLen = PDMReadLE16(bytes + localHeaderOffset + 28);
        size_t dataOffset = (size_t)localHeaderOffset + 30 + lhNameLen + lhExtraLen;
        if (dataOffset + compSize > len) continue;

        if (method == 0) {
            NSData *raw = [NSData dataWithBytes:(bytes + dataOffset) length:compSize];
            if ([raw writeToURL:targetURL atomically:YES]) extracted++;
        } else if (method == 8) {
            // Raw DEFLATE via zlib inflateInit2(-MAX_WBITS)
            z_stream zs;
            memset(&zs, 0, sizeof(zs));
            zs.next_in = (Bytef *)(bytes + dataOffset);
            zs.avail_in = (uInt)compSize;
            if (inflateInit2(&zs, -MAX_WBITS) == Z_OK) {
                NSMutableData *outData = [NSMutableData dataWithCapacity:MAX((NSUInteger)uncompSize, (NSUInteger)4096)];
                uint8_t chunk[16384];
                int ret = Z_OK;
                while (ret == Z_OK) {
                    zs.next_out = chunk;
                    zs.avail_out = (uInt)sizeof(chunk);
                    ret = inflate(&zs, Z_NO_FLUSH);
                    size_t produced = sizeof(chunk) - zs.avail_out;
                    if (produced > 0) {
                        [outData appendBytes:chunk length:produced];
                    }
                }
                inflateEnd(&zs);
                if (ret == Z_STREAM_END || ret == Z_OK) {
                    if ([outData writeToURL:targetURL atomically:YES]) extracted++;
                }
            }
        }
    }

    if (outCount) *outCount = extracted;
    return YES;
}

#pragma mark - Lifecycle & UI

- (void)viewDidLoad {
    [super viewDidLoad];
    self.activeCategory = @"All";
    self.sortMode = PDMLibrarySortDate;
    self.allFiles = [NSMutableArray array];
    self.visibleFiles = @[];

    [self buildUI];
    [self applyTheme];
    [self scanLibraryFiles];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyTheme) name:PDMThemeDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(scanLibraryFiles) name:PDMDownloadsDidUpdateNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)buildUI {
    PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;

    UIStackView *navRow = [[UIStackView alloc] init];
    navRow.axis = UILayoutConstraintAxisHorizontal;
    navRow.alignment = UIStackViewAlignmentCenter;
    navRow.spacing = 8.0;
    navRow.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:navRow];

    UILabel *titleLbl = [[UILabel alloc] init];
    titleLbl.text = @"Library";
    titleLbl.tag = 9101;
    titleLbl.font = [[PDMThemeManager sharedManager] displayFontOfSize:26.0 weight:UIFontWeightHeavy];
    [navRow addArrangedSubview:titleLbl];

    self.sortBtn = [[PDMGlassPillButton alloc] initWithTitle:@"Date" symbolName:@"arrow.up.arrow.down"];
    [self.sortBtn addTarget:self action:@selector(handleCycleSort) forControlEvents:UIControlEventTouchUpInside];
    [navRow addArrangedSubview:self.sortBtn];

    self.selectBtn = [[PDMGlassPillButton alloc] initWithTitle:@"Select" symbolName:@"checkmark.circle"];
    [self.selectBtn addTarget:self action:@selector(handleToggleBulkSelect) forControlEvents:UIControlEventTouchUpInside];
    [navRow addArrangedSubview:self.selectBtn];

    PDMGlassPillButton *closeBtn = [[PDMGlassPillButton alloc] initWithTitle:nil symbolName:@"xmark"];
    closeBtn.horizontalPadding = 10.0;
    closeBtn.verticalPadding = 10.0;
    [closeBtn addTarget:self action:@selector(handleClose) forControlEvents:UIControlEventTouchUpInside];
    [navRow addArrangedSubview:closeBtn];

    // Search Glass Pill
    PDMGlassView *searchGlass = [[PDMGlassView alloc] initWithCornerRadius:18.0 elevated:NO];
    searchGlass.pillShape = YES;
    searchGlass.showAmbientShadow = NO;
    searchGlass.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:searchGlass];

    self.searchField = [[UITextField alloc] init];
    self.searchField.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchField.placeholder = @"Search offline files...";
    self.searchField.textColor = spec.primaryTextColor;
    self.searchField.tintColor = spec.accentColor;
    self.searchField.font = [[PDMThemeManager sharedManager] bodyFontOfSize:14.5 weight:UIFontWeightMedium];
    self.searchField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.searchField.delegate = self;
    [self.searchField addTarget:self action:@selector(applyFilterAndSort) forControlEvents:UIControlEventEditingChanged];
    [searchGlass.contentView addSubview:self.searchField];
    [NSLayoutConstraint activateConstraints:@[
        [self.searchField.topAnchor constraintEqualToAnchor:searchGlass.contentView.topAnchor constant:10.0],
        [self.searchField.bottomAnchor constraintEqualToAnchor:searchGlass.contentView.bottomAnchor constant:-10.0],
        [self.searchField.leadingAnchor constraintEqualToAnchor:searchGlass.contentView.leadingAnchor constant:16.0],
        [self.searchField.trailingAnchor constraintEqualToAnchor:searchGlass.contentView.trailingAnchor constant:-16.0]
    ]];

    // Category Chips Scroll
    UIScrollView *catScroll = [[UIScrollView alloc] init];
    catScroll.showsHorizontalScrollIndicator = NO;
    catScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:catScroll];

    self.categoryStack = [[UIStackView alloc] init];
    self.categoryStack.axis = UILayoutConstraintAxisHorizontal;
    self.categoryStack.spacing = 8.0;
    self.categoryStack.translatesAutoresizingMaskIntoConstraints = NO;
    [catScroll addSubview:self.categoryStack];
    [NSLayoutConstraint activateConstraints:@[
        [self.categoryStack.topAnchor constraintEqualToAnchor:catScroll.contentLayoutGuide.topAnchor],
        [self.categoryStack.bottomAnchor constraintEqualToAnchor:catScroll.contentLayoutGuide.bottomAnchor],
        [self.categoryStack.leadingAnchor constraintEqualToAnchor:catScroll.contentLayoutGuide.leadingAnchor constant:14.0],
        [self.categoryStack.trailingAnchor constraintEqualToAnchor:catScroll.contentLayoutGuide.trailingAnchor constant:-14.0],
        [self.categoryStack.heightAnchor constraintEqualToAnchor:catScroll.frameLayoutGuide.heightAnchor]
    ]];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 76.0;
    [self.view addSubview:self.tableView];

    self.emptyLabel = [[UILabel alloc] init];
    self.emptyLabel.text = @"No files in this category yet.";
    self.emptyLabel.font = [[PDMThemeManager sharedManager] bodyFontOfSize:14.5 weight:UIFontWeightMedium];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.emptyLabel];

    // Bulk Action Bar
    self.bulkBar = [[PDMGlassView alloc] initWithCornerRadius:22.0 elevated:YES];
    self.bulkBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.bulkBar.hidden = YES;
    [self.view addSubview:self.bulkBar];

    UIStackView *bulkRow = [[UIStackView alloc] init];
    bulkRow.axis = UILayoutConstraintAxisHorizontal;
    bulkRow.spacing = 8.0;
    bulkRow.distribution = UIStackViewDistributionFillEqually;
    bulkRow.translatesAutoresizingMaskIntoConstraints = NO;
    [self.bulkBar.contentView addSubview:bulkRow];

    PDMGlassPillButton *bulkVault = [[PDMGlassPillButton alloc] initWithTitle:@"Vault" symbolName:@"lock.shield.fill"];
    [bulkVault addTarget:self action:@selector(handleBulkMoveToVault) forControlEvents:UIControlEventTouchUpInside];
    [bulkRow addArrangedSubview:bulkVault];

    PDMGlassPillButton *bulkShare = [[PDMGlassPillButton alloc] initWithTitle:@"Share" symbolName:@"square.and.arrow.up"];
    [bulkShare addTarget:self action:@selector(handleBulkShare) forControlEvents:UIControlEventTouchUpInside];
    [bulkRow addArrangedSubview:bulkShare];

    PDMGlassPillButton *bulkDel = [[PDMGlassPillButton alloc] initWithTitle:@"Delete" symbolName:@"trash.fill"];
    bulkDel.customAccentColor = spec.dangerColor;
    bulkDel.glowing = YES;
    [bulkDel addTarget:self action:@selector(handleBulkDelete) forControlEvents:UIControlEventTouchUpInside];
    [bulkRow addArrangedSubview:bulkDel];

    [NSLayoutConstraint activateConstraints:@[
        [navRow.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12.0],
        [navRow.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16.0],
        [navRow.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],

        [searchGlass.topAnchor constraintEqualToAnchor:navRow.bottomAnchor constant:12.0],
        [searchGlass.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14.0],
        [searchGlass.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14.0],

        [catScroll.topAnchor constraintEqualToAnchor:searchGlass.bottomAnchor constant:12.0],
        [catScroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [catScroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [catScroll.heightAnchor constraintEqualToConstant:40.0],

        [self.tableView.topAnchor constraintEqualToAnchor:catScroll.bottomAnchor constant:8.0],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor constant:-20.0],

        [self.bulkBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14.0],
        [self.bulkBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14.0],
        [self.bulkBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10.0],
        [bulkRow.topAnchor constraintEqualToAnchor:self.bulkBar.contentView.topAnchor constant:10.0],
        [bulkRow.bottomAnchor constraintEqualToAnchor:self.bulkBar.contentView.bottomAnchor constant:-10.0],
        [bulkRow.leadingAnchor constraintEqualToAnchor:self.bulkBar.contentView.leadingAnchor constant:10.0],
        [bulkRow.trailingAnchor constraintEqualToAnchor:self.bulkBar.contentView.trailingAnchor constant:-10.0]
    ]];

    [self rebuildCategoryChips];
}

- (void)applyTheme {
    PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;
    self.overrideUserInterfaceStyle = spec.interfaceStyle;
    self.view.backgroundColor = spec.canvasColor;
    UILabel *t = (UILabel *)[self.view viewWithTag:9101];
    if ([t isKindOfClass:[UILabel class]]) t.textColor = spec.primaryTextColor;
    self.searchField.textColor = spec.primaryTextColor;
    self.emptyLabel.textColor = spec.secondaryTextColor;
    [self.tableView reloadData];
}

- (void)rebuildCategoryChips {
    for (UIView *v in [self.categoryStack.arrangedSubviews copy]) {
        [self.categoryStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    NSArray<NSString *> *cats = @[@"All", @"Videos", @"Audio", @"Documents", @"Archives", @"Images", @"Private Vault"];
    for (NSUInteger i = 0; i < cats.count; i++) {
        PDMGlassChip *c = [[PDMGlassChip alloc] initWithTitle:cats[i] subtitle:nil];
        if ([cats[i] isEqualToString:@"Private Vault"]) {
            c.symbolName = @"lock.shield.fill";
        }
        c.tag = (NSInteger)i;
        c.chipSelected = [self.activeCategory isEqualToString:cats[i]];
        [c addTarget:self action:@selector(handleCategoryTap:) forControlEvents:UIControlEventTouchUpInside];
        [self.categoryStack addArrangedSubview:c];
    }
}

- (void)scanLibraryFiles {
    [self.allFiles removeAllObjects];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *folders = @[@"Videos", @"Audio", @"Documents", @"Archives", @"Images", @".PrivateVault"];
    NSURL *base = [PDMDownloadManager downloadsBaseDirectory];

    for (NSString *folder in folders) {
        BOOL isVault = [folder isEqualToString:@".PrivateVault"];
        NSURL *dir = [base URLByAppendingPathComponent:folder isDirectory:YES];
        NSArray<NSURL *> *contents = [fm contentsOfDirectoryAtURL:dir
                                       includingPropertiesForKeys:@[NSURLFileSizeKey, NSURLContentModificationDateKey, NSURLIsDirectoryKey]
                                                          options:NSDirectoryEnumerationSkipsHiddenFiles
                                                            error:nil];
        for (NSURL *u in contents) {
            NSNumber *isDir = nil;
            [u getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
            if (isDir.boolValue) continue;
            NSNumber *sizeNum = nil;
            NSDate *modDate = nil;
            [u getResourceValue:&sizeNum forKey:NSURLFileSizeKey error:nil];
            [u getResourceValue:&modDate forKey:NSURLContentModificationDateKey error:nil];

            PDMLibraryFileEntry *e = [[PDMLibraryFileEntry alloc] init];
            e.filename = u.lastPathComponent;
            e.fileURL = u;
            e.isPrivateVault = isVault;
            e.category = isVault ? @"Private Vault" : folder;
            e.fileSize = sizeNum.longLongValue;
            e.modifiedDate = modDate ?: [NSDate date];
            [self.allFiles addObject:e];
        }
    }
    [self applyFilterAndSort];
}

- (void)applyFilterAndSort {
    NSString *query = [self.searchField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
    NSMutableArray<PDMLibraryFileEntry *> *list = [NSMutableArray array];
    for (PDMLibraryFileEntry *e in self.allFiles) {
        if ([self.activeCategory isEqualToString:@"Private Vault"]) {
            if (!e.isPrivateVault || !self.vaultUnlocked) continue;
        } else {
            if (e.isPrivateVault) continue; // Keep Private Vault strictly isolated
            if (![self.activeCategory isEqualToString:@"All"] && ![e.category isEqualToString:self.activeCategory]) {
                continue;
            }
        }
        if (query.length > 0 && ![e.filename.lowercaseString containsString:query]) {
            continue;
        }
        [list addObject:e];
    }

    [list sortUsingComparator:^NSComparisonResult(PDMLibraryFileEntry *a, PDMLibraryFileEntry *b) {
        switch (self.sortMode) {
            case PDMLibrarySortName:
                return [a.filename localizedCaseInsensitiveCompare:b.filename];
            case PDMLibrarySortSize:
                if (a.fileSize != b.fileSize) return (a.fileSize > b.fileSize) ? NSOrderedAscending : NSOrderedDescending;
                return NSOrderedSame;
            case PDMLibrarySortDate:
            default:
                return [b.modifiedDate compare:a.modifiedDate];
        }
    }];

    self.visibleFiles = list;
    self.emptyLabel.hidden = (list.count > 0);
    [self.tableView reloadData];
}

#pragma mark - Actions

- (void)handleClose {
    [[PDMThemeManager sharedManager] triggerLightImpact];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)handleCategoryTap:(PDMGlassChip *)sender {
    NSArray<NSString *> *cats = @[@"All", @"Videos", @"Audio", @"Documents", @"Archives", @"Images", @"Private Vault"];
    if (sender.tag < 0 || sender.tag >= (NSInteger)cats.count) return;
    NSString *chosen = cats[(NSUInteger)sender.tag];
    [[PDMThemeManager sharedManager] triggerSelectionHaptic];

    if ([chosen isEqualToString:@"Private Vault"] && !self.vaultUnlocked) {
        __weak typeof(self) weakSelf = self;
        [[PDMBiometricGuard sharedGuard] authenticateWithReason:@"Unlock PrismDM Private Downloads Vault"
                                                     completion:^(BOOL success, NSString * _Nullable errorMessage) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (success) {
                strongSelf.vaultUnlocked = YES;
                strongSelf.activeCategory = @"Private Vault";
                [strongSelf rebuildCategoryChips];
                [strongSelf applyFilterAndSort];
            } else {
                [PDMToastBanner showInView:strongSelf.view message:(errorMessage ?: @"Authentication required") symbolName:@"lock.fill"];
            }
        }];
        return;
    }

    self.activeCategory = chosen;
    [self rebuildCategoryChips];
    [self applyFilterAndSort];
}

- (void)handleCycleSort {
    [[PDMThemeManager sharedManager] triggerSelectionHaptic];
    self.sortMode = (PDMLibrarySortMode)((self.sortMode + 1) % 3);
    switch (self.sortMode) {
        case PDMLibrarySortDate: self.sortBtn.titleText = @"Date"; break;
        case PDMLibrarySortName: self.sortBtn.titleText = @"Name"; break;
        case PDMLibrarySortSize: self.sortBtn.titleText = @"Size"; break;
    }
    [self applyFilterAndSort];
}

- (void)handleToggleBulkSelect {
    [[PDMThemeManager sharedManager] triggerLightImpact];
    self.bulkSelectMode = !self.bulkSelectMode;
    self.selectBtn.glowing = self.bulkSelectMode;
    self.bulkBar.hidden = !self.bulkSelectMode;
    if (!self.bulkSelectMode) {
        for (PDMLibraryFileEntry *e in self.allFiles) e.selected = NO;
    }
    [self.tableView reloadData];
}

- (NSArray<PDMLibraryFileEntry *> *)selectedEntries {
    NSMutableArray<PDMLibraryFileEntry *> *arr = [NSMutableArray array];
    for (PDMLibraryFileEntry *e in self.visibleFiles) {
        if (e.selected) [arr addObject:e];
    }
    return arr;
}

- (void)handleBulkMoveToVault {
    NSArray<PDMLibraryFileEntry *> *sel = [self selectedEntries];
    if (sel.count == 0) return;
    for (PDMLibraryFileEntry *e in sel) {
        [self moveEntry:e toVault:!e.isPrivateVault];
    }
    [self handleToggleBulkSelect];
    [self scanLibraryFiles];
    [PDMToastBanner showInView:self.view message:[NSString stringWithFormat:@"Moved %lu file(s)", (unsigned long)sel.count] symbolName:@"lock.shield.fill"];
}

- (void)handleBulkShare {
    NSArray<PDMLibraryFileEntry *> *sel = [self selectedEntries];
    if (sel.count == 0) return;
    NSMutableArray<NSURL *> *urls = [NSMutableArray arrayWithCapacity:sel.count];
    for (PDMLibraryFileEntry *e in sel) [urls addObject:e.fileURL];
    UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:urls applicationActivities:nil];
    vc.popoverPresentationController.sourceView = self.view;
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)handleBulkDelete {
    NSArray<PDMLibraryFileEntry *> *sel = [self selectedEntries];
    if (sel.count == 0) return;
    for (PDMLibraryFileEntry *e in sel) {
        [[NSFileManager defaultManager] removeItemAtURL:e.fileURL error:nil];
    }
    [self handleToggleBulkSelect];
    [self scanLibraryFiles];
    [PDMToastBanner showInView:self.view message:[NSString stringWithFormat:@"Deleted %lu file(s)", (unsigned long)sel.count] symbolName:@"trash.fill"];
}

- (void)moveEntry:(PDMLibraryFileEntry *)entry toVault:(BOOL)toVault {
    NSString *targetCat = toVault ? @"Private Vault" : [PDMThemeManager categoryForFilename:entry.filename mimeType:nil];
    NSURL *destDir = [PDMDownloadManager directoryForCategory:targetCat isPrivateVault:toVault];
    NSURL *destURL = [destDir URLByAppendingPathComponent:entry.filename];
    [[NSFileManager defaultManager] removeItemAtURL:destURL error:nil];
    [[NSFileManager defaultManager] moveItemAtURL:entry.fileURL toURL:destURL error:nil];
}

#pragma mark - File Tools Sheet

- (void)openStudioForEntry:(PDMLibraryFileEntry *)entry audioOnlyDefault:(BOOL)audioOnly {
    PDMDetectedMedia *m = [[PDMDetectedMedia alloc] init];
    m.urlString = entry.fileURL.absoluteString;
    m.title = entry.filename;
    m.filename = entry.filename;
    m.sourceBadge = entry.fileURL.pathExtension.uppercaseString;
    m.contentLength = entry.fileSize;
    m.isInspected = YES;

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:entry.fileURL options:nil];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSArray<AVAssetTrack *> *aTracks = [asset tracksWithMediaType:AVMediaTypeAudio];
#pragma clang diagnostic pop
    for (NSUInteger i = 0; i < aTracks.count; i++) {
        AVAssetTrack *t = aTracks[i];
        PDMMediaAudioTrack *mt = [[PDMMediaAudioTrack alloc] init];
        mt.trackID = [NSString stringWithFormat:@"lib_%lu", (unsigned long)i];
        mt.trackIndex = (NSInteger)i;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSString *lang = t.extendedLanguageTag ?: t.languageCode;
#pragma clang diagnostic pop
        mt.language = lang ?: @"und";
        mt.name = lang.length > 0 ? ([[NSLocale currentLocale] localizedStringForLanguageCode:lang].capitalizedString ?: lang) : [NSString stringWithFormat:@"Audio Track %lu", (unsigned long)(i + 1)];
        mt.channels = @"2";
        mt.isDefault = (i == 0);
        [m.audioTracks addObject:mt];
    }
    if (m.audioTracks.count == 0) {
        PDMMediaAudioTrack *def = [[PDMMediaAudioTrack alloc] init];
        def.trackID = @"def";
        def.name = @"Default Audio";
        def.language = @"und";
        def.channels = @"2";
        def.isDefault = YES;
        [m.audioTracks addObject:def];
    }

    PDMMediaPickerSheetViewController *studio = [[PDMMediaPickerSheetViewController alloc] init];
    studio.media = m;
    studio.studioOnlyMode = YES;
    studio.localFilePathForStudio = entry.fileURL.path;
    __weak typeof(self) weakSelf = self;
    studio.onDownloadRequested = ^(PDMDetectedMedia *__unused dm,
                                   PDMMediaVideoVariant *__unused v,
                                   PDMMediaAudioTrack *__unused a,
                                   PDMMediaFormatConfig *cfg,
                                   NSString *finalName,
                                   BOOL __unused startNow) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (audioOnly && cfg.outputMode != PDMOutputModeAudioOnly) {
            cfg.outputMode = PDMOutputModeAudioOnly;
        }
        [[PDMDownloadManager sharedManager] enqueueLocalConversionForFileURL:entry.fileURL
                                                                      config:cfg
                                                              outputFilename:finalName
                                                              isPrivateVault:entry.isPrivateVault];
        [PDMToastBanner showInView:strongSelf.view
                           message:[NSString stringWithFormat:@"Converting %@ in Downloads...", finalName]
                        symbolName:@"wand.and.stars"];
    };
    [studio presentFromViewController:self];
}

- (void)presentFileToolsForEntry:(PDMLibraryFileEntry *)entry {
    NSString *ext = entry.fileURL.pathExtension.lowercaseString;
    BOOL isVideo = [entry.category isEqualToString:@"Videos"] || [@[@"mp4", @"m4v", @"mov", @"mkv", @"webm", @"ts"] containsObject:ext];
    BOOL isAudio = [entry.category isEqualToString:@"Audio"] || [@[@"mp3", @"m4a", @"aac", @"flac", @"wav", @"ogg"] containsObject:ext];
    BOOL isZip = [ext isEqualToString:@"zip"];

    NSMutableArray<PDMGlassActionItem *> *actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;

    if (isVideo || isAudio) {
        PDMGlassActionItem *playAct = [PDMGlassActionItem actionWithTitle:@"Play in Pro Player"
                                                                 subtitle:@"Multi-Audio, PiP, Background Audio & AirPlay"
                                                               symbolName:@"play.circle.fill"
                                                              destructive:NO
                                                                  handler:^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            PDMMediaPlayerViewController *player = [[PDMMediaPlayerViewController alloc] initWithURL:entry.fileURL title:entry.filename httpHeaders:nil];
            player.onRequestConvertLocalFile = ^(NSURL *localURL, PDMMediaFormatConfig *cfg, NSString *outName) {
                [[PDMDownloadManager sharedManager] enqueueLocalConversionForFileURL:localURL config:cfg outputFilename:outName isPrivateVault:entry.isPrivateVault];
            };
            [strongSelf presentViewController:player animated:YES completion:nil];
        }];
        playAct.prominent = YES;
        [actions addObject:playAct];

        [actions addObject:[PDMGlassActionItem actionWithTitle:@"Convert Format / Codec / Resolution"
                                                      subtitle:@"MP4 H.264/HEVC · MOV · M4V · 1080p/720p/480p"
                                                    symbolName:@"wand.and.stars"
                                                   destructive:NO
                                                       handler:^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) [strongSelf openStudioForEntry:entry audioOnlyDefault:NO];
        }]];

        [actions addObject:[PDMGlassActionItem actionWithTitle:@"Extract Audio Track"
                                                      subtitle:@"MP3 · M4A (AAC/ALAC) · FLAC · WAV (Pick Track)"
                                                    symbolName:@"waveform.circle.fill"
                                                   destructive:NO
                                                       handler:^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) [strongSelf openStudioForEntry:entry audioOnlyDefault:YES];
        }]];
    }

    if (isVideo) {
        [actions addObject:[PDMGlassActionItem actionWithTitle:@"Quick Compress Video (720p HEVC)"
                                                      subtitle:@"Shrinks file size while preserving visual clarity"
                                                    symbolName:@"arrow.down.right.and.arrow.up.left"
                                                   destructive:NO
                                                       handler:^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            PDMMediaFormatConfig *cfg = [PDMMediaFormatConfig defaultConfig];
            cfg.outputMode = PDMOutputModeVideo;
            cfg.videoFormat = PDMVideoFormatMP4HEVC;
            cfg.targetResolution = PDMTargetResolution720p;
            cfg.qualityPreset = PDMVideoQualityPresetCompact;
            NSString *outName = [[entry.filename stringByDeletingPathExtension] stringByAppendingString:@"_720p.mp4"];
            [[PDMDownloadManager sharedManager] enqueueLocalConversionForFileURL:entry.fileURL config:cfg outputFilename:outName isPrivateVault:entry.isPrivateVault];
            [PDMToastBanner showInView:strongSelf.view message:@"Compressing video in Downloads..." symbolName:@"wand.and.stars"];
        }]];
    }

    if (isZip) {
        [actions addObject:[PDMGlassActionItem actionWithTitle:@"Extract .zip Archive"
                                                      subtitle:@"Unpacks into Documents folder with path safety"
                                                    symbolName:@"archivebox.fill"
                                                   destructive:NO
                                                       handler:^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            NSURL *dest = [[PDMDownloadManager directoryForCategory:@"Documents" isPrivateVault:entry.isPrivateVault]
                           URLByAppendingPathComponent:[entry.filename stringByDeletingPathExtension]
                           isDirectory:YES];
            NSInteger count = 0;
            NSError *err = nil;
            BOOL ok = [PDMLibraryViewController extractZipAtURL:entry.fileURL toDirectory:dest extractedCount:&count error:&err];
            [strongSelf scanLibraryFiles];
            [PDMToastBanner showInView:strongSelf.view
                               message:(ok ? [NSString stringWithFormat:@"Extracted %ld file(s)", (long)count] : (err.localizedDescription ?: @"Extract failed"))
                            symbolName:(ok ? @"checkmark.circle.fill" : @"exclamationmark.triangle.fill")];
        }]];
    }

    [actions addObject:[PDMGlassActionItem actionWithTitle:@"Verify SHA-256 Checksum"
                                                  subtitle:@"Compute cryptographic integrity digest"
                                                symbolName:@"checkmark.shield.fill"
                                               destructive:NO
                                                   handler:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSString *hash = [PDMLibraryViewController sha256HexForFileAtPath:entry.fileURL.path] ?: @"Error computing digest";
            dispatch_async(dispatch_get_main_queue(), ^{
                PDMGlassActionItem *copyAct = [PDMGlassActionItem actionWithTitle:@"Copy SHA-256 Digest"
                                                                         subtitle:hash
                                                                       symbolName:@"doc.on.doc"
                                                                      destructive:NO
                                                                          handler:^{
                    [UIPasteboard generalPasteboard].string = hash;
                    [PDMToastBanner showInView:strongSelf.view message:@"SHA-256 copied to clipboard" symbolName:@"checkmark.circle.fill"];
                }];
                copyAct.prominent = YES;
                [PDMGlassActionSheetController presentFrom:strongSelf
                                                     title:@"SHA-256 Verification"
                                                  subtitle:entry.filename
                                                symbolName:@"checkmark.shield.fill"
                                                   actions:@[copyAct]];
            });
        });
    }]];

    [actions addObject:[PDMGlassActionItem actionWithTitle:(entry.isPrivateVault ? @"Remove from Private Vault" : @"Move to Face ID Private Vault")
                                                  subtitle:(entry.isPrivateVault ? @"Restore to standard Library" : @"Protect with Face ID / Touch ID")
                                                symbolName:@"lock.shield.fill"
                                               destructive:NO
                                                   handler:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf moveEntry:entry toVault:!entry.isPrivateVault];
        [strongSelf scanLibraryFiles];
        [PDMToastBanner showInView:strongSelf.view
                           message:(entry.isPrivateVault ? @"Moved out of Private Vault" : @"Secured in Private Vault")
                        symbolName:@"lock.shield.fill"];
    }]];

    [actions addObject:[PDMGlassActionItem actionWithTitle:@"Rename File"
                                                  subtitle:entry.filename
                                                symbolName:@"pencil"
                                               destructive:NO
                                                   handler:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [PDMGlassActionSheetController presentTextInputFrom:strongSelf
                                                      title:@"Rename File"
                                                   subtitle:@"Enter a new filename"
                                                placeholder:entry.filename
                                                initialText:entry.filename
                                               confirmTitle:@"Rename"
                                                  onConfirm:^(NSString *value) {
            NSString *clean = [PDMThemeManager sanitizeFilename:value fallbackExtension:entry.fileURL.pathExtension];
            NSURL *newURL = [[entry.fileURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:clean];
            [[NSFileManager defaultManager] moveItemAtURL:entry.fileURL toURL:newURL error:nil];
            [strongSelf scanLibraryFiles];
        }];
    }]];

    [actions addObject:[PDMGlassActionItem actionWithTitle:@"Share / Export"
                                                  subtitle:@"AirDrop, Files, Save to Photos or Apps"
                                                symbolName:@"square.and.arrow.up"
                                               destructive:NO
                                                   handler:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:@[entry.fileURL] applicationActivities:nil];
        av.popoverPresentationController.sourceView = strongSelf.view;
        [strongSelf presentViewController:av animated:YES completion:nil];
    }]];

    [actions addObject:[PDMGlassActionItem actionWithTitle:@"Delete File"
                                                  subtitle:@"Permanently remove from device storage"
                                                symbolName:@"trash.fill"
                                               destructive:YES
                                                   handler:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [[NSFileManager defaultManager] removeItemAtURL:entry.fileURL error:nil];
        [strongSelf scanLibraryFiles];
    }]];

    [PDMGlassActionSheetController presentFrom:self
                                         title:entry.filename
                                      subtitle:[NSString stringWithFormat:@"%@ · %@", entry.category, [PDMThemeManager formatBytes:entry.fileSize]]
                                    symbolName:[PDMThemeManager symbolNameForCategory:entry.category]
                                       actions:actions];
}

#pragma mark - UITableViewDataSource & Delegate

- (NSInteger)tableView:(UITableView *__unused)tableView numberOfRowsInSection:(NSInteger __unused)section {
    return (NSInteger)self.visibleFiles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *const reuseID = @"PDMLibCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseID];
    PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseID];
        cell.backgroundColor = [UIColor clearColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        PDMGlassView *card = [[PDMGlassView alloc] initWithCornerRadius:16.0 elevated:NO];
        card.tag = 500;
        card.showAmbientShadow = NO;
        card.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:card];

        UIImageView *icon = [[UIImageView alloc] init];
        icon.tag = 501;
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        [card.contentView addSubview:icon];

        UILabel *title = [[UILabel alloc] init];
        title.tag = 502;
        title.font = [[PDMThemeManager sharedManager] bodyFontOfSize:14.5 weight:UIFontWeightSemibold];
        title.lineBreakMode = NSLineBreakByTruncatingMiddle;
        title.translatesAutoresizingMaskIntoConstraints = NO;
        [card.contentView addSubview:title];

        UILabel *sub = [[UILabel alloc] init];
        sub.tag = 503;
        sub.font = [[PDMThemeManager sharedManager] tabularFontOfSize:11.5 weight:UIFontWeightMedium];
        sub.translatesAutoresizingMaskIntoConstraints = NO;
        [card.contentView addSubview:sub];

        [NSLayoutConstraint activateConstraints:@[
            [card.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:5.0],
            [card.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-5.0],
            [card.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:14.0],
            [card.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-14.0],

            [icon.leadingAnchor constraintEqualToAnchor:card.contentView.leadingAnchor constant:14.0],
            [icon.centerYAnchor constraintEqualToAnchor:card.contentView.centerYAnchor],
            [icon.widthAnchor constraintEqualToConstant:28.0],
            [icon.heightAnchor constraintEqualToConstant:28.0],

            [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12.0],
            [title.trailingAnchor constraintEqualToAnchor:card.contentView.trailingAnchor constant:-14.0],
            [title.topAnchor constraintEqualToAnchor:card.contentView.topAnchor constant:14.0],

            [sub.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
            [sub.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
            [sub.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:3.0]
        ]];
    }

    PDMLibraryFileEntry *entry = self.visibleFiles[(NSUInteger)indexPath.row];
    PDMGlassView *card = (PDMGlassView *)[cell.contentView viewWithTag:500];
    UIImageView *icon = (UIImageView *)[card.contentView viewWithTag:501];
    UILabel *title = (UILabel *)[card.contentView viewWithTag:502];
    UILabel *sub = (UILabel *)[card.contentView viewWithTag:503];

    card.customBorderColor = (self.bulkSelectMode && entry.selected) ? spec.accentColor : nil;
    card.customTintColor = (self.bulkSelectMode && entry.selected) ? [spec.accentColor colorWithAlphaComponent:0.18] : nil;
    [card applyTheme];

    NSString *sym = self.bulkSelectMode
        ? (entry.selected ? @"checkmark.circle.fill" : @"circle")
        : [PDMThemeManager symbolNameForCategory:entry.category];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:20.0 weight:UIImageSymbolWeightSemibold];
    icon.image = [UIImage systemImageNamed:sym withConfiguration:cfg];
    icon.tintColor = self.bulkSelectMode
        ? (entry.selected ? spec.accentColor : spec.tertiaryTextColor)
        : [PDMThemeManager tintColorForCategory:entry.category spec:spec];

    title.text = entry.filename;
    title.textColor = spec.primaryTextColor;

    NSString *extUpper = entry.fileURL.pathExtension.uppercaseString;
    sub.text = [NSString stringWithFormat:@"%@ · %@ · %@",
                entry.category,
                [PDMThemeManager formatBytes:entry.fileSize],
                (extUpper.length > 0 ? extUpper : @"FILE")];
    sub.textColor = spec.secondaryTextColor;
    return cell;
}

- (void)tableView:(UITableView *__unused)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PDMLibraryFileEntry *entry = self.visibleFiles[(NSUInteger)indexPath.row];
    [[PDMThemeManager sharedManager] triggerLightImpact];
    if (self.bulkSelectMode) {
        entry.selected = !entry.selected;
        [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    } else {
        [self presentFileToolsForEntry:entry];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end
