// Copyright © 2026 PrismDM. All Rights Reserved. Proprietary and Confidential.

#import <UIKit/UIKit.h>
#import "PDMBrowser.h"
#import "PDMMediaPlayer.h"
#import "PDMDownloadManager.h"
#import "PDMTheme.h"

@interface PDMSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong, nullable) UIWindow *window;
@property (nonatomic, strong, nullable) PDMRootBrowserViewController *rootBrowser;
@end

@implementation PDMSceneDelegate

- (void)scene:(UIScene *)scene
willConnectToSession:(UISceneSession *__unused)session
      options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) {
        return;
    }
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    UIWindow *win = [[UIWindow alloc] initWithWindowScene:windowScene];
    win.overrideUserInterfaceStyle = [PDMThemeManager sharedManager].currentSpec.interfaceStyle;

    PDMRootBrowserViewController *root = [[PDMRootBrowserViewController alloc] init];
    self.rootBrowser = root;
    win.rootViewController = root;
    self.window = win;
    [win makeKeyAndVisible];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleThemeDidChange)
                                                 name:PDMThemeDidChangeNotification
                                               object:nil];

    NSURL *incomingURL = connectionOptions.URLContexts.allObjects.firstObject.URL;
    if (incomingURL) {
        [root openExternalURL:incomingURL];
    }
}

- (void)handleThemeDidChange {
    self.window.overrideUserInterfaceStyle = [PDMThemeManager sharedManager].currentSpec.interfaceStyle;
}

- (void)scene:(UIScene *__unused)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts {
    NSURL *url = URLContexts.allObjects.firstObject.URL;
    if (url && self.rootBrowser) {
        [self.rootBrowser openExternalURL:url];
    }
}

- (void)sceneDidEnterBackground:(UIScene *__unused)scene {
    [[PDMDownloadManager sharedManager] saveState];
}

- (void)sceneDidDisconnect:(UIScene *__unused)scene {
    [[PDMDownloadManager sharedManager] saveState];
    [self.rootBrowser performExitCleanupIfEnabled];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

@interface PDMAppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation PDMAppDelegate

- (BOOL)application:(UIApplication *__unused)application
didFinishLaunchingWithOptions:(nullable NSDictionary<UIApplicationLaunchOptionsKey, id> *__unused)launchOptions {
    [PDMMediaPlayerViewController configurePlaybackAudioSession];
    (void)[PDMDownloadManager sharedManager];
    return YES;
}

- (UISceneConfiguration *)application:(UIApplication *__unused)application
configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                              options:(UISceneConnectionOptions *__unused)options {
    UISceneConfiguration *cfg = [[UISceneConfiguration alloc] initWithName:@"Default Configuration"
                                                              sessionRole:connectingSceneSession.role];
    cfg.delegateClass = [PDMSceneDelegate class];
    return cfg;
}

- (void)applicationWillTerminate:(UIApplication *__unused)application {
    [[PDMDownloadManager sharedManager] saveState];
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([PDMAppDelegate class]));
    }
}
