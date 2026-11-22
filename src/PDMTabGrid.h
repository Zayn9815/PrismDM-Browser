// Copyright © 2026 PrismDM. All Rights Reserved. Proprietary and Confidential.

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import "PDMUI.h"
#import "PDMMediaSniffer.h"

NS_ASSUME_NONNULL_BEGIN

static const NSInteger kPDMMaxTabCount = 16;

@interface PDMTabItem : NSObject
@property (nonatomic, copy) NSString *tabID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *urlString;
@property (nonatomic, assign) BOOL isPrivate;
@property (nonatomic, assign) BOOL isNewTab;
@property (nonatomic, strong, nullable) UIImage *snapshot;
@property (nonatomic, strong, nullable) WKWebView *webView;
@property (nonatomic, strong) NSMutableArray<PDMDetectedMedia *> *detectedMedia;
@property (nonatomic, assign) NSInteger blockedCountOnPage;
@end

@interface PDMTabGridViewController : UIViewController
@property (nonatomic, copy) NSArray<PDMTabItem *> *standardTabs;
@property (nonatomic, copy) NSArray<PDMTabItem *> *privateTabs;
@property (nonatomic, copy, nullable) NSString *activeTabID;
@property (nonatomic, assign) BOOL showingPrivateSegment;
@property (nonatomic, assign) BOOL canReopenClosedTab;

@property (nonatomic, copy, nullable) void (^onSelectTab)(PDMTabItem *tab);
@property (nonatomic, copy, nullable) void (^onCloseTab)(PDMTabItem *tab);
@property (nonatomic, copy, nullable) void (^onNewTab)(BOOL isPrivate);
@property (nonatomic, copy, nullable) void (^onCloseAllTabs)(BOOL isPrivate);
@property (nonatomic, copy, nullable) dispatch_block_t onReopenLastClosed;
@end

NS_ASSUME_NONNULL_END
