// Copyright © 2026 PrismDM. All Rights Reserved. Proprietary and Confidential.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PDMRootBrowserViewController : UIViewController
- (void)openExternalURL:(NSURL *)url;
- (void)performExitCleanupIfEnabled;
@end

NS_ASSUME_NONNULL_END
