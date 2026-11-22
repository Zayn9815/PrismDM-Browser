// Copyright © 2026 PrismDM. All Rights Reserved. Proprietary and Confidential.

#import "PDMMediaPlayer.h"
#import "PDMUI.h"
#import "PDMTranscoder.h"
#import <AVKit/AVKit.h>
#import <MediaPlayer/MediaPlayer.h>

@interface PDMPlayerRenderView : UIView
@property (nonatomic, strong, readonly) AVPlayerLayer *playerLayer;
@end

@implementation PDMPlayerRenderView

+ (Class)layerClass {
    return [AVPlayerLayer class];
}

- (AVPlayerLayer *)playerLayer {
    return (AVPlayerLayer *)self.layer;
}

@end

@interface PDMMediaPlayerViewController () <AVPictureInPictureControllerDelegate>
@property (nonatomic, strong, readwrite) NSURL *mediaURL;
@property (nonatomic, copy, readwrite) NSString *mediaTitle;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerItem *playerItem;
@property (nonatomic, strong) PDMPlayerRenderView *renderView;
@property (nonatomic, strong, nullable) AVPictureInPictureController *pipController;
@property (nonatomic, strong, nullable) id timeObserver;

@property (nonatomic, strong) UIView *controlsOverlay;
@property (nonatomic, strong) PDMGlassView *topBarGlass;
@property (nonatomic, strong) PDMGlassView *bottomBarGlass;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleBadgeLabel;
@property (nonatomic, strong) PDMGlassPillButton *playPauseBtn;
@property (nonatomic, strong) PDMGlassPillButton *speedBtn;
@property (nonatomic, strong) PDMGlassPillButton *pipBtn;
@property (nonatomic, strong) UISlider *scrubber;
@property (nonatomic, strong) UILabel *elapsedLabel;
@property (nonatomic, strong) UILabel *remainingLabel;
@property (nonatomic, strong) PDMGlassView *gestureHUD;
@property (nonatomic, strong) UILabel *gestureHUDLabel;
@property (nonatomic, strong) UIImageView *gestureHUDIcon;
@property (nonatomic, strong) UIImageView *audioArtworkIcon;

@property (nonatomic, assign) BOOL controlsVisible;
@property (nonatomic, assign) BOOL isScrubbing;
@property (nonatomic, assign) float playbackRate;
@property (nonatomic, copy) NSString *activeQualityLabel;
@property (nonatomic, assign) BOOL panAdjustingBrightness;
@property (nonatomic, assign) CGFloat panStartValue;
@property (nonatomic, strong, nullable) NSTimer *autoHideTimer;
@end

@implementation PDMMediaPlayerViewController

+ (void)configurePlaybackAudioSession {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *err = nil;
    [session setCategory:AVAudioSessionCategoryPlayback
                    mode:AVAudioSessionModeMoviePlayback
                 options:AVAudioSessionCategoryOptionAllowAirPlay | AVAudioSessionCategoryOptionAllowBluetoothA2DP
                   error:&err];
    [session setActive:YES error:&err];
}

- (instancetype)initWithURL:(NSURL *)url
                      title:(NSString *)title
                httpHeaders:(nullable NSDictionary<NSString *, NSString *> *)headers {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _mediaURL = url;
        _mediaTitle = (title.length > 0) ? [title copy] : (url.lastPathComponent ?: @"PrismDM Player");
        _httpHeaders = [headers copy];
        _controlsVisible = YES;
        _playbackRate = 1.0f;
        _activeQualityLabel = @"Auto";
        self.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    return self;
}

- (void)dealloc {
    [self.autoHideTimer invalidate];
    if (self.timeObserver && self.player) {
        [self.player removeTimeObserver:self.timeObserver];
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self teardownRemoteCommands];
}

- (BOOL)prefersStatusBarHidden {
    return !self.controlsVisible;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    [[self class] configurePlaybackAudioSession];

    [self setupPlayer];
    [self buildControlsUI];
    [self setupGestures];
    [self setupRemoteCommands];
    [self startPlayback];
    [self scheduleAutoHide];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.autoHideTimer invalidate];
    if (self.isBeingDismissed && (!self.pipController || !self.pipController.isPictureInPictureActive)) {
        [self.player pause];
        [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:nil];
    }
}

- (void)setupPlayer {
    NSDictionary *options = (self.httpHeaders.count > 0) ? @{ @"AVURLAssetHTTPHeaderFieldsKey": self.httpHeaders } : nil;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:self.mediaURL options:options];
    self.playerItem = [AVPlayerItem playerItemWithAsset:asset];
    self.player = [AVPlayer playerWithPlayerItem:self.playerItem];
    self.player.allowsExternalPlayback = YES;

    self.renderView = [[PDMPlayerRenderView alloc] initWithFrame:self.view.bounds];
    self.renderView.translatesAutoresizingMaskIntoConstraints = NO;
    self.renderView.playerLayer.player = self.player;
    self.renderView.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    [self.view addSubview:self.renderView];

    [NSLayoutConstraint activateConstraints:@[
        [self.renderView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.renderView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.renderView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.renderView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    // Ambient waveform graphic for audio-only files
    NSString *ext = self.mediaURL.pathExtension.lowercaseString;
    BOOL isAudioOnly = [@[@"mp3", @"m4a", @"aac", @"flac", @"wav", @"ogg", @"opus"] containsObject:ext];
    if (isAudioOnly) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:84.0 weight:UIImageSymbolWeightThin];
        self.audioArtworkIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"waveform.circle.fill" withConfiguration:cfg]];
        self.audioArtworkIcon.tintColor = [PDMThemeManager sharedManager].currentSpec.accentColor;
        self.audioArtworkIcon.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:self.audioArtworkIcon];
        [NSLayoutConstraint activateConstraints:@[
            [self.audioArtworkIcon.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
            [self.audioArtworkIcon.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
        ]];
    }

    if ([AVPictureInPictureController isPictureInPictureSupported]) {
        self.pipController = [[AVPictureInPictureController alloc] initWithPlayerLayer:self.renderView.playerLayer];
        self.pipController.delegate = self;
    }

    __weak typeof(self) weakSelf = self;
    self.timeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.5, NSEC_PER_SEC)
                                                                  queue:dispatch_get_main_queue()
                                                             usingBlock:^(CMTime time) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf updateProgressWithTime:time];
    }];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handlePlaybackDidEnd:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:self.playerItem];
}

- (void)buildControlsUI {
    PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;

    self.controlsOverlay = [[UIView alloc] init];
    self.controlsOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    self.controlsOverlay.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.22];
    [self.view addSubview:self.controlsOverlay];

    // Top Liquid Glass Bar
    self.topBarGlass = [[PDMGlassView alloc] initWithCornerRadius:22.0 elevated:YES];
    self.topBarGlass.translatesAutoresizingMaskIntoConstraints = NO;
    [self.controlsOverlay addSubview:self.topBarGlass];

    UIStackView *topRow = [[UIStackView alloc] init];
    topRow.axis = UILayoutConstraintAxisHorizontal;
    topRow.alignment = UIStackViewAlignmentCenter;
    topRow.spacing = 10.0;
    topRow.translatesAutoresizingMaskIntoConstraints = NO;
    [self.topBarGlass.contentView addSubview:topRow];

    PDMGlassPillButton *closeBtn = [[PDMGlassPillButton alloc] initWithTitle:nil symbolName:@"xmark"];
    closeBtn.horizontalPadding = 10.0;
    closeBtn.verticalPadding = 10.0;
    [closeBtn addTarget:self action:@selector(handleCloseTap) forControlEvents:UIControlEventTouchUpInside];
    [topRow addArrangedSubview:closeBtn];

    UIStackView *titleStack = [[UIStackView alloc] init];
    titleStack.axis = UILayoutConstraintAxisVertical;
    titleStack.spacing = 2.0;
    [topRow addArrangedSubview:titleStack];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.text = self.mediaTitle;
    self.titleLabel.font = [[PDMThemeManager sharedManager] displayFontOfSize:15.0 weight:UIFontWeightBold];
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [titleStack addArrangedSubview:self.titleLabel];

    self.subtitleBadgeLabel = [[UILabel alloc] init];
    self.subtitleBadgeLabel.text = @"Auto Quality · Background Audio Ready";
    self.subtitleBadgeLabel.font = [[PDMThemeManager sharedManager] tabularFontOfSize:11.0 weight:UIFontWeightMedium];
    self.subtitleBadgeLabel.textColor = spec.mediaGlowColor;
    [titleStack addArrangedSubview:self.subtitleBadgeLabel];

    // AirPlay Route Picker
    AVRoutePickerView *routePicker = [[AVRoutePickerView alloc] init];
    routePicker.tintColor = [UIColor whiteColor];
    routePicker.activeTintColor = spec.accentColor;
    routePicker.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [routePicker.widthAnchor constraintEqualToConstant:34.0],
        [routePicker.heightAnchor constraintEqualToConstant:34.0]
    ]];
    [topRow addArrangedSubview:routePicker];

    self.pipBtn = [[PDMGlassPillButton alloc] initWithTitle:nil symbolName:@"pip.enter"];
    self.pipBtn.horizontalPadding = 10.0;
    self.pipBtn.verticalPadding = 9.0;
    self.pipBtn.hidden = (self.pipController == nil);
    [self.pipBtn addTarget:self action:@selector(handlePiPTap) forControlEvents:UIControlEventTouchUpInside];
    [topRow addArrangedSubview:self.pipBtn];

    // Center Transport Controls
    UIStackView *centerRow = [[UIStackView alloc] init];
    centerRow.axis = UILayoutConstraintAxisHorizontal;
    centerRow.alignment = UIStackViewAlignmentCenter;
    centerRow.spacing = 24.0;
    centerRow.translatesAutoresizingMaskIntoConstraints = NO;
    [self.controlsOverlay addSubview:centerRow];

    PDMGlassPillButton *rewBtn = [[PDMGlassPillButton alloc] initWithTitle:nil symbolName:@"gobackward.10"];
    rewBtn.horizontalPadding = 16.0;
    rewBtn.verticalPadding = 14.0;
    [rewBtn addTarget:self action:@selector(handleSkipBackward) forControlEvents:UIControlEventTouchUpInside];
    [centerRow addArrangedSubview:rewBtn];

    self.playPauseBtn = [[PDMGlassPillButton alloc] initWithTitle:nil symbolName:@"pause.fill"];
    self.playPauseBtn.prominentAccent = YES;
    self.playPauseBtn.horizontalPadding = 22.0;
    self.playPauseBtn.verticalPadding = 18.0;
    [self.playPauseBtn addTarget:self action:@selector(handlePlayPauseTap) forControlEvents:UIControlEventTouchUpInside];
    [centerRow addArrangedSubview:self.playPauseBtn];

    PDMGlassPillButton *fwdBtn = [[PDMGlassPillButton alloc] initWithTitle:nil symbolName:@"goforward.10"];
    fwdBtn.horizontalPadding = 16.0;
    fwdBtn.verticalPadding = 14.0;
    [fwdBtn addTarget:self action:@selector(handleSkipForward) forControlEvents:UIControlEventTouchUpInside];
    [centerRow addArrangedSubview:fwdBtn];

    // Bottom Liquid Glass Deck
    self.bottomBarGlass = [[PDMGlassView alloc] initWithCornerRadius:24.0 elevated:YES];
    self.bottomBarGlass.translatesAutoresizingMaskIntoConstraints = NO;
    [self.controlsOverlay addSubview:self.bottomBarGlass];

    UIStackView *bottomStack = [[UIStackView alloc] init];
    bottomStack.axis = UILayoutConstraintAxisVertical;
    bottomStack.spacing = 10.0;
    bottomStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.bottomBarGlass.contentView addSubview:bottomStack];

    // Scrubber Row
    UIStackView *scrubRow = [[UIStackView alloc] init];
    scrubRow.axis = UILayoutConstraintAxisHorizontal;
    scrubRow.alignment = UIStackViewAlignmentCenter;
    scrubRow.spacing = 10.0;

    self.elapsedLabel = [[UILabel alloc] init];
    self.elapsedLabel.text = @"0:00";
    self.elapsedLabel.font = [[PDMThemeManager sharedManager] tabularFontOfSize:12.0 weight:UIFontWeightSemibold];
    self.elapsedLabel.textColor = [UIColor whiteColor];
    [scrubRow addArrangedSubview:self.elapsedLabel];

    self.scrubber = [[UISlider alloc] init];
    self.scrubber.minimumTrackTintColor = spec.accentColor;
    self.scrubber.maximumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.25];
    [self.scrubber addTarget:self action:@selector(handleScrubBegan) forControlEvents:UIControlEventTouchDown];
    [self.scrubber addTarget:self action:@selector(handleScrubChanged) forControlEvents:UIControlEventValueChanged];
    [self.scrubber addTarget:self action:@selector(handleScrubEnded) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [scrubRow addArrangedSubview:self.scrubber];

    self.remainingLabel = [[UILabel alloc] init];
    self.remainingLabel.text = @"0:00";
    self.remainingLabel.font = [[PDMThemeManager sharedManager] tabularFontOfSize:12.0 weight:UIFontWeightSemibold];
    self.remainingLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.75];
    [scrubRow addArrangedSubview:self.remainingLabel];

    [bottomStack addArrangedSubview:scrubRow];

    // Pro Action Strip: Audio Track, Quality, Captions, Speed, Convert/Extract
    UIScrollView *actionScroll = [[UIScrollView alloc] init];
    actionScroll.showsHorizontalScrollIndicator = NO;
    actionScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [actionScroll.heightAnchor constraintEqualToConstant:38.0].active = YES;

    UIStackView *actionRow = [[UIStackView alloc] init];
    actionRow.axis = UILayoutConstraintAxisHorizontal;
    actionRow.spacing = 8.0;
    actionRow.translatesAutoresizingMaskIntoConstraints = NO;
    [actionScroll addSubview:actionRow];
    [NSLayoutConstraint activateConstraints:@[
        [actionRow.topAnchor constraintEqualToAnchor:actionScroll.contentLayoutGuide.topAnchor],
        [actionRow.bottomAnchor constraintEqualToAnchor:actionScroll.contentLayoutGuide.bottomAnchor],
        [actionRow.leadingAnchor constraintEqualToAnchor:actionScroll.contentLayoutGuide.leadingAnchor],
        [actionRow.trailingAnchor constraintEqualToAnchor:actionScroll.contentLayoutGuide.trailingAnchor],
        [actionRow.heightAnchor constraintEqualToAnchor:actionScroll.frameLayoutGuide.heightAnchor]
    ]];

    PDMGlassPillButton *audioBtn = [[PDMGlassPillButton alloc] initWithTitle:@"Audio Track" symbolName:@"speaker.wave.2.fill"];
    [audioBtn addTarget:self action:@selector(handleAudioTrackPickerTap) forControlEvents:UIControlEventTouchUpInside];
    [actionRow addArrangedSubview:audioBtn];

    PDMGlassPillButton *qualBtn = [[PDMGlassPillButton alloc] initWithTitle:@"Quality" symbolName:@"sparkles.tv.fill"];
    [qualBtn addTarget:self action:@selector(handleQualityPickerTap) forControlEvents:UIControlEventTouchUpInside];
    [actionRow addArrangedSubview:qualBtn];

    PDMGlassPillButton *subBtn = [[PDMGlassPillButton alloc] initWithTitle:@"Captions" symbolName:@"captions.bubble.fill"];
    [subBtn addTarget:self action:@selector(handleSubtitlePickerTap) forControlEvents:UIControlEventTouchUpInside];
    [actionRow addArrangedSubview:subBtn];

    self.speedBtn = [[PDMGlassPillButton alloc] initWithTitle:@"1.0x" symbolName:@"gauge.with.needle.fill"];
    [self.speedBtn addTarget:self action:@selector(handleSpeedPickerTap) forControlEvents:UIControlEventTouchUpInside];
    [actionRow addArrangedSubview:self.speedBtn];

    if (self.mediaURL.isFileURL) {
        PDMGlassPillButton *convBtn = [[PDMGlassPillButton alloc] initWithTitle:@"Convert / Audio" symbolName:@"wand.and.stars"];
        convBtn.glowing = YES;
        convBtn.customAccentColor = spec.mediaGlowColor;
        [convBtn addTarget:self action:@selector(handleConvertExtractTap) forControlEvents:UIControlEventTouchUpInside];
        [actionRow addArrangedSubview:convBtn];
    }

    [bottomStack addArrangedSubview:actionScroll];

    // Gesture Feedback HUD (Brightness / Volume / Seek)
    self.gestureHUD = [[PDMGlassView alloc] initWithCornerRadius:18.0 elevated:YES];
    self.gestureHUD.pillShape = YES;
    self.gestureHUD.alpha = 0.0;
    self.gestureHUD.userInteractionEnabled = NO;
    self.gestureHUD.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.gestureHUD];

    UIStackView *hudStack = [[UIStackView alloc] init];
    hudStack.axis = UILayoutConstraintAxisHorizontal;
    hudStack.alignment = UIStackViewAlignmentCenter;
    hudStack.spacing = 8.0;
    hudStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.gestureHUD.contentView addSubview:hudStack];

    self.gestureHUDIcon = [[UIImageView alloc] init];
    self.gestureHUDIcon.tintColor = spec.accentColor;
    [hudStack addArrangedSubview:self.gestureHUDIcon];

    self.gestureHUDLabel = [[UILabel alloc] init];
    self.gestureHUDLabel.font = [[PDMThemeManager sharedManager] tabularFontOfSize:14.0 weight:UIFontWeightBold];
    self.gestureHUDLabel.textColor = [UIColor whiteColor];
    [hudStack addArrangedSubview:self.gestureHUDLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.controlsOverlay.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.controlsOverlay.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.controlsOverlay.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.controlsOverlay.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.topBarGlass.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10.0],
        [self.topBarGlass.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:14.0],
        [self.topBarGlass.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-14.0],

        [topRow.topAnchor constraintEqualToAnchor:self.topBarGlass.contentView.topAnchor constant:10.0],
        [topRow.bottomAnchor constraintEqualToAnchor:self.topBarGlass.contentView.bottomAnchor constant:-10.0],
        [topRow.leadingAnchor constraintEqualToAnchor:self.topBarGlass.contentView.leadingAnchor constant:12.0],
        [topRow.trailingAnchor constraintEqualToAnchor:self.topBarGlass.contentView.trailingAnchor constant:-12.0],

        [centerRow.centerXAnchor constraintEqualToAnchor:self.controlsOverlay.centerXAnchor],
        [centerRow.centerYAnchor constraintEqualToAnchor:self.controlsOverlay.centerYAnchor],

        [self.bottomBarGlass.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:14.0],
        [self.bottomBarGlass.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-14.0],
        [self.bottomBarGlass.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10.0],

        [bottomStack.topAnchor constraintEqualToAnchor:self.bottomBarGlass.contentView.topAnchor constant:12.0],
        [bottomStack.bottomAnchor constraintEqualToAnchor:self.bottomBarGlass.contentView.bottomAnchor constant:-12.0],
        [bottomStack.leadingAnchor constraintEqualToAnchor:self.bottomBarGlass.contentView.leadingAnchor constant:14.0],
        [bottomStack.trailingAnchor constraintEqualToAnchor:self.bottomBarGlass.contentView.trailingAnchor constant:-14.0],

        [self.gestureHUD.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.gestureHUD.topAnchor constraintEqualToAnchor:self.topBarGlass.bottomAnchor constant:16.0],
        [hudStack.topAnchor constraintEqualToAnchor:self.gestureHUD.contentView.topAnchor constant:9.0],
        [hudStack.bottomAnchor constraintEqualToAnchor:self.gestureHUD.contentView.bottomAnchor constant:-9.0],
        [hudStack.leadingAnchor constraintEqualToAnchor:self.gestureHUD.contentView.leadingAnchor constant:16.0],
        [hudStack.trailingAnchor constraintEqualToAnchor:self.gestureHUD.contentView.trailingAnchor constant:-16.0]
    ]];
}

- (void)setupGestures {
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    doubleTap.numberOfTapsRequired = 2;
    [self.renderView addGestureRecognizer:doubleTap];

    UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSingleTap)];
    singleTap.numberOfTapsRequired = 1;
    [singleTap requireGestureRecognizerToFail:doubleTap];
    [self.renderView addGestureRecognizer:singleTap];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleVerticalPan:)];
    [self.renderView addGestureRecognizer:pan];
}

- (void)startPlayback {
    [self.player play];
    self.player.rate = self.playbackRate;
    [self updatePlayPauseButton];
    [self updateNowPlayingInfo];
}

#pragma mark - Progress & Now Playing

- (void)updateProgressWithTime:(CMTime)time {
    double current = CMTimeGetSeconds(time);
    double duration = CMTimeGetSeconds(self.playerItem.duration);
    if (!isfinite(current)) current = 0.0;
    if (!isfinite(duration) || duration <= 0.0) duration = 0.0;

    if (!self.isScrubbing && duration > 0.0) {
        self.scrubber.value = (float)(current / duration);
    }
    self.elapsedLabel.text = [PDMThemeManager formatDuration:current];
    self.remainingLabel.text = (duration > 0.0) ? [PDMThemeManager formatDuration:duration] : @"LIVE";
    [self updateNowPlayingInfo];
}

- (void)updatePlayPauseButton {
    BOOL playing = (self.player.rate > 0.01f);
    self.playPauseBtn.symbolName = playing ? @"pause.fill" : @"play.fill";
}

- (void)updateNowPlayingInfo {
    double elapsed = CMTimeGetSeconds(self.player.currentTime);
    double duration = CMTimeGetSeconds(self.playerItem.duration);
    NSMutableDictionary<NSString *, id> *info = [NSMutableDictionary dictionary];
    info[MPMediaItemPropertyTitle] = self.mediaTitle;
    info[MPMediaItemPropertyArtist] = @"PrismDM Pro Player";
    info[MPNowPlayingInfoPropertyPlaybackRate] = @(self.player.rate);
    if (isfinite(elapsed)) {
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(elapsed);
    }
    if (isfinite(duration) && duration > 0.0) {
        info[MPMediaItemPropertyPlaybackDuration] = @(duration);
    }
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:info];
}

- (void)setupRemoteCommands {
    MPRemoteCommandCenter *rcc = [MPRemoteCommandCenter sharedCommandCenter];
    __weak typeof(self) weakSelf = self;

    [rcc.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *__unused event) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return MPRemoteCommandHandlerStatusCommandFailed;
        [strongSelf.player play];
        strongSelf.player.rate = strongSelf.playbackRate;
        [strongSelf updatePlayPauseButton];
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    [rcc.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *__unused event) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return MPRemoteCommandHandlerStatusCommandFailed;
        [strongSelf.player pause];
        [strongSelf updatePlayPauseButton];
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    [rcc.togglePlayPauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *__unused event) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return MPRemoteCommandHandlerStatusCommandFailed;
        [strongSelf handlePlayPauseTap];
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    rcc.skipForwardCommand.preferredIntervals = @[@10];
    [rcc.skipForwardCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *__unused event) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return MPRemoteCommandHandlerStatusCommandFailed;
        [strongSelf seekBySeconds:10.0];
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    rcc.skipBackwardCommand.preferredIntervals = @[@10];
    [rcc.skipBackwardCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *__unused event) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return MPRemoteCommandHandlerStatusCommandFailed;
        [strongSelf seekBySeconds:-10.0];
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    [rcc.changePlaybackPositionCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return MPRemoteCommandHandlerStatusCommandFailed;
        if ([event isKindOfClass:[MPChangePlaybackPositionCommandEvent class]]) {
            MPChangePlaybackPositionCommandEvent *posEvent = (MPChangePlaybackPositionCommandEvent *)event;
            [strongSelf.player seekToTime:CMTimeMakeWithSeconds(posEvent.positionTime, NSEC_PER_SEC)];
            return MPRemoteCommandHandlerStatusSuccess;
        }
        return MPRemoteCommandHandlerStatusCommandFailed;
    }];
}

- (void)teardownRemoteCommands {
    MPRemoteCommandCenter *rcc = [MPRemoteCommandCenter sharedCommandCenter];
    [rcc.playCommand removeTarget:nil];
    [rcc.pauseCommand removeTarget:nil];
    [rcc.togglePlayPauseCommand removeTarget:nil];
    [rcc.skipForwardCommand removeTarget:nil];
    [rcc.skipBackwardCommand removeTarget:nil];
    [rcc.changePlaybackPositionCommand removeTarget:nil];
}

#pragma mark - Controls & Gestures

- (void)showGestureHUDWithSymbol:(NSString *)symbol text:(NSString *)text {
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15.0 weight:UIImageSymbolWeightSemibold];
    self.gestureHUDIcon.image = [UIImage systemImageNamed:symbol withConfiguration:cfg];
    self.gestureHUDLabel.text = text;
    [UIView animateWithDuration:0.16 animations:^{
        self.gestureHUD.alpha = 1.0;
    }];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideGestureHUD) object:nil];
    [self performSelector:@selector(hideGestureHUD) withObject:nil afterDelay:1.1];
}

- (void)hideGestureHUD {
    [UIView animateWithDuration:0.22 animations:^{
        self.gestureHUD.alpha = 0.0;
    }];
}

- (void)scheduleAutoHide {
    [self.autoHideTimer invalidate];
    __weak typeof(self) weakSelf = self;
    self.autoHideTimer = [NSTimer scheduledTimerWithTimeInterval:4.0 repeats:NO block:^(NSTimer *__unused timer) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf && strongSelf.player.rate > 0.01f && !strongSelf.isScrubbing) {
            [strongSelf setControlsVisible:NO animated:YES];
        }
    }];
}

- (void)setControlsVisible:(BOOL)visible animated:(BOOL)animated {
    self.controlsVisible = visible;
    [UIView animateWithDuration:(animated ? 0.24 : 0.0) animations:^{
        self.controlsOverlay.alpha = visible ? 1.0 : 0.0;
        [self setNeedsStatusBarAppearanceUpdate];
    }];
    if (visible) {
        [self scheduleAutoHide];
    }
}

- (void)handleSingleTap {
    [self setControlsVisible:!self.controlsVisible animated:YES];
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)gr {
    CGPoint pt = [gr locationInView:self.view];
    BOOL forward = (pt.x >= CGRectGetMidX(self.view.bounds));
    [self seekBySeconds:(forward ? 10.0 : -10.0)];
    [[PDMThemeManager sharedManager] triggerLightImpact];
    [self showGestureHUDWithSymbol:(forward ? @"goforward.10" : @"gobackward.10")
                              text:(forward ? @"+10s" : @"-10s")];
}

- (void)handleVerticalPan:(UIPanGestureRecognizer *)gr {
    CGPoint loc = [gr locationInView:self.view];
    CGPoint trans = [gr translationInView:self.view];
    if (gr.state == UIGestureRecognizerStateBegan) {
        self.panAdjustingBrightness = (loc.x < CGRectGetMidX(self.view.bounds));
        if (self.panAdjustingBrightness) {
            UIScreen *scr = self.view.window.windowScene.screen;
            self.panStartValue = scr ? scr.brightness : 0.6;
        } else {
            self.panStartValue = (CGFloat)self.player.volume;
        }
    } else if (gr.state == UIGestureRecognizerStateChanged) {
        CGFloat delta = -trans.y / MAX(200.0, CGRectGetHeight(self.view.bounds) * 0.55);
        CGFloat val = MAX(0.0, MIN(1.0, self.panStartValue + delta));
        if (self.panAdjustingBrightness) {
            UIScreen *scr = self.view.window.windowScene.screen;
            if (scr) scr.brightness = val;
            [self showGestureHUDWithSymbol:@"sun.max.fill" text:[NSString stringWithFormat:@"Brightness %.0f%%", val * 100.0]];
        } else {
            self.player.volume = (float)val;
            [self showGestureHUDWithSymbol:(val < 0.02 ? @"speaker.slash.fill" : @"speaker.wave.3.fill")
                                      text:[NSString stringWithFormat:@"Volume %.0f%%", val * 100.0]];
        }
    }
}

- (void)seekBySeconds:(double)delta {
    double cur = CMTimeGetSeconds(self.player.currentTime);
    double dur = CMTimeGetSeconds(self.playerItem.duration);
    if (!isfinite(cur)) cur = 0.0;
    double target = MAX(0.0, cur + delta);
    if (isfinite(dur) && dur > 0.0) {
        target = MIN(dur, target);
    }
    [self.player seekToTime:CMTimeMakeWithSeconds(target, NSEC_PER_SEC) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    [self scheduleAutoHide];
}

- (void)handlePlayPauseTap {
    [[PDMThemeManager sharedManager] triggerLightImpact];
    if (self.player.rate > 0.01f) {
        [self.player pause];
    } else {
        [self.player play];
        self.player.rate = self.playbackRate;
    }
    [self updatePlayPauseButton];
    [self scheduleAutoHide];
}

- (void)handleSkipBackward {
    [self seekBySeconds:-10.0];
    [self showGestureHUDWithSymbol:@"gobackward.10" text:@"-10s"];
}

- (void)handleSkipForward {
    [self seekBySeconds:10.0];
    [self showGestureHUDWithSymbol:@"goforward.10" text:@"+10s"];
}

- (void)handleScrubBegan {
    self.isScrubbing = YES;
    [self.autoHideTimer invalidate];
}

- (void)handleScrubChanged {
    double dur = CMTimeGetSeconds(self.playerItem.duration);
    if (isfinite(dur) && dur > 0.0) {
        double target = (double)self.scrubber.value * dur;
        self.elapsedLabel.text = [PDMThemeManager formatDuration:target];
    }
}

- (void)handleScrubEnded {
    double dur = CMTimeGetSeconds(self.playerItem.duration);
    if (isfinite(dur) && dur > 0.0) {
        double target = (double)self.scrubber.value * dur;
        [self.player seekToTime:CMTimeMakeWithSeconds(target, NSEC_PER_SEC)];
    }
    self.isScrubbing = NO;
    [self scheduleAutoHide];
}

- (void)handlePlaybackDidEnd:(NSNotification *__unused)note {
    [self.player seekToTime:kCMTimeZero];
    [self updatePlayPauseButton];
    [self setControlsVisible:YES animated:YES];
}

- (void)handleCloseTap {
    [[PDMThemeManager sharedManager] triggerLightImpact];
    [self.player pause];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)handlePiPTap {
    [[PDMThemeManager sharedManager] triggerMediumImpact];
    if (!self.pipController) return;
    if (self.pipController.isPictureInPictureActive) {
        [self.pipController stopPictureInPicture];
    } else if (self.pipController.isPictureInPicturePossible) {
        [self.pipController startPictureInPicture];
    } else {
        [PDMToastBanner showInView:self.view message:@"Picture-in-Picture becomes ready once video starts." symbolName:@"pip"];
    }
}

#pragma mark - In-Player Multi-Audio, Quality, Captions, Speed & Convert Pickers

- (void)handleAudioTrackPickerTap {
    [[PDMThemeManager sharedManager] triggerLightImpact];
    AVAsset *asset = self.playerItem.asset;
    __weak typeof(self) weakSelf = self;
    [asset loadMediaSelectionGroupForMediaCharacteristic:AVMediaCharacteristicAudible
                                       completionHandler:^(AVMediaSelectionGroup * _Nullable group, NSError * _Nullable __unused error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (!group || group.options.count == 0) {
                [PDMToastBanner showInView:strongSelf.view message:@"Single default audio track in this media." symbolName:@"speaker.wave.2"];
                return;
            }
            AVMediaSelectionOption *current = [strongSelf.playerItem.currentMediaSelection selectedMediaOptionInMediaSelectionGroup:group];
            NSMutableArray<PDMGlassActionItem *> *actions = [NSMutableArray array];
            for (AVMediaSelectionOption *opt in group.options) {
                BOOL isCur = [opt isEqual:current];
                NSString *sub = opt.extendedLanguageTag ? opt.extendedLanguageTag.uppercaseString : @"Audio Track";
                PDMGlassActionItem *act = [PDMGlassActionItem actionWithTitle:(opt.displayName ?: @"Audio Track")
                                                                     subtitle:(isCur ? [sub stringByAppendingString:@" · Active"] : sub)
                                                                   symbolName:(isCur ? @"checkmark.circle.fill" : @"speaker.wave.2.fill")
                                                                  destructive:NO
                                                                      handler:^{
                    [strongSelf.playerItem selectMediaOption:opt inMediaSelectionGroup:group];
                    strongSelf.subtitleBadgeLabel.text = [NSString stringWithFormat:@"%@ · Audio: %@", strongSelf.activeQualityLabel, opt.displayName ?: @"Selected"];
                    [PDMToastBanner showInView:strongSelf.view message:[NSString stringWithFormat:@"Switched audio to %@", opt.displayName ?: @"track"] symbolName:@"speaker.wave.2.fill"];
                }];
                act.prominent = isCur;
                [actions addObject:act];
            }
            [PDMGlassActionSheetController presentFrom:strongSelf
                                                 title:@"Audio Track Switcher"
                                              subtitle:@"Switch language or channel mix seamlessly"
                                            symbolName:@"speaker.wave.2.fill"
                                               actions:actions];
        });
    }];
}

- (void)handleQualityPickerTap {
    [[PDMThemeManager sharedManager] triggerLightImpact];
    NSArray<NSDictionary<NSString *, id> *> *presets = @[
        @{@"label": @"Auto (Adaptive)", @"bps": @0.0, @"sub": @"Highest available bandwidth"},
        @{@"label": @"2160p 4K Ultra HD", @"bps": @18000000.0, @"sub": @"Peak cap 18 Mbps"},
        @{@"label": @"1080p Full HD", @"bps": @6500000.0, @"sub": @"Peak cap 6.5 Mbps"},
        @{@"label": @"720p HD", @"bps": @3000000.0, @"sub": @"Peak cap 3.0 Mbps"},
        @{@"label": @"480p SD", @"bps": @1200000.0, @"sub": @"Peak cap 1.2 Mbps"},
        @{@"label": @"360p Data Saver", @"bps": @650000.0, @"sub": @"Peak cap 650 kbps"}
    ];
    NSMutableArray<PDMGlassActionItem *> *actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (NSDictionary<NSString *, id> *p in presets) {
        NSString *lbl = p[@"label"];
        double bps = [p[@"bps"] doubleValue];
        BOOL active = [self.activeQualityLabel isEqualToString:lbl];
        PDMGlassActionItem *act = [PDMGlassActionItem actionWithTitle:lbl
                                                             subtitle:p[@"sub"]
                                                           symbolName:(active ? @"checkmark.circle.fill" : @"sparkles.tv")
                                                          destructive:NO
                                                              handler:^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.playerItem.preferredPeakBitRate = bps;
            strongSelf.activeQualityLabel = lbl;
            strongSelf.subtitleBadgeLabel.text = [NSString stringWithFormat:@"Quality: %@ · %.2gx", lbl, strongSelf.playbackRate];
            [PDMToastBanner showInView:strongSelf.view message:[NSString stringWithFormat:@"Stream quality set to %@", lbl] symbolName:@"sparkles.tv.fill"];
        }];
        act.prominent = active;
        [actions addObject:act];
    }
    [PDMGlassActionSheetController presentFrom:self
                                         title:@"Stream Quality"
                                      subtitle:@"Adjust adaptive HLS bitrate cap on the fly"
                                    symbolName:@"sparkles.tv.fill"
                                       actions:actions];
}

- (void)handleSubtitlePickerTap {
    [[PDMThemeManager sharedManager] triggerLightImpact];
    AVAsset *asset = self.playerItem.asset;
    __weak typeof(self) weakSelf = self;
    [asset loadMediaSelectionGroupForMediaCharacteristic:AVMediaCharacteristicLegible
                                       completionHandler:^(AVMediaSelectionGroup * _Nullable group, NSError * _Nullable __unused error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (!group || group.options.count == 0) {
                [PDMToastBanner showInView:strongSelf.view message:@"No subtitles or closed captions found." symbolName:@"captions.bubble"];
                return;
            }
            AVMediaSelectionOption *current = [strongSelf.playerItem.currentMediaSelection selectedMediaOptionInMediaSelectionGroup:group];
            NSMutableArray<PDMGlassActionItem *> *actions = [NSMutableArray array];
            PDMGlassActionItem *offAct = [PDMGlassActionItem actionWithTitle:@"Off"
                                                                    subtitle:@"Disable subtitles"
                                                                  symbolName:(current == nil ? @"checkmark.circle.fill" : @"nosign")
                                                                 destructive:NO
                                                                     handler:^{
                [strongSelf.playerItem selectMediaOption:nil inMediaSelectionGroup:group];
            }];
            offAct.prominent = (current == nil);
            [actions addObject:offAct];

            for (AVMediaSelectionOption *opt in group.options) {
                BOOL isCur = [opt isEqual:current];
                PDMGlassActionItem *act = [PDMGlassActionItem actionWithTitle:(opt.displayName ?: @"Subtitle")
                                                                     subtitle:(opt.extendedLanguageTag.uppercaseString ?: @"Caption")
                                                                   symbolName:(isCur ? @"checkmark.circle.fill" : @"captions.bubble.fill")
                                                                  destructive:NO
                                                                      handler:^{
                    [strongSelf.playerItem selectMediaOption:opt inMediaSelectionGroup:group];
                }];
                act.prominent = isCur;
                [actions addObject:act];
            }
            [PDMGlassActionSheetController presentFrom:strongSelf
                                                 title:@"Subtitles & Captions"
                                              subtitle:@"Select closed caption track"
                                            symbolName:@"captions.bubble.fill"
                                               actions:actions];
        });
    }];
}

- (void)handleSpeedPickerTap {
    [[PDMThemeManager sharedManager] triggerLightImpact];
    NSArray<NSNumber *> *rates = @[@0.5, @0.75, @1.0, @1.25, @1.5, @2.0];
    NSMutableArray<PDMGlassActionItem *> *actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (NSNumber *r in rates) {
        float rateVal = r.floatValue;
        BOOL isCur = (fabsf(self.playbackRate - rateVal) < 0.05f);
        NSString *lbl = [NSString stringWithFormat:@"%.2gx", rateVal];
        PDMGlassActionItem *act = [PDMGlassActionItem actionWithTitle:lbl
                                                             subtitle:(isCur ? @"Current speed" : nil)
                                                           symbolName:(isCur ? @"checkmark.circle.fill" : @"gauge.with.needle")
                                                          destructive:NO
                                                              handler:^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.playbackRate = rateVal;
            strongSelf.speedBtn.titleText = lbl;
            if (strongSelf.player.rate > 0.01f) {
                strongSelf.player.rate = rateVal;
            }
            [strongSelf updateNowPlayingInfo];
        }];
        act.prominent = isCur;
        [actions addObject:act];
    }
    [PDMGlassActionSheetController presentFrom:self
                                         title:@"Playback Speed"
                                      subtitle:@"Pitch-corrected variable playback speed"
                                    symbolName:@"gauge.with.needle.fill"
                                       actions:actions];
}

- (void)handleConvertExtractTap {
    if (!self.mediaURL.isFileURL) return;
    [[PDMThemeManager sharedManager] triggerMediumImpact];

    PDMDetectedMedia *localMedia = [[PDMDetectedMedia alloc] init];
    localMedia.urlString = self.mediaURL.absoluteString;
    localMedia.title = self.mediaTitle;
    localMedia.filename = self.mediaURL.lastPathComponent;
    localMedia.sourceBadge = self.mediaURL.pathExtension.uppercaseString;
    localMedia.isInspected = YES;

    // Populate audio tracks from AVAsset
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:self.mediaURL options:nil];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSArray<AVAssetTrack *> *aTracks = [asset tracksWithMediaType:AVMediaTypeAudio];
#pragma clang diagnostic pop
    for (NSUInteger i = 0; i < aTracks.count; i++) {
        AVAssetTrack *t = aTracks[i];
        PDMMediaAudioTrack *mt = [[PDMMediaAudioTrack alloc] init];
        mt.trackID = [NSString stringWithFormat:@"local_%lu", (unsigned long)i];
        mt.trackIndex = (NSInteger)i;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSString *lang = t.extendedLanguageTag ?: t.languageCode;
#pragma clang diagnostic pop
        mt.language = lang ?: @"und";
        mt.name = lang.length > 0 ? ([[NSLocale currentLocale] localizedStringForLanguageCode:lang].capitalizedString ?: lang) : [NSString stringWithFormat:@"Audio Track %lu", (unsigned long)(i + 1)];
        mt.channels = @"2";
        mt.isDefault = (i == 0);
        [localMedia.audioTracks addObject:mt];
    }
    if (localMedia.audioTracks.count == 0) {
        PDMMediaAudioTrack *def = [[PDMMediaAudioTrack alloc] init];
        def.trackID = @"def";
        def.name = @"Default Audio";
        def.language = @"und";
        def.channels = @"2";
        def.isDefault = YES;
        [localMedia.audioTracks addObject:def];
    }

    PDMMediaPickerSheetViewController *picker = [[PDMMediaPickerSheetViewController alloc] init];
    picker.media = localMedia;
    picker.studioOnlyMode = YES;
    picker.localFilePathForStudio = self.mediaURL.path;
    __weak typeof(self) weakSelf = self;
    picker.onDownloadRequested = ^(PDMDetectedMedia *__unused m,
                                   PDMMediaVideoVariant *__unused v,
                                   PDMMediaAudioTrack *__unused a,
                                   PDMMediaFormatConfig *cfg,
                                   NSString *finalName,
                                   BOOL __unused startNow) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (strongSelf.onRequestConvertLocalFile) {
            strongSelf.onRequestConvertLocalFile(strongSelf.mediaURL, cfg, finalName);
            [PDMToastBanner showInView:strongSelf.view message:[NSString stringWithFormat:@"Converting to %@...", [cfg summaryBadgeText]] symbolName:@"wand.and.stars"];
        } else {
            NSURL *outURL = [[strongSelf.mediaURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:finalName];
            [PDMToastBanner showInView:strongSelf.view message:@"Starting background conversion..." symbolName:@"wand.and.stars"];
            [[PDMTranscoder sharedTranscoder] transcodeFileAtURL:strongSelf.mediaURL
                                                     toOutputURL:outURL
                                                          config:cfg
                                                        progress:nil
                                                      completion:^(BOOL success, NSURL * _Nullable finalURL, NSError * _Nullable error) {
                [PDMToastBanner showInView:strongSelf.view
                                   message:(success ? [NSString stringWithFormat:@"Saved %@", finalURL.lastPathComponent] : (error.localizedDescription ?: @"Conversion failed"))
                                symbolName:(success ? @"checkmark.circle.fill" : @"exclamationmark.triangle.fill")];
            }];
        }
    };
    [picker presentFromViewController:self];
}

#pragma mark - AVPictureInPictureControllerDelegate

- (void)pictureInPictureControllerDidStartPictureInPicture:(AVPictureInPictureController *__unused)pictureInPictureController {
    self.pipBtn.symbolName = @"pip.exit";
}

- (void)pictureInPictureControllerDidStopPictureInPicture:(AVPictureInPictureController *__unused)pictureInPictureController {
    self.pipBtn.symbolName = @"pip.enter";
}

@end
