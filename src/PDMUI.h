// Copyright © 2026 PrismDM. All Rights Reserved. Proprietary and Confidential.

#import <UIKit/UIKit.h>
#import "PDMTheme.h"

NS_ASSUME_NONNULL_BEGIN

@interface PDMGlassView : UIView
@property (nonatomic, assign) CGFloat glassCornerRadius;
@property (nonatomic, assign) BOOL pillShape;
@property (nonatomic, assign) BOOL elevated;
@property (nonatomic, assign) BOOL showAmbientShadow;
@property (nonatomic, strong, nullable) UIColor *customBorderColor;
@property (nonatomic, strong, nullable) UIColor *customTintColor;
@property (nonatomic, strong, readonly) UIView *contentView;

- (instancetype)initWithCornerRadius:(CGFloat)radius elevated:(BOOL)elevated;
- (void)applyTheme;
@end

@interface PDMGlassPillButton : UIControl
@property (nonatomic, copy, nullable) NSString *titleText;
@property (nonatomic, copy, nullable) NSString *symbolName;
@property (nonatomic, copy, nullable) NSString *badgeText;
@property (nonatomic, assign) BOOL prominentAccent;
@property (nonatomic, assign) BOOL glowing;
@property (nonatomic, assign) BOOL borderless;
@property (nonatomic, assign) CGFloat symbolPointSize;
@property (nonatomic, strong, nullable) UIColor *customAccentColor;
@property (nonatomic, assign) CGFloat horizontalPadding;
@property (nonatomic, assign) CGFloat verticalPadding;

- (instancetype)initWithTitle:(nullable NSString *)title symbolName:(nullable NSString *)symbolName;
- (void)applyTheme;
@end

@interface PDMGlassChip : UIControl
@property (nonatomic, copy) NSString *titleText;
@property (nonatomic, copy, nullable) NSString *subtitleText;
@property (nonatomic, copy, nullable) NSString *symbolName;
@property (nonatomic, assign) BOOL chipSelected;
@property (nonatomic, strong, nullable) UIColor *customAccentColor;

- (instancetype)initWithTitle:(NSString *)title subtitle:(nullable NSString *)subtitle;
- (void)applyTheme;
@end

@interface PDMSegmentProgressView : UIView
@property (nonatomic, assign) NSInteger segmentCount;
@property (nonatomic, copy) NSArray<NSNumber *> *segmentProgress; // values 0.0 .. 1.0
@property (nonatomic, assign) BOOL convertingMode;
@property (nonatomic, assign) double conversionProgress; // 0.0 .. 1.0
@property (nonatomic, assign) BOOL pausedState;
@property (nonatomic, assign) BOOL failedState;
- (void)applyTheme;
@end

@interface PDMGlassSheetViewController : UIViewController
@property (nonatomic, copy) NSString *sheetTitle;
@property (nonatomic, copy, nullable) NSString *sheetSubtitle;
@property (nonatomic, copy, nullable) NSString *sheetSymbolName;
@property (nonatomic, strong, nullable) UIColor *sheetSymbolTint;
@property (nonatomic, assign) BOOL prefersLargeDefaultDetent;
@property (nonatomic, assign) BOOL allowsMediumDetent;

@property (nonatomic, strong, readonly) UIScrollView *scrollView;
@property (nonatomic, strong, readonly) UIStackView *contentStack;
@property (nonatomic, strong, readonly) UIView *bottomBarContainer;
@property (nonatomic, strong, readonly) UIStackView *bottomBarStack;

- (void)configureSheetPresentation;
- (void)presentFromViewController:(UIViewController *)presenter;
- (void)applyTheme;
- (void)showBottomBar:(BOOL)show;
- (UIView *)sectionHeaderWithTitle:(NSString *)title detail:(nullable NSString *)detail;
@end

@interface PDMGlassActionItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *subtitle;
@property (nonatomic, copy, nullable) NSString *symbolName;
@property (nonatomic, assign) BOOL destructive;
@property (nonatomic, assign) BOOL prominent;
@property (nonatomic, copy, nullable) dispatch_block_t handler;

+ (instancetype)actionWithTitle:(NSString *)title
                       subtitle:(nullable NSString *)subtitle
                     symbolName:(nullable NSString *)symbolName
                    destructive:(BOOL)destructive
                        handler:(nullable dispatch_block_t)handler;
@end

@interface PDMGlassActionSheetController : PDMGlassSheetViewController
+ (void)presentFrom:(UIViewController *)presenter
              title:(NSString *)title
           subtitle:(nullable NSString *)subtitle
         symbolName:(nullable NSString *)symbolName
            actions:(NSArray<PDMGlassActionItem *> *)actions;

+ (void)presentTextInputFrom:(UIViewController *)presenter
                       title:(NSString *)title
                    subtitle:(nullable NSString *)subtitle
                 placeholder:(nullable NSString *)placeholder
                 initialText:(nullable NSString *)initialText
                confirmTitle:(NSString *)confirmTitle
                  onConfirm:(void (^)(NSString *value))onConfirm;
@end

@interface PDMToastBanner : NSObject
+ (void)showInView:(UIView *)hostView message:(NSString *)message symbolName:(nullable NSString *)symbolName;
+ (void)showInView:(UIView *)hostView message:(NSString *)message symbolName:(nullable NSString *)symbolName accentColor:(nullable UIColor *)accentColor;
@end

@interface PDMBiometricGuard : NSObject
+ (instancetype)sharedGuard;
- (BOOL)isUnlockedRecently;
- (void)invalidateSession;
- (void)authenticateWithReason:(NSString *)reason completion:(void (^)(BOOL success, NSString * _Nullable errorMessage))completion;
@end

NS_ASSUME_NONNULL_END
