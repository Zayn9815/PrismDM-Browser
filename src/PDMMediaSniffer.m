// Copyright © 2026 PrismDM. All Rights Reserved. Proprietary and Confidential.

#import "PDMMediaSniffer.h"
#import <AVFoundation/AVFoundation.h>

#pragma mark - PDMWeakScriptMessageHandler

@implementation PDMWeakScriptMessageHandler

- (instancetype)initWithDelegate:(id<WKScriptMessageHandler>)delegate {
    self = [super init];
    if (self) {
        _delegate = delegate;
    }
    return self;
}

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    id<WKScriptMessageHandler> strongDelegate = self.delegate;
    if (strongDelegate) {
        [strongDelegate userContentController:userContentController didReceiveScriptMessage:message];
    }
}

@end

#pragma mark - Models

@implementation PDMMediaAudioTrack

- (NSString *)displayLabel {
    NSMutableString *out = [NSMutableString string];
    if (self.name.length > 0) {
        [out appendString:self.name];
    } else if (self.language.length > 0) {
        [out appendString:self.language.uppercaseString];
    } else {
        [out appendFormat:@"Track %ld", (long)(self.trackIndex + 1)];
    }
    if (self.channels.length > 0) {
        if ([self.channels isEqualToString:@"6"]) {
            [out appendString:@" 5.1"];
        } else if ([self.channels isEqualToString:@"2"]) {
            [out appendString:@" Stereo"];
        } else if (![out containsString:self.channels]) {
            [out appendFormat:@" %@ch", self.channels];
        }
    }
    return out;
}

@end

@implementation PDMMediaVideoVariant

- (NSString *)specSubtitle {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (self.fps > 1.0) {
        [parts addObject:[NSString stringWithFormat:@"%.0ffps", self.fps]];
    }
    if (self.bandwidthBps > 0) {
        double mbps = (double)self.bandwidthBps / 1000000.0;
        if (mbps >= 1.0) {
            [parts addObject:[NSString stringWithFormat:@"%.1f Mbps", mbps]];
        } else {
            [parts addObject:[NSString stringWithFormat:@"%lld kbps", (long long)(self.bandwidthBps / 1000)]];
        }
    }
    if (self.estimatedBytes > 0) {
        [parts addObject:[PDMThemeManager formatBytes:self.estimatedBytes]];
    }
    return (parts.count > 0) ? [parts componentsJoinedByString:@" · "] : (self.isAudioOnly ? @"Audio Stream" : @"Auto");
}

@end

@implementation PDMMediaFormatConfig

+ (instancetype)defaultConfig {
    PDMMediaFormatConfig *c = [[PDMMediaFormatConfig alloc] init];
    c.outputMode = PDMOutputModeOriginal;
    c.videoFormat = PDMVideoFormatMP4H264;
    c.targetResolution = PDMTargetResolutionOriginal;
    c.qualityPreset = PDMVideoQualityPresetHigh;
    c.audioFormat = PDMAudioFormatMP3;
    c.audioBitrateKbps = 320;
    c.selectedAudioTrackIndex = 0;
    c.destinationCategory = @"Auto";
    c.segmentCount = [PDMThemeManager sharedManager].defaultSegmentCount;
    return c;
}

- (id)copyWithZone:(nullable NSZone *)zone {
    PDMMediaFormatConfig *c = [[[self class] allocWithZone:zone] init];
    c.outputMode = self.outputMode;
    c.videoFormat = self.videoFormat;
    c.targetResolution = self.targetResolution;
    c.qualityPreset = self.qualityPreset;
    c.audioFormat = self.audioFormat;
    c.audioBitrateKbps = self.audioBitrateKbps;
    c.selectedAudioTrackIndex = self.selectedAudioTrackIndex;
    c.destinationCategory = [self.destinationCategory copy];
    c.segmentCount = self.segmentCount;
    return c;
}

- (NSString *)targetFileExtension {
    if (self.outputMode == PDMOutputModeAudioOnly) {
        switch (self.audioFormat) {
            case PDMAudioFormatMP3: return @"mp3";
            case PDMAudioFormatM4AAAC: return @"m4a";
            case PDMAudioFormatM4AALAC: return @"m4a";
            case PDMAudioFormatFLAC: return @"flac";
            case PDMAudioFormatWAV: return @"wav";
        }
    } else if (self.outputMode == PDMOutputModeVideo) {
        switch (self.videoFormat) {
            case PDMVideoFormatMP4H264:
            case PDMVideoFormatMP4HEVC: return @"mp4";
            case PDMVideoFormatMOVH264:
            case PDMVideoFormatMOVHEVC: return @"mov";
            case PDMVideoFormatM4VH264: return @"m4v";
        }
    }
    return @"";
}

- (NSString *)summaryBadgeText {
    if (self.outputMode == PDMOutputModeOriginal) {
        return @"Original";
    }
    if (self.outputMode == PDMOutputModeAudioOnly) {
        switch (self.audioFormat) {
            case PDMAudioFormatMP3: return [NSString stringWithFormat:@"%ldk MP3", (long)self.audioBitrateKbps];
            case PDMAudioFormatM4AAAC: return [NSString stringWithFormat:@"%ldk M4A AAC", (long)self.audioBitrateKbps];
            case PDMAudioFormatM4AALAC: return @"M4A ALAC";
            case PDMAudioFormatFLAC: return @"FLAC Lossless";
            case PDMAudioFormatWAV: return @"WAV PCM";
        }
    }
    NSString *fmt = @"MP4 H.264";
    switch (self.videoFormat) {
        case PDMVideoFormatMP4H264: fmt = @"MP4 H.264"; break;
        case PDMVideoFormatMP4HEVC: fmt = @"MP4 HEVC"; break;
        case PDMVideoFormatMOVH264: fmt = @"MOV H.264"; break;
        case PDMVideoFormatMOVHEVC: fmt = @"MOV HEVC"; break;
        case PDMVideoFormatM4VH264: fmt = @"M4V H.264"; break;
    }
    if (self.targetResolution == PDMTargetResolution1080p) return [fmt stringByAppendingString:@" · 1080p"];
    if (self.targetResolution == PDMTargetResolution720p) return [fmt stringByAppendingString:@" · 720p"];
    if (self.targetResolution == PDMTargetResolution480p) return [fmt stringByAppendingString:@" · 480p"];
    return fmt;
}

- (NSDictionary<NSString *, id> *)toDictionary {
    return @{
        @"outputMode": @(self.outputMode),
        @"videoFormat": @(self.videoFormat),
        @"targetResolution": @(self.targetResolution),
        @"qualityPreset": @(self.qualityPreset),
        @"audioFormat": @(self.audioFormat),
        @"audioBitrateKbps": @(self.audioBitrateKbps),
        @"selectedAudioTrackIndex": @(self.selectedAudioTrackIndex),
        @"destinationCategory": self.destinationCategory ?: @"Auto",
        @"segmentCount": @(self.segmentCount)
    };
}

+ (instancetype)fromDictionary:(NSDictionary<NSString *, id> *)dict {
    PDMMediaFormatConfig *c = [self defaultConfig];
    if (![dict isKindOfClass:[NSDictionary class]]) {
        return c;
    }
    if (dict[@"outputMode"]) c.outputMode = (PDMOutputMode)[dict[@"outputMode"] integerValue];
    if (dict[@"videoFormat"]) c.videoFormat = (PDMVideoFormat)[dict[@"videoFormat"] integerValue];
    if (dict[@"targetResolution"]) c.targetResolution = (PDMTargetResolution)[dict[@"targetResolution"] integerValue];
    if (dict[@"qualityPreset"]) c.qualityPreset = (PDMVideoQualityPreset)[dict[@"qualityPreset"] integerValue];
    if (dict[@"audioFormat"]) c.audioFormat = (PDMAudioFormat)[dict[@"audioFormat"] integerValue];
    if (dict[@"audioBitrateKbps"]) c.audioBitrateKbps = [dict[@"audioBitrateKbps"] integerValue];
    if (dict[@"selectedAudioTrackIndex"]) c.selectedAudioTrackIndex = [dict[@"selectedAudioTrackIndex"] integerValue];
    if ([dict[@"destinationCategory"] isKindOfClass:[NSString class]]) c.destinationCategory = dict[@"destinationCategory"];
    if (dict[@"segmentCount"]) c.segmentCount = [dict[@"segmentCount"] integerValue];
    return c;
}

@end

@implementation PDMDetectedMedia

- (instancetype)init {
    self = [super init];
    if (self) {
        _mediaID = [NSUUID UUID].UUIDString;
        _variants = [NSMutableArray array];
        _audioTracks = [NSMutableArray array];
        _detectedAt = [NSDate date];
    }
    return self;
}

@end

@implementation PDMPageResource
@end

#pragma mark - PDMMediaSniffer

static NSDictionary<NSString *, NSString *> *PDMParseHLSAttributes(NSString *attrLine) {
    NSMutableDictionary<NSString *, NSString *> *attrs = [NSMutableDictionary dictionary];
    NSUInteger len = attrLine.length;
    NSUInteger i = 0;
    while (i < len) {
        while (i < len && ([attrLine characterAtIndex:i] == ',' || [attrLine characterAtIndex:i] == ' ')) {
            i++;
        }
        NSUInteger keyStart = i;
        while (i < len && [attrLine characterAtIndex:i] != '=') {
            i++;
        }
        if (i >= len) break;
        NSString *key = [[attrLine substringWithRange:NSMakeRange(keyStart, i - keyStart)]
                         stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        i++; // skip '='
        if (i >= len) break;
        NSString *val = @"";
        if ([attrLine characterAtIndex:i] == '"') {
            i++;
            NSUInteger valStart = i;
            while (i < len && [attrLine characterAtIndex:i] != '"') {
                i++;
            }
            val = [attrLine substringWithRange:NSMakeRange(valStart, i - valStart)];
            if (i < len) i++; // skip closing quote
        } else {
            NSUInteger valStart = i;
            while (i < len && [attrLine characterAtIndex:i] != ',') {
                i++;
            }
            val = [[attrLine substringWithRange:NSMakeRange(valStart, i - valStart)]
                   stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        }
        if (key.length > 0) {
            attrs[key.uppercaseString] = val;
        }
    }
    return attrs;
}

static NSString *PDMQualityLabelForHeight(NSInteger height) {
    if (height >= 2160) return @"2160p 4K";
    if (height >= 1440) return @"1440p QHD";
    if (height >= 1080) return @"1080p Full HD";
    if (height >= 720) return @"720p HD";
    if (height >= 480) return @"480p SD";
    if (height >= 360) return @"360p";
    if (height > 0) return [NSString stringWithFormat:@"%ldp", (long)height];
    return @"Original";
}

@implementation PDMMediaSniffer

+ (WKUserScript *)mediaSnifferUserScript {
    NSString *js = @""
    "(function(){"
    "  if (window.__pdmSnifferInstalled) return;"
    "  window.__pdmSnifferInstalled = true;"
    "  var seen = Object.create(null);"
    "  var mediaRe = /\\.(m3u8|mpd|mp4|m4v|mov|webm|mkv|mp3|m4a|aac|flac|ogg|wav|opus)(\\?|$|#)/i;"
    "  function report(url, kind, mime) {"
    "    if (!url || typeof url !== 'string') return;"
    "    if (url.indexOf('blob:') === 0 || url.indexOf('data:') === 0) return;"
    "    var abs = url;"
    "    try { abs = new URL(url, location.href).href; } catch(e) {}"
    "    if (!mediaRe.test(abs) && !(mime && /^(video|audio|application\\/vnd\\.apple\\.mpegurl|application\\/x-mpegurl|application\\/dash\\+xml)/i.test(mime))) return;"
    "    if (seen[abs]) return;"
    "    seen[abs] = true;"
    "    try {"
    "      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.pdmMedia) {"
    "        window.webkit.messageHandlers.pdmMedia.postMessage({url:abs, kind:(kind||'media'), mime:(mime||''), title:(document.title||''), pageUrl:location.href});"
    "      }"
    "    } catch(e) {}"
    "  }"
    "  function scanDOM(){"
    "    try {"
    "      var els = document.querySelectorAll('video, audio, source');"
    "      for (var i = 0; i < els.length; i++) {"
    "        var el = els[i];"
    "        if (el.currentSrc) report(el.currentSrc, el.tagName.toLowerCase(), el.type || '');"
    "        if (el.src) report(el.src, el.tagName.toLowerCase(), el.type || '');"
    "      }"
    "    } catch(e) {}"
    "  }"
    "  try {"
    "    var origFetch = window.fetch;"
    "    if (origFetch) {"
    "      window.fetch = function(input, init) {"
    "        var reqUrl = (typeof input === 'string') ? input : (input && input.url ? input.url : '');"
    "        if (reqUrl) report(reqUrl, 'fetch', '');"
    "        var p = origFetch.apply(this, arguments);"
    "        if (p && p.then) {"
    "          p.then(function(res){"
    "            try {"
    "              var ct = res.headers ? (res.headers.get('content-type') || '') : '';"
    "              report(res.url || reqUrl, 'fetch', ct);"
    "            } catch(e) {}"
    "          }).catch(function(){});"
    "        }"
    "        return p;"
    "      };"
    "    }"
    "  } catch(e) {}"
    "  try {"
    "    var origOpen = XMLHttpRequest.prototype.open;"
    "    XMLHttpRequest.prototype.open = function(method, url) {"
    "      this.__pdmUrl = url;"
    "      if (url) report(String(url), 'xhr', '');"
    "      return origOpen.apply(this, arguments);"
    "    };"
    "    var origSend = XMLHttpRequest.prototype.send;"
    "    XMLHttpRequest.prototype.send = function() {"
    "      var self = this;"
    "      this.addEventListener('readystatechange', function(){"
    "        if (self.readyState === 2) {"
    "          try {"
    "            var ct = self.getResponseHeader('content-type') || '';"
    "            report(self.responseURL || self.__pdmUrl || '', 'xhr', ct);"
    "          } catch(e) {}"
    "        }"
    "      });"
    "      return origSend.apply(this, arguments);"
    "    };"
    "  } catch(e) {}"
    "  try {"
    "    var desc = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');"
    "    if (desc && desc.set) {"
    "      Object.defineProperty(HTMLMediaElement.prototype, 'src', {"
    "        get: desc.get,"
    "        set: function(v) { report(String(v), 'media_src', ''); return desc.set.call(this, v); },"
    "        configurable: true"
    "      });"
    "    }"
    "    var origLoad = HTMLMediaElement.prototype.load;"
    "    HTMLMediaElement.prototype.load = function() {"
    "      if (this.currentSrc) report(this.currentSrc, 'media_load', '');"
    "      if (this.src) report(this.src, 'media_load', '');"
    "      return origLoad.apply(this, arguments);"
    "    };"
    "  } catch(e) {}"
    "  document.addEventListener('play', function(ev){"
    "    var t = ev.target;"
    "    if (t && (t.currentSrc || t.src)) report(t.currentSrc || t.src, 'play', '');"
    "  }, true);"
    "  if (document.readyState === 'loading') { document.addEventListener('DOMContentLoaded', scanDOM); } else { scanDOM(); }"
    "  setTimeout(scanDOM, 1200);"
    "  setTimeout(scanDOM, 3500);"
    "})();";

    return [[WKUserScript alloc] initWithSource:js
                                  injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                               forMainFrameOnly:NO];
}

+ (NSString *)pageResourceExtractionJavaScript {
    return @""
    "(function(){"
    "  var out = []; var seen = Object.create(null);"
    "  function add(url, title, cat) {"
    "    if (!url || url.indexOf('javascript:') === 0 || url.indexOf('data:') === 0 || url.indexOf('blob:') === 0) return;"
    "    var abs = url; try { abs = new URL(url, location.href).href; } catch(e) {}"
    "    if (seen[abs]) return; seen[abs] = true;"
    "    var path = abs.split('?')[0].split('#')[0];"
    "    var ext = (path.lastIndexOf('.') > path.lastIndexOf('/')) ? path.substring(path.lastIndexOf('.')+1).toLowerCase() : '';"
    "    out.push({url:abs, title:(title || path.split('/').pop() || abs), category:cat, ext:ext});"
    "  }"
    "  var vids = document.querySelectorAll('video, video source');"
    "  for (var i=0;i<vids.length;i++) { var u = vids[i].currentSrc || vids[i].src; if (u) add(u, document.title, 'Videos'); }"
    "  var auds = document.querySelectorAll('audio, audio source');"
    "  for (var j=0;j<auds.length;j++) { var au = auds[j].currentSrc || auds[j].src; if (au) add(au, document.title, 'Audio'); }"
    "  var imgs = document.querySelectorAll('img');"
    "  for (var k=0;k<imgs.length && out.length<180;k++) { var im = imgs[k]; if ((im.naturalWidth||0) >= 160 && (im.currentSrc||im.src)) add(im.currentSrc||im.src, im.alt||'', 'Images'); }"
    "  var links = document.querySelectorAll('a[href]');"
    "  var vidRe = /\\.(mp4|m4v|mov|mkv|webm|m3u8)(\\?|$)/i;"
    "  var audRe = /\\.(mp3|m4a|aac|flac|wav|ogg|opus)(\\?|$)/i;"
    "  var arcRe = /\\.(zip|rar|7z|tar|gz|ipa|dmg|apk)(\\?|$)/i;"
    "  var docRe = /\\.(pdf|docx?|xlsx?|pptx?|epub|txt|csv|json)(\\?|$)/i;"
    "  var imgRe = /\\.(png|jpe?g|webp|gif|svg|heic)(\\?|$)/i;"
    "  for (var m=0;m<links.length && out.length<220;m++) {"
    "    var href = links[m].href; var txt = (links[m].innerText||'').trim();"
    "    if (vidRe.test(href)) add(href, txt, 'Videos');"
    "    else if (audRe.test(href)) add(href, txt, 'Audio');"
    "    else if (arcRe.test(href)) add(href, txt, 'Archives');"
    "    else if (docRe.test(href)) add(href, txt, 'Documents');"
    "    else if (imgRe.test(href)) add(href, txt, 'Images');"
    "  }"
    "  return JSON.stringify(out);"
    "})();";
}

+ (BOOL)isMediaURLString:(NSString *)urlString {
    if (urlString.length == 0) return NO;
    NSURL *url = [NSURL URLWithString:urlString];
    NSString *ext = url.pathExtension.lowercaseString;
    NSSet<NSString *> *exts = [NSSet setWithObjects:
        @"m3u8", @"mpd", @"mp4", @"m4v", @"mov", @"webm", @"mkv",
        @"mp3", @"m4a", @"aac", @"flac", @"ogg", @"wav", @"opus", nil];
    return [exts containsObject:ext];
}

+ (BOOL)isDownloadableResponse:(NSURLResponse *)response {
    if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
        return NO;
    }
    NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
    NSString *disp = nil;
    for (NSString *k in http.allHeaderFields) {
        if ([k.lowercaseString isEqualToString:@"content-disposition"]) {
            disp = [http.allHeaderFields[k] description].lowercaseString;
            break;
        }
    }
    if (disp && [disp containsString:@"attachment"]) {
        return YES;
    }
    NSString *mime = http.MIMEType.lowercaseString ?: @"";
    if ([mime hasPrefix:@"text/html"] || [mime hasPrefix:@"application/xhtml"] || [mime hasPrefix:@"image/"] || [mime isEqualToString:@"text/plain"]) {
        return NO;
    }
    NSArray<NSString *> *downloadMimes = @[
        @"application/octet-stream", @"application/zip", @"application/x-rar",
        @"application/x-7z-compressed", @"application/gzip", @"application/x-tar",
        @"application/pdf", @"application/epub+zip", @"application/vnd.android.package-archive",
        @"application/x-apple-diskimage", @"video/", @"audio/"
    ];
    for (NSString *prefix in downloadMimes) {
        if ([mime hasPrefix:prefix]) {
            return YES;
        }
    }
    return NO;
}

+ (NSString *)sourceBadgeForURLString:(NSString *)urlString mimeType:(nullable NSString *)mimeType {
    NSURL *u = [NSURL URLWithString:urlString];
    NSString *ext = u.pathExtension.uppercaseString;
    NSString *mime = mimeType.lowercaseString ?: @"";
    if ([ext isEqualToString:@"M3U8"] || [mime containsString:@"mpegurl"]) return @"HLS";
    if ([ext isEqualToString:@"MPD"] || [mime containsString:@"dash+xml"]) return @"DASH";
    if (ext.length >= 2 && ext.length <= 5) return ext;
    if ([mime hasPrefix:@"video/"]) return @"VIDEO";
    if ([mime hasPrefix:@"audio/"]) return @"AUDIO";
    return @"MEDIA";
}

+ (nullable PDMDetectedMedia *)mediaFromMessageBody:(id)body
                                           pageURL:(nullable NSString *)pageURL
                                         pageTitle:(nullable NSString *)pageTitle
                                         userAgent:(nullable NSString *)userAgent
                                      cookieHeader:(nullable NSString *)cookieHeader {
    if (![body isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSDictionary *dict = (NSDictionary *)body;
    NSString *urlStr = [dict[@"url"] isKindOfClass:[NSString class]] ? dict[@"url"] : nil;
    if (urlStr.length < 8) return nil;

    NSString *mime = [dict[@"mime"] isKindOfClass:[NSString class]] ? dict[@"mime"] : nil;
    NSString *msgTitle = [dict[@"title"] isKindOfClass:[NSString class]] ? dict[@"title"] : nil;

    PDMDetectedMedia *m = [[PDMDetectedMedia alloc] init];
    m.urlString = urlStr;
    m.pageURLString = pageURL;
    m.referer = pageURL;
    m.userAgent = userAgent;
    m.cookieHeader = cookieHeader;
    m.mimeType = mime;
    m.sourceBadge = [self sourceBadgeForURLString:urlStr mimeType:mime];
    m.isHLS = [m.sourceBadge isEqualToString:@"HLS"];
    m.isDASH = [m.sourceBadge isEqualToString:@"DASH"];

    NSURL *u = [NSURL URLWithString:urlStr];
    NSString *baseTitle = (msgTitle.length > 0) ? msgTitle : (pageTitle.length > 0 ? pageTitle : u.lastPathComponent);
    if (baseTitle.length == 0) baseTitle = @"Detected Media";
    m.title = baseTitle;

    NSString *fallbackExt = m.isHLS ? @"mp4" : (u.pathExtension.length > 0 ? u.pathExtension.lowercaseString : @"mp4");
    m.filename = [PDMThemeManager sanitizeFilename:baseTitle fallbackExtension:fallbackExt];
    return m;
}

+ (void)parseHLSPlaylistText:(NSString *)playlistText
                     baseURL:(NSURL *)baseURL
                   intoMedia:(PDMDetectedMedia *)media {
    [media.variants removeAllObjects];
    [media.audioTracks removeAllObjects];

    NSArray<NSString *> *lines = [playlistText componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    double totalDuration = 0.0;
    BOOL isMaster = NO;

    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *line = [lines[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (line.length == 0) continue;

        if ([line hasPrefix:@"#EXT-X-KEY:"]) {
            NSDictionary<NSString *, NSString *> *attrs = PDMParseHLSAttributes([line substringFromIndex:11]);
            NSString *method = attrs[@"METHOD"].uppercaseString;
            NSString *keyFormat = attrs[@"KEYFORMAT"].lowercaseString;
            if ([method containsString:@"SAMPLE-AES"] || [keyFormat containsString:@"streamingkeydelivery"] || [attrs[@"URI"] hasPrefix:@"skd://"]) {
                media.isDRMProtected = YES;
            } else if ([method isEqualToString:@"AES-128"]) {
                media.isAES128Encrypted = YES;
            }
        } else if ([line hasPrefix:@"#EXT-X-MEDIA:"]) {
            isMaster = YES;
            NSDictionary<NSString *, NSString *> *attrs = PDMParseHLSAttributes([line substringFromIndex:13]);
            if ([attrs[@"TYPE"].uppercaseString isEqualToString:@"AUDIO"]) {
                PDMMediaAudioTrack *track = [[PDMMediaAudioTrack alloc] init];
                track.trackID = [NSUUID UUID].UUIDString;
                track.trackIndex = (NSInteger)media.audioTracks.count;
                track.name = attrs[@"NAME"] ?: (attrs[@"LANGUAGE"] ?: @"Audio");
                track.language = attrs[@"LANGUAGE"] ?: @"";
                track.groupID = attrs[@"GROUP-ID"] ?: @"";
                track.channels = attrs[@"CHANNELS"] ?: @"2";
                track.isDefault = [attrs[@"DEFAULT"].uppercaseString isEqualToString:@"YES"];
                track.isAutoSelect = [attrs[@"AUTOSELECT"].uppercaseString isEqualToString:@"YES"];
                NSString *rawURI = attrs[@"URI"];
                if (rawURI.length > 0) {
                    NSURL *resolved = [NSURL URLWithString:rawURI relativeToURL:baseURL].absoluteURL;
                    track.uri = resolved.absoluteString ?: rawURI;
                }
                [media.audioTracks addObject:track];
            }
        } else if ([line hasPrefix:@"#EXT-X-STREAM-INF:"]) {
            isMaster = YES;
            NSDictionary<NSString *, NSString *> *attrs = PDMParseHLSAttributes([line substringFromIndex:18]);
            NSString *uriLine = nil;
            for (NSUInteger j = i + 1; j < lines.count; j++) {
                NSString *cand = [lines[j] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (cand.length == 0) continue;
                if ([cand hasPrefix:@"#"]) continue;
                uriLine = cand;
                i = j;
                break;
            }
            if (uriLine.length > 0) {
                NSURL *resolved = [NSURL URLWithString:uriLine relativeToURL:baseURL].absoluteURL;
                PDMMediaVideoVariant *v = [[PDMMediaVideoVariant alloc] init];
                v.variantID = [NSUUID UUID].UUIDString;
                v.uri = resolved.absoluteString ?: uriLine;
                v.bandwidthBps = [attrs[@"BANDWIDTH"] longLongValue];
                v.fps = [attrs[@"FRAME-RATE"] doubleValue];
                v.audioGroupID = attrs[@"AUDIO"];
                v.codecs = attrs[@"CODECS"];
                NSString *res = attrs[@"RESOLUTION"];
                if (res.length > 0 && [res containsString:@"x"]) {
                    NSArray<NSString *> *dims = [res componentsSeparatedByString:@"x"];
                    if (dims.count == 2) {
                        v.width = [dims[0] integerValue];
                        v.height = [dims[1] integerValue];
                    }
                }
                v.label = PDMQualityLabelForHeight(v.height);
                [media.variants addObject:v];
            }
        } else if ([line hasPrefix:@"#EXTINF:"]) {
            NSString *val = [line substringFromIndex:8];
            NSRange comma = [val rangeOfString:@","];
            if (comma.location != NSNotFound) {
                val = [val substringToIndex:comma.location];
            }
            totalDuration += val.doubleValue;
        }
    }

    if (totalDuration > 0.0) {
        media.durationSeconds = totalDuration;
    }

    // Sort variants highest resolution/bandwidth first
    [media.variants sortUsingComparator:^NSComparisonResult(PDMMediaVideoVariant *a, PDMMediaVideoVariant *b) {
        if (a.height != b.height) return (a.height > b.height) ? NSOrderedAscending : NSOrderedDescending;
        if (a.bandwidthBps != b.bandwidthBps) return (a.bandwidthBps > b.bandwidthBps) ? NSOrderedAscending : NSOrderedDescending;
        return NSOrderedSame;
    }];

    if (!isMaster && media.variants.count == 0) {
        PDMMediaVideoVariant *orig = [[PDMMediaVideoVariant alloc] init];
        orig.variantID = [NSUUID UUID].UUIDString;
        orig.label = @"Original";
        orig.uri = media.urlString;
        [media.variants addObject:orig];
    }

    // Always append an Audio Only option
    PDMMediaVideoVariant *audioOnly = [[PDMMediaVideoVariant alloc] init];
    audioOnly.variantID = @"audio_only";
    audioOnly.label = @"Audio Only";
    audioOnly.isAudioOnly = YES;
    audioOnly.uri = (media.audioTracks.firstObject.uri.length > 0) ? media.audioTracks.firstObject.uri : media.urlString;
    [media.variants addObject:audioOnly];

    if (media.audioTracks.count == 0) {
        PDMMediaAudioTrack *def = [[PDMMediaAudioTrack alloc] init];
        def.trackID = @"default_audio";
        def.name = @"Default Audio";
        def.language = @"und";
        def.channels = @"2";
        def.isDefault = YES;
        def.trackIndex = 0;
        [media.audioTracks addObject:def];
    }
}

+ (void)inspectMedia:(PDMDetectedMedia *)media completion:(void (^)(PDMDetectedMedia *inspected))completion {
    if (!media) {
        if (completion) completion(media);
        return;
    }
    NSURL *url = [NSURL URLWithString:media.urlString];
    if (!url) {
        media.isInspected = YES;
        if (completion) completion(media);
        return;
    }

    NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
    if (media.referer.length > 0) headers[@"Referer"] = media.referer;
    if (media.userAgent.length > 0) headers[@"User-Agent"] = media.userAgent;
    if (media.cookieHeader.length > 0) headers[@"Cookie"] = media.cookieHeader;

    if (media.isHLS) {
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
        req.timeoutInterval = 12.0;
        for (NSString *k in headers) {
            [req setValue:headers[k] forHTTPHeaderField:k];
        }
        [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable __unused response, NSError * _Nullable __unused error) {
            if (data.length > 0) {
                NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (text.length > 0) {
                    [self parseHLSPlaylistText:text baseURL:url intoMedia:media];
                }
            }
            if (media.variants.count == 0) {
                PDMMediaVideoVariant *orig = [[PDMMediaVideoVariant alloc] init];
                orig.variantID = @"orig";
                orig.label = @"Original";
                orig.uri = media.urlString;
                [media.variants addObject:orig];
            }
            media.isInspected = YES;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(media);
            });
        }] resume];
        return;
    }

    // Direct file probe + AVURLAsset multi-audio inspection
    NSMutableURLRequest *headReq = [NSMutableURLRequest requestWithURL:url];
    headReq.HTTPMethod = @"HEAD";
    headReq.timeoutInterval = 10.0;
    for (NSString *k in headers) {
        [headReq setValue:headers[k] forHTTPHeaderField:k];
    }

    [[[NSURLSession sharedSession] dataTaskWithRequest:headReq completionHandler:^(NSData * _Nullable __unused data, NSURLResponse * _Nullable response, NSError * _Nullable __unused error) {
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
            if (http.expectedContentLength > 0) {
                media.contentLength = http.expectedContentLength;
            }
            if (http.MIMEType.length > 0) {
                media.mimeType = http.MIMEType;
            }
        }

        // Inspect audio tracks & video resolution asynchronously with AVURLAsset
        NSDictionary *assetOpts = (headers.count > 0) ? @{ @"AVURLAssetHTTPHeaderFieldsKey": headers } : nil;
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:assetOpts];

        dispatch_group_t grp = dispatch_group_create();
        dispatch_group_enter(grp);
        [asset loadTracksWithMediaType:AVMediaTypeVideo completionHandler:^(NSArray<AVAssetTrack *> * _Nullable tracks, NSError * _Nullable __unused err) {
            if (tracks.count > 0) {
                AVAssetTrack *vt = tracks.firstObject;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                CGSize nat = vt.naturalSize;
                float fps = vt.nominalFrameRate;
                float estRate = vt.estimatedDataRate;
                CMTime dur = asset.duration;
#pragma clang diagnostic pop
                if (CMTIME_IS_NUMERIC(dur)) {
                    media.durationSeconds = CMTimeGetSeconds(dur);
                }
                NSInteger h = (NSInteger)llround(fabs(nat.height));
                NSInteger w = (NSInteger)llround(fabs(nat.width));
                PDMMediaVideoVariant *orig = [[PDMMediaVideoVariant alloc] init];
                orig.variantID = @"orig";
                orig.label = (h > 0) ? [NSString stringWithFormat:@"%@ (Original)", PDMQualityLabelForHeight(h)] : @"Original";
                orig.width = w;
                orig.height = h;
                orig.fps = (double)fps;
                orig.bandwidthBps = (int64_t)estRate;
                orig.estimatedBytes = media.contentLength;
                orig.uri = media.urlString;
                [media.variants addObject:orig];
            }
            dispatch_group_leave(grp);
        }];

        dispatch_group_enter(grp);
        [asset loadTracksWithMediaType:AVMediaTypeAudio completionHandler:^(NSArray<AVAssetTrack *> * _Nullable tracks, NSError * _Nullable __unused err) {
            for (NSUInteger i = 0; i < tracks.count; i++) {
                AVAssetTrack *at = tracks[i];
                PDMMediaAudioTrack *t = [[PDMMediaAudioTrack alloc] init];
                t.trackID = [NSString stringWithFormat:@"track_%lu", (unsigned long)i];
                t.trackIndex = (NSInteger)i;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                NSString *lang = at.extendedLanguageTag ?: at.languageCode;
                float rate = at.estimatedDataRate;
#pragma clang diagnostic pop
                t.language = lang ?: @"und";
                NSString *disp = lang.length > 0 ? [[NSLocale currentLocale] localizedStringForLanguageCode:lang] : nil;
                t.name = (disp.length > 0) ? disp.capitalizedString : [NSString stringWithFormat:@"Audio Track %lu", (unsigned long)(i + 1)];
                t.bitrateKbps = (rate > 1000.0f) ? (NSInteger)(rate / 1000.0f) : 192;
                t.channels = @"2";
                t.isDefault = (i == 0);
                [media.audioTracks addObject:t];
            }
            dispatch_group_leave(grp);
        }];

        dispatch_group_notify(grp, dispatch_get_main_queue(), ^{
            if (media.variants.count == 0) {
                PDMMediaVideoVariant *orig = [[PDMMediaVideoVariant alloc] init];
                orig.variantID = @"orig";
                orig.label = @"Original";
                orig.estimatedBytes = media.contentLength;
                orig.uri = media.urlString;
                [media.variants addObject:orig];
            }
            PDMMediaVideoVariant *audioOnly = [[PDMMediaVideoVariant alloc] init];
            audioOnly.variantID = @"audio_only";
            audioOnly.label = @"Audio Only";
            audioOnly.isAudioOnly = YES;
            audioOnly.uri = media.urlString;
            [media.variants addObject:audioOnly];

            if (media.audioTracks.count == 0) {
                PDMMediaAudioTrack *def = [[PDMMediaAudioTrack alloc] init];
                def.trackID = @"default_audio";
                def.name = @"Default Audio";
                def.language = @"und";
                def.channels = @"2";
                def.isDefault = YES;
                def.trackIndex = 0;
                [media.audioTracks addObject:def];
            }
            media.isInspected = YES;
            if (completion) completion(media);
        });
    }] resume];
}

@end

#pragma mark - PDMMediaPickerSheetViewController

@interface PDMMediaPickerSheetViewController ()
@property (nonatomic, strong) PDMMediaFormatConfig *config;
@property (nonatomic, strong, nullable) PDMMediaVideoVariant *selectedVariant;
@property (nonatomic, strong, nullable) PDMMediaAudioTrack *selectedAudioTrack;
@property (nonatomic, strong) UITextField *filenameField;
@property (nonatomic, strong) UILabel *specsLabel;
@property (nonatomic, strong) UIActivityIndicatorView *inspectSpinner;
@property (nonatomic, strong) UIStackView *qualityRowsStack;
@property (nonatomic, strong) UIStackView *audioTrackRowsStack;
@property (nonatomic, strong) UIStackView *audioBitrateRow;
@property (nonatomic, strong) UIStackView *formatModeRow;
@property (nonatomic, strong) UIStackView *videoStudioStack;
@property (nonatomic, strong) UIStackView *audioStudioStack;
@property (nonatomic, strong) UIStackView *destinationRow;
@property (nonatomic, strong) UIStackView *segmentsRow;
@property (nonatomic, strong) PDMGlassView *studioContentCard;
@property (nonatomic, assign) BOOL studioExpanded;
@property (nonatomic, strong) PDMGlassPillButton *studioToggleBtn;
@end

@implementation PDMMediaPickerSheetViewController

- (void)viewDidLoad {
    self.sheetTitle = self.studioOnlyMode ? @"Format & Encoding Studio" : @"Media Grabber";
    self.sheetSubtitle = self.media.sourceBadge ? [NSString stringWithFormat:@"%@ · Liquid Glass Studio", self.media.sourceBadge] : @"Quality, Multi-Audio & Format";
    self.sheetSymbolName = self.studioOnlyMode ? @"wand.and.stars" : @"arrow.down.circle.fill";
    self.allowsMediumDetent = YES;
    self.prefersLargeDefaultDetent = YES;
    [super viewDidLoad];

    self.config = [PDMMediaFormatConfig defaultConfig];
    self.studioExpanded = YES;
    [self showBottomBar:YES];
    [self buildUI];

    if (!self.media.isInspected && !self.studioOnlyMode) {
        [self.inspectSpinner startAnimating];
        __weak typeof(self) weakSelf = self;
        [PDMMediaSniffer inspectMedia:self.media completion:^(PDMDetectedMedia *__unused inspected) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf.inspectSpinner stopAnimating];
            [strongSelf refreshDynamicSections];
        }];
    } else {
        [self refreshDynamicSections];
    }
}

- (UIView *)wrappedChipGridWithChips:(NSArray<PDMGlassChip *> *)chips perRow:(NSInteger)perRow {
    UIStackView *vStack = [[UIStackView alloc] init];
    vStack.axis = UILayoutConstraintAxisVertical;
    vStack.spacing = 8.0;

    NSInteger cols = MAX(1, perRow);
    NSUInteger idx = 0;
    while (idx < chips.count) {
        UIStackView *row = [[UIStackView alloc] init];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.spacing = 8.0;
        row.distribution = UIStackViewDistributionFillEqually;
        for (NSInteger c = 0; c < cols; c++) {
            if (idx < chips.count) {
                [row addArrangedSubview:chips[idx]];
                idx++;
            } else {
                UIView *spacer = [[UIView alloc] init];
                spacer.userInteractionEnabled = NO;
                [row addArrangedSubview:spacer];
            }
        }
        [vStack addArrangedSubview:row];
    }
    return vStack;
}

- (void)buildUI {
    PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;

    // Header Glass Card
    PDMGlassView *headerCard = [[PDMGlassView alloc] initWithCornerRadius:20.0 elevated:YES];
    headerCard.customBorderColor = [spec.mediaGlowColor colorWithAlphaComponent:0.45];

    UIStackView *hCardStack = [[UIStackView alloc] init];
    hCardStack.axis = UILayoutConstraintAxisVertical;
    hCardStack.spacing = 10.0;
    hCardStack.translatesAutoresizingMaskIntoConstraints = NO;
    [headerCard.contentView addSubview:hCardStack];

    UIStackView *topRow = [[UIStackView alloc] init];
    topRow.axis = UILayoutConstraintAxisHorizontal;
    topRow.alignment = UIStackViewAlignmentCenter;
    topRow.spacing = 8.0;

    UILabel *badge = [[UILabel alloc] init];
    badge.text = [NSString stringWithFormat:@"  %@  ", self.media.sourceBadge ?: @"MEDIA"];
    badge.font = [[PDMThemeManager sharedManager] tabularFontOfSize:11.0 weight:UIFontWeightHeavy];
    badge.textColor = [UIColor blackColor];
    badge.backgroundColor = spec.mediaGlowColor;
    badge.clipsToBounds = YES;
    badge.layer.cornerRadius = 8.0;
    [badge.heightAnchor constraintEqualToConstant:22.0].active = YES;
    [badge setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [topRow addArrangedSubview:badge];

    UILabel *titleLbl = [[UILabel alloc] init];
    titleLbl.text = self.media.title ?: @"Detected Media";
    titleLbl.font = [[PDMThemeManager sharedManager] displayFontOfSize:15.5 weight:UIFontWeightBold];
    titleLbl.textColor = spec.primaryTextColor;
    titleLbl.numberOfLines = 2;
    [topRow addArrangedSubview:titleLbl];

    self.inspectSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.inspectSpinner.color = spec.accentColor;
    self.inspectSpinner.hidesWhenStopped = YES;
    [topRow addArrangedSubview:self.inspectSpinner];

    [hCardStack addArrangedSubview:topRow];

    self.specsLabel = [[UILabel alloc] init];
    self.specsLabel.font = [[PDMThemeManager sharedManager] tabularFontOfSize:12.0 weight:UIFontWeightMedium];
    self.specsLabel.textColor = spec.secondaryTextColor;
    self.specsLabel.text = @"Inspecting stream specs & audio tracks...";
    [hCardStack addArrangedSubview:self.specsLabel];

    // Editable filename pill + Stream Preview button
    UIStackView *fileRow = [[UIStackView alloc] init];
    fileRow.axis = UILayoutConstraintAxisHorizontal;
    fileRow.spacing = 8.0;
    fileRow.alignment = UIStackViewAlignmentCenter;

    PDMGlassView *namePill = [[PDMGlassView alloc] initWithCornerRadius:12.0 elevated:NO];
    namePill.showAmbientShadow = NO;
    self.filenameField = [[UITextField alloc] init];
    self.filenameField.translatesAutoresizingMaskIntoConstraints = NO;
    self.filenameField.text = self.media.filename;
    self.filenameField.placeholder = @"Filename";
    self.filenameField.textColor = spec.primaryTextColor;
    self.filenameField.tintColor = spec.accentColor;
    self.filenameField.font = [[PDMThemeManager sharedManager] bodyFontOfSize:13.5 weight:UIFontWeightMedium];
    self.filenameField.clearButtonMode = UITextFieldViewModeWhileEditing;
    [namePill.contentView addSubview:self.filenameField];
    [NSLayoutConstraint activateConstraints:@[
        [self.filenameField.topAnchor constraintEqualToAnchor:namePill.contentView.topAnchor constant:8.0],
        [self.filenameField.bottomAnchor constraintEqualToAnchor:namePill.contentView.bottomAnchor constant:-8.0],
        [self.filenameField.leadingAnchor constraintEqualToAnchor:namePill.contentView.leadingAnchor constant:10.0],
        [self.filenameField.trailingAnchor constraintEqualToAnchor:namePill.contentView.trailingAnchor constant:-10.0]
    ]];
    [fileRow addArrangedSubview:namePill];

    if (!self.studioOnlyMode) {
        PDMGlassPillButton *previewBtn = [[PDMGlassPillButton alloc] initWithTitle:@"Preview" symbolName:@"play.fill"];
        previewBtn.glowing = YES;
        previewBtn.customAccentColor = spec.accentColor;
        previewBtn.horizontalPadding = 12.0;
        previewBtn.verticalPadding = 9.0;
        [previewBtn setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [previewBtn addTarget:self action:@selector(handlePreviewTap) forControlEvents:UIControlEventTouchUpInside];
        [fileRow addArrangedSubview:previewBtn];
    }
    [hCardStack addArrangedSubview:fileRow];

    [NSLayoutConstraint activateConstraints:@[
        [hCardStack.topAnchor constraintEqualToAnchor:headerCard.contentView.topAnchor constant:14.0],
        [hCardStack.bottomAnchor constraintEqualToAnchor:headerCard.contentView.bottomAnchor constant:-14.0],
        [hCardStack.leadingAnchor constraintEqualToAnchor:headerCard.contentView.leadingAnchor constant:14.0],
        [hCardStack.trailingAnchor constraintEqualToAnchor:headerCard.contentView.trailingAnchor constant:-14.0]
    ]];
    [self.contentStack addArrangedSubview:headerCard];

    // Section 1: Video Quality Pill Grid (when not studio-only)
    if (!self.studioOnlyMode) {
        [self.contentStack addArrangedSubview:[self sectionHeaderWithTitle:@"1. Video Quality" detail:@"Tap to select stream"]];
        self.qualityRowsStack = [[UIStackView alloc] init];
        self.qualityRowsStack.axis = UILayoutConstraintAxisVertical;
        self.qualityRowsStack.spacing = 8.0;
        [self.contentStack addArrangedSubview:self.qualityRowsStack];
    }

    // Section 2: Multi-Audio Track & Audio Quality Selector
    [self.contentStack addArrangedSubview:[self sectionHeaderWithTitle:self.studioOnlyMode ? @"1. Audio Track & Bitrate" : @"2. Multi-Audio Track & Quality" detail:@"Language & Bitrate"]];
    self.audioTrackRowsStack = [[UIStackView alloc] init];
    self.audioTrackRowsStack.axis = UILayoutConstraintAxisVertical;
    self.audioTrackRowsStack.spacing = 8.0;
    [self.contentStack addArrangedSubview:self.audioTrackRowsStack];

    self.audioBitrateRow = [[UIStackView alloc] init];
    self.audioBitrateRow.axis = UILayoutConstraintAxisVertical;
    self.audioBitrateRow.spacing = 8.0;
    [self.contentStack addArrangedSubview:self.audioBitrateRow];

    // Section 3: Format & Encoding Studio Card
    UIStackView *studioHeader = [[UIStackView alloc] init];
    studioHeader.axis = UILayoutConstraintAxisHorizontal;
    studioHeader.alignment = UIStackViewAlignmentCenter;
    [studioHeader addArrangedSubview:[self sectionHeaderWithTitle:self.studioOnlyMode ? @"2. Format & Encoding Studio" : @"3. Format & Encoding Studio" detail:nil]];
    self.studioToggleBtn = [[PDMGlassPillButton alloc] initWithTitle:@"Hide" symbolName:@"chevron.up"];
    self.studioToggleBtn.horizontalPadding = 10.0;
    self.studioToggleBtn.verticalPadding = 5.0;
    [self.studioToggleBtn addTarget:self action:@selector(handleToggleStudio) forControlEvents:UIControlEventTouchUpInside];
    [studioHeader addArrangedSubview:self.studioToggleBtn];
    [self.contentStack addArrangedSubview:studioHeader];

    self.studioContentCard = [[PDMGlassView alloc] initWithCornerRadius:20.0 elevated:NO];
    self.studioContentCard.showAmbientShadow = NO;
    UIStackView *studioStack = [[UIStackView alloc] init];
    studioStack.axis = UILayoutConstraintAxisVertical;
    studioStack.spacing = 12.0;
    studioStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.studioContentCard.contentView addSubview:studioStack];
    [NSLayoutConstraint activateConstraints:@[
        [studioStack.topAnchor constraintEqualToAnchor:self.studioContentCard.contentView.topAnchor constant:14.0],
        [studioStack.bottomAnchor constraintEqualToAnchor:self.studioContentCard.contentView.bottomAnchor constant:-14.0],
        [studioStack.leadingAnchor constraintEqualToAnchor:self.studioContentCard.contentView.leadingAnchor constant:14.0],
        [studioStack.trailingAnchor constraintEqualToAnchor:self.studioContentCard.contentView.trailingAnchor constant:-14.0]
    ]];

    self.formatModeRow = [[UIStackView alloc] init];
    self.formatModeRow.axis = UILayoutConstraintAxisHorizontal;
    self.formatModeRow.spacing = 6.0;
    self.formatModeRow.distribution = UIStackViewDistributionFillEqually;
    [studioStack addArrangedSubview:self.formatModeRow];

    self.videoStudioStack = [[UIStackView alloc] init];
    self.videoStudioStack.axis = UILayoutConstraintAxisVertical;
    self.videoStudioStack.spacing = 10.0;
    [studioStack addArrangedSubview:self.videoStudioStack];

    self.audioStudioStack = [[UIStackView alloc] init];
    self.audioStudioStack.axis = UILayoutConstraintAxisVertical;
    self.audioStudioStack.spacing = 10.0;
    [studioStack addArrangedSubview:self.audioStudioStack];

    if (!self.studioOnlyMode) {
        [studioStack addArrangedSubview:[self sectionHeaderWithTitle:@"Destination Folder" detail:nil]];
        self.destinationRow = [[UIStackView alloc] init];
        self.destinationRow.axis = UILayoutConstraintAxisVertical;
        self.destinationRow.spacing = 8.0;
        [studioStack addArrangedSubview:self.destinationRow];

        [studioStack addArrangedSubview:[self sectionHeaderWithTitle:@"Parallel Download Segments" detail:@"IDM Multi-Part"]];
        self.segmentsRow = [[UIStackView alloc] init];
        self.segmentsRow.axis = UILayoutConstraintAxisHorizontal;
        self.segmentsRow.spacing = 8.0;
        self.segmentsRow.distribution = UIStackViewDistributionFillEqually;
        [studioStack addArrangedSubview:self.segmentsRow];
    }

    [self.contentStack addArrangedSubview:self.studioContentCard];

    // Pinned Bottom Action Bar
    if (self.studioOnlyMode) {
        PDMGlassPillButton *convertBtn = [[PDMGlassPillButton alloc] initWithTitle:@"Start Conversion" symbolName:@"wand.and.stars"];
        convertBtn.prominentAccent = YES;
        convertBtn.verticalPadding = 13.0;
        [convertBtn addTarget:self action:@selector(handleDownloadNowTap) forControlEvents:UIControlEventTouchUpInside];
        [self.bottomBarStack addArrangedSubview:convertBtn];
    } else {
        PDMGlassPillButton *queueBtn = [[PDMGlassPillButton alloc] initWithTitle:@"Add to Queue" symbolName:@"text.badge.plus"];
        queueBtn.verticalPadding = 13.0;
        [queueBtn addTarget:self action:@selector(handleAddToQueueTap) forControlEvents:UIControlEventTouchUpInside];
        [self.bottomBarStack addArrangedSubview:queueBtn];

        PDMGlassPillButton *dlBtn = [[PDMGlassPillButton alloc] initWithTitle:@"Download Now" symbolName:@"arrow.down.circle.fill"];
        dlBtn.prominentAccent = YES;
        dlBtn.verticalPadding = 13.0;
        [dlBtn addTarget:self action:@selector(handleDownloadNowTap) forControlEvents:UIControlEventTouchUpInside];
        [self.bottomBarStack addArrangedSubview:dlBtn];
    }

    [self rebuildStudioControls];
}

- (void)clearStack:(UIStackView *)stack {
    for (UIView *v in [stack.arrangedSubviews copy]) {
        [stack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
}

- (void)refreshDynamicSections {
    if (!self.selectedVariant && self.media.variants.count > 0) {
        self.selectedVariant = self.media.variants.firstObject;
    }
    if (!self.selectedAudioTrack && self.media.audioTracks.count > 0) {
        for (PDMMediaAudioTrack *t in self.media.audioTracks) {
            if (t.isDefault) {
                self.selectedAudioTrack = t;
                break;
            }
        }
        if (!self.selectedAudioTrack) {
            self.selectedAudioTrack = self.media.audioTracks.firstObject;
        }
    }

    // Update header specs text
    NSMutableArray<NSString *> *specs = [NSMutableArray array];
    if (self.media.isDRMProtected) {
        [specs addObject:@"DRM Protected (FairPlay)"];
    } else if (self.media.isAES128Encrypted) {
        [specs addObject:@"AES-128 Clear-Key"];
    }
    if (self.selectedVariant.height > 0) {
        [specs addObject:[NSString stringWithFormat:@"%ld×%ld", (long)self.selectedVariant.width, (long)self.selectedVariant.height]];
    }
    if (self.selectedVariant.fps > 1.0) {
        [specs addObject:[NSString stringWithFormat:@"%.0f FPS", self.selectedVariant.fps]];
    }
    if (self.media.durationSeconds > 1.0) {
        [specs addObject:[PDMThemeManager formatDuration:self.media.durationSeconds]];
    }
    if (self.media.contentLength > 0) {
        [specs addObject:[PDMThemeManager formatBytes:self.media.contentLength]];
    }
    [specs addObject:[NSString stringWithFormat:@"%lu Audio Track%@", (unsigned long)MAX((NSUInteger)1, self.media.audioTracks.count), self.media.audioTracks.count == 1 ? @"" : @"s"]];
    self.specsLabel.text = [specs componentsJoinedByString:@" · "];

    if (self.media.isDRMProtected) {
        [PDMToastBanner showInView:self.view
                           message:@"FairPlay DRM stream detected — offline saving is restricted by content owner."
                        symbolName:@"lock.trianglebadge.exclamationmark.fill"
                       accentColor:[PDMThemeManager sharedManager].currentSpec.warningColor];
    }

    // Rebuild Video Quality Grid
    if (self.qualityRowsStack) {
        [self clearStack:self.qualityRowsStack];
        NSMutableArray<PDMGlassChip *> *qChips = [NSMutableArray array];
        for (NSUInteger i = 0; i < self.media.variants.count; i++) {
            PDMMediaVideoVariant *v = self.media.variants[i];
            PDMGlassChip *chip = [[PDMGlassChip alloc] initWithTitle:v.label subtitle:[v specSubtitle]];
            chip.tag = (NSInteger)i;
            chip.chipSelected = (v == self.selectedVariant);
            if (v.isAudioOnly) {
                chip.symbolName = @"waveform";
            }
            [chip addTarget:self action:@selector(handleVariantChipTap:) forControlEvents:UIControlEventTouchUpInside];
            [qChips addObject:chip];
        }
        if (qChips.count > 0) {
            [self.qualityRowsStack addArrangedSubview:[self wrappedChipGridWithChips:qChips perRow:2]];
        }
    }

    // Rebuild Multi-Audio Tracks
    [self clearStack:self.audioTrackRowsStack];
    NSMutableArray<PDMGlassChip *> *aChips = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.media.audioTracks.count; i++) {
        PDMMediaAudioTrack *t = self.media.audioTracks[i];
        NSString *sub = (t.language.length > 0 && ![t.language isEqualToString:@"und"]) ? t.language.uppercaseString : (t.isDefault ? @"Default" : @"Track");
        PDMGlassChip *chip = [[PDMGlassChip alloc] initWithTitle:[t displayLabel] subtitle:sub];
        chip.symbolName = @"speaker.wave.2.fill";
        chip.tag = (NSInteger)i;
        chip.chipSelected = (t == self.selectedAudioTrack);
        [chip addTarget:self action:@selector(handleAudioTrackChipTap:) forControlEvents:UIControlEventTouchUpInside];
        [aChips addObject:chip];
    }
    if (aChips.count > 0) {
        [self.audioTrackRowsStack addArrangedSubview:[self wrappedChipGridWithChips:aChips perRow:2]];
    }

    // Rebuild Audio Bitrate chips
    [self clearStack:self.audioBitrateRow];
    NSArray<NSNumber *> *bitrates = @[@320, @256, @192, @128, @96, @64];
    NSMutableArray<PDMGlassChip *> *brChips = [NSMutableArray array];
    for (NSNumber *br in bitrates) {
        PDMGlassChip *c = [[PDMGlassChip alloc] initWithTitle:[NSString stringWithFormat:@"%ld kbps", (long)br.integerValue] subtitle:nil];
        c.tag = br.integerValue;
        c.chipSelected = (self.config.audioBitrateKbps == br.integerValue);
        [c addTarget:self action:@selector(handleBitrateChipTap:) forControlEvents:UIControlEventTouchUpInside];
        [brChips addObject:c];
    }
    [self.audioBitrateRow addArrangedSubview:[self wrappedChipGridWithChips:brChips perRow:3]];

    [self rebuildStudioControls];
}

- (void)rebuildStudioControls {
    [self clearStack:self.formatModeRow];
    NSArray<NSString *> *modes = self.studioOnlyMode
        ? @[@"Video Format", @"Audio Only"]
        : @[@"Original", @"Video Format", @"Audio Only"];
    for (NSUInteger i = 0; i < modes.count; i++) {
        NSInteger modeVal = self.studioOnlyMode ? (NSInteger)(i + 1) : (NSInteger)i;
        if (self.studioOnlyMode && self.config.outputMode == PDMOutputModeOriginal) {
            self.config.outputMode = PDMOutputModeVideo;
        }
        PDMGlassChip *c = [[PDMGlassChip alloc] initWithTitle:modes[i] subtitle:nil];
        c.tag = modeVal;
        c.chipSelected = ((NSInteger)self.config.outputMode == modeVal);
        [c addTarget:self action:@selector(handleOutputModeTap:) forControlEvents:UIControlEventTouchUpInside];
        [self.formatModeRow addArrangedSubview:c];
    }

    // Video Format Studio
    [self clearStack:self.videoStudioStack];
    self.videoStudioStack.hidden = (self.config.outputMode != PDMOutputModeVideo);
    if (self.config.outputMode == PDMOutputModeVideo) {
        NSArray<NSString *> *vNames = @[@"MP4 (H.264)", @"MP4 (HEVC)", @"MOV (H.264)", @"MOV (HEVC)", @"M4V (H.264)"];
        NSMutableArray<PDMGlassChip *> *vChips = [NSMutableArray array];
        for (NSUInteger i = 0; i < vNames.count; i++) {
            PDMGlassChip *c = [[PDMGlassChip alloc] initWithTitle:vNames[i] subtitle:nil];
            c.tag = (NSInteger)i;
            c.chipSelected = ((NSInteger)self.config.videoFormat == (NSInteger)i);
            [c addTarget:self action:@selector(handleVideoFormatTap:) forControlEvents:UIControlEventTouchUpInside];
            [vChips addObject:c];
        }
        [self.videoStudioStack addArrangedSubview:[self wrappedChipGridWithChips:vChips perRow:2]];

        [self.videoStudioStack addArrangedSubview:[self sectionHeaderWithTitle:@"Target Resolution" detail:nil]];
        NSArray<NSString *> *resNames = @[@"Original", @"1080p", @"720p", @"480p"];
        NSMutableArray<PDMGlassChip *> *rChips = [NSMutableArray array];
        for (NSUInteger i = 0; i < resNames.count; i++) {
            PDMGlassChip *c = [[PDMGlassChip alloc] initWithTitle:resNames[i] subtitle:nil];
            c.tag = (NSInteger)i;
            c.chipSelected = ((NSInteger)self.config.targetResolution == (NSInteger)i);
            [c addTarget:self action:@selector(handleTargetResTap:) forControlEvents:UIControlEventTouchUpInside];
            [rChips addObject:c];
        }
        [self.videoStudioStack addArrangedSubview:[self wrappedChipGridWithChips:rChips perRow:4]];

        [self.videoStudioStack addArrangedSubview:[self sectionHeaderWithTitle:@"Encoding Quality" detail:nil]];
        NSArray<NSString *> *qNames = @[@"High", @"Balanced", @"Compact"];
        NSMutableArray<PDMGlassChip *> *pChips = [NSMutableArray array];
        for (NSUInteger i = 0; i < qNames.count; i++) {
            PDMGlassChip *c = [[PDMGlassChip alloc] initWithTitle:qNames[i] subtitle:nil];
            c.tag = (NSInteger)i;
            c.chipSelected = ((NSInteger)self.config.qualityPreset == (NSInteger)i);
            [c addTarget:self action:@selector(handleQualityPresetTap:) forControlEvents:UIControlEventTouchUpInside];
            [pChips addObject:c];
        }
        [self.videoStudioStack addArrangedSubview:[self wrappedChipGridWithChips:pChips perRow:3]];
    }

    // Audio Format Studio
    [self clearStack:self.audioStudioStack];
    self.audioStudioStack.hidden = (self.config.outputMode != PDMOutputModeAudioOnly);
    if (self.config.outputMode == PDMOutputModeAudioOnly) {
        NSArray<NSString *> *aNames = @[@"MP3", @"M4A (AAC)", @"M4A (ALAC)", @"FLAC", @"WAV"];
        NSMutableArray<PDMGlassChip *> *afChips = [NSMutableArray array];
        for (NSUInteger i = 0; i < aNames.count; i++) {
            PDMGlassChip *c = [[PDMGlassChip alloc] initWithTitle:aNames[i] subtitle:nil];
            c.tag = (NSInteger)i;
            c.chipSelected = ((NSInteger)self.config.audioFormat == (NSInteger)i);
            [c addTarget:self action:@selector(handleAudioFormatTap:) forControlEvents:UIControlEventTouchUpInside];
            [afChips addObject:c];
        }
        [self.audioStudioStack addArrangedSubview:[self wrappedChipGridWithChips:afChips perRow:3]];
    }

    // Destination & Segments
    if (self.destinationRow) {
        [self clearStack:self.destinationRow];
        NSArray<NSString *> *dests = @[@"Auto", @"Videos", @"Audio", @"Private Vault"];
        NSMutableArray<PDMGlassChip *> *dChips = [NSMutableArray array];
        for (NSUInteger i = 0; i < dests.count; i++) {
            PDMGlassChip *c = [[PDMGlassChip alloc] initWithTitle:dests[i] subtitle:nil];
            c.tag = (NSInteger)i;
            c.chipSelected = [self.config.destinationCategory isEqualToString:dests[i]];
            [c addTarget:self action:@selector(handleDestinationTap:) forControlEvents:UIControlEventTouchUpInside];
            [dChips addObject:c];
        }
        [self.destinationRow addArrangedSubview:[self wrappedChipGridWithChips:dChips perRow:2]];
    }

    if (self.segmentsRow) {
        [self clearStack:self.segmentsRow];
        NSArray<NSNumber *> *segs = @[@2, @4, @8, @16];
        for (NSNumber *n in segs) {
            PDMGlassChip *c = [[PDMGlassChip alloc] initWithTitle:[NSString stringWithFormat:@"%ld Parts", (long)n.integerValue] subtitle:nil];
            c.tag = n.integerValue;
            c.chipSelected = (self.config.segmentCount == n.integerValue);
            [c addTarget:self action:@selector(handleSegmentChipTap:) forControlEvents:UIControlEventTouchUpInside];
            [self.segmentsRow addArrangedSubview:c];
        }
    }
}

#pragma mark - Actions

- (void)handleToggleStudio {
    [[PDMThemeManager sharedManager] triggerLightImpact];
    self.studioExpanded = !self.studioExpanded;
    self.studioContentCard.hidden = !self.studioExpanded;
    self.studioToggleBtn.titleText = self.studioExpanded ? @"Hide" : @"Expand";
    self.studioToggleBtn.symbolName = self.studioExpanded ? @"chevron.up" : @"chevron.down";
}

- (void)handleVariantChipTap:(PDMGlassChip *)sender {
    [[PDMThemeManager sharedManager] triggerSelectionHaptic];
    NSInteger idx = sender.tag;
    if (idx >= 0 && idx < (NSInteger)self.media.variants.count) {
        self.selectedVariant = self.media.variants[(NSUInteger)idx];
        if (self.selectedVariant.isAudioOnly) {
            self.config.outputMode = PDMOutputModeAudioOnly;
        }
        [self refreshDynamicSections];
    }
}

- (void)handleAudioTrackChipTap:(PDMGlassChip *)sender {
    [[PDMThemeManager sharedManager] triggerSelectionHaptic];
    NSInteger idx = sender.tag;
    if (idx >= 0 && idx < (NSInteger)self.media.audioTracks.count) {
        self.selectedAudioTrack = self.media.audioTracks[(NSUInteger)idx];
        self.config.selectedAudioTrackIndex = self.selectedAudioTrack.trackIndex;
        [self refreshDynamicSections];
    }
}

- (void)handleBitrateChipTap:(PDMGlassChip *)sender {
    [[PDMThemeManager sharedManager] triggerSelectionHaptic];
    self.config.audioBitrateKbps = sender.tag;
    [self refreshDynamicSections];
}

- (void)handleOutputModeTap:(PDMGlassChip *)sender {
    [[PDMThemeManager sharedManager] triggerSelectionHaptic];
    self.config.outputMode = (PDMOutputMode)sender.tag;
    [self syncFilenameExtension];
    [self rebuildStudioControls];
}

- (void)handleVideoFormatTap:(PDMGlassChip *)sender {
    [[PDMThemeManager sharedManager] triggerSelectionHaptic];
    self.config.videoFormat = (PDMVideoFormat)sender.tag;
    [self syncFilenameExtension];
    [self rebuildStudioControls];
}

- (void)handleTargetResTap:(PDMGlassChip *)sender {
    [[PDMThemeManager sharedManager] triggerSelectionHaptic];
    self.config.targetResolution = (PDMTargetResolution)sender.tag;
    [self rebuildStudioControls];
}

- (void)handleQualityPresetTap:(PDMGlassChip *)sender {
    [[PDMThemeManager sharedManager] triggerSelectionHaptic];
    self.config.qualityPreset = (PDMVideoQualityPreset)sender.tag;
    [self rebuildStudioControls];
}

- (void)handleAudioFormatTap:(PDMGlassChip *)sender {
    [[PDMThemeManager sharedManager] triggerSelectionHaptic];
    self.config.audioFormat = (PDMAudioFormat)sender.tag;
    [self syncFilenameExtension];
    [self rebuildStudioControls];
}

- (void)handleDestinationTap:(PDMGlassChip *)sender {
    [[PDMThemeManager sharedManager] triggerSelectionHaptic];
    NSArray<NSString *> *dests = @[@"Auto", @"Videos", @"Audio", @"Private Vault"];
    if (sender.tag >= 0 && sender.tag < (NSInteger)dests.count) {
        self.config.destinationCategory = dests[(NSUInteger)sender.tag];
        [self rebuildStudioControls];
    }
}

- (void)handleSegmentChipTap:(PDMGlassChip *)sender {
    [[PDMThemeManager sharedManager] triggerSelectionHaptic];
    self.config.segmentCount = sender.tag;
    [self rebuildStudioControls];
}

- (void)syncFilenameExtension {
    NSString *targetExt = [self.config targetFileExtension];
    if (targetExt.length == 0) return;
    NSString *cur = self.filenameField.text ?: self.media.filename;
    NSString *base = [cur stringByDeletingPathExtension];
    if (base.length == 0) base = @"PrismDM_Media";
    self.filenameField.text = [base stringByAppendingPathExtension:targetExt];
}

- (void)handlePreviewTap {
    [[PDMThemeManager sharedManager] triggerMediumImpact];
    NSString *targetURLStr = (self.selectedVariant.uri.length > 0 && !self.selectedVariant.isAudioOnly)
        ? self.selectedVariant.uri : self.media.urlString;
    NSURL *u = [NSURL URLWithString:targetURLStr];
    if (!u) return;

    NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
    if (self.media.referer.length > 0) headers[@"Referer"] = self.media.referer;
    if (self.media.userAgent.length > 0) headers[@"User-Agent"] = self.media.userAgent;
    if (self.media.cookieHeader.length > 0) headers[@"Cookie"] = self.media.cookieHeader;

    NSString *title = self.media.title ?: @"Stream Preview";
    void (^cb)(NSURL *, NSString *, NSDictionary<NSString *, NSString *> *) = self.onStreamPreviewRequested;
    [self dismissViewControllerAnimated:YES completion:^{
        if (cb) cb(u, title, headers);
    }];
}

- (void)submitWithImmediateStart:(BOOL)startNow {
    if (self.media.isDRMProtected && !self.studioOnlyMode) {
        [[PDMThemeManager sharedManager] triggerWarningHaptic];
        [PDMToastBanner showInView:self.view
                           message:@"Cannot download FairPlay DRM protected stream."
                        symbolName:@"lock.slash.fill"
                       accentColor:[PDMThemeManager sharedManager].currentSpec.dangerColor];
        return;
    }
    [[PDMThemeManager sharedManager] triggerSuccessHaptic];
    NSString *fallbackExt = [self.config targetFileExtension];
    if (fallbackExt.length == 0) {
        fallbackExt = self.media.filename.pathExtension.length > 0 ? self.media.filename.pathExtension : @"mp4";
    }
    NSString *finalName = [PDMThemeManager sanitizeFilename:(self.filenameField.text ?: self.media.filename)
                                          fallbackExtension:fallbackExt];

    PDMDetectedMedia *m = self.media;
    PDMMediaVideoVariant *v = self.selectedVariant;
    PDMMediaAudioTrack *a = self.selectedAudioTrack;
    PDMMediaFormatConfig *cfg = [self.config copy];
    void (^cb)(PDMDetectedMedia *, PDMMediaVideoVariant *, PDMMediaAudioTrack *, PDMMediaFormatConfig *, NSString *, BOOL) = self.onDownloadRequested;

    [self dismissViewControllerAnimated:YES completion:^{
        if (cb) cb(m, v, a, cfg, finalName, startNow);
    }];
}

- (void)handleDownloadNowTap {
    [self submitWithImmediateStart:YES];
}

- (void)handleAddToQueueTap {
    [self submitWithImmediateStart:NO];
}

@end

#pragma mark - PDMResourceGrabberSheetViewController

@interface PDMResourceGrabberSheetViewController ()
@property (nonatomic, copy) NSString *activeFilter;
@property (nonatomic, strong) UIStackView *filterRow;
@property (nonatomic, strong) UIStackView *listStack;
@property (nonatomic, strong) PDMGlassPillButton *downloadBtn;
@end

@implementation PDMResourceGrabberSheetViewController

- (void)viewDidLoad {
    self.sheetTitle = @"Page Resource Grabber";
    self.sheetSubtitle = [NSString stringWithFormat:@"%lu downloadable items found", (unsigned long)self.resources.count];
    self.sheetSymbolName = @"square.stack.3d.down.right.fill";
    self.allowsMediumDetent = YES;
    self.prefersLargeDefaultDetent = YES;
    [super viewDidLoad];

    self.activeFilter = @"All";
    [self showBottomBar:YES];

    UIScrollView *filterScroll = [[UIScrollView alloc] init];
    filterScroll.showsHorizontalScrollIndicator = NO;
    filterScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [filterScroll.heightAnchor constraintEqualToConstant:40.0].active = YES;

    self.filterRow = [[UIStackView alloc] init];
    self.filterRow.axis = UILayoutConstraintAxisHorizontal;
    self.filterRow.spacing = 8.0;
    self.filterRow.translatesAutoresizingMaskIntoConstraints = NO;
    [filterScroll addSubview:self.filterRow];
    [NSLayoutConstraint activateConstraints:@[
        [self.filterRow.topAnchor constraintEqualToAnchor:filterScroll.contentLayoutGuide.topAnchor],
        [self.filterRow.bottomAnchor constraintEqualToAnchor:filterScroll.contentLayoutGuide.bottomAnchor],
        [self.filterRow.leadingAnchor constraintEqualToAnchor:filterScroll.contentLayoutGuide.leadingAnchor],
        [self.filterRow.trailingAnchor constraintEqualToAnchor:filterScroll.contentLayoutGuide.trailingAnchor],
        [self.filterRow.heightAnchor constraintEqualToAnchor:filterScroll.frameLayoutGuide.heightAnchor]
    ]];
    [self.contentStack addArrangedSubview:filterScroll];

    self.listStack = [[UIStackView alloc] init];
    self.listStack.axis = UILayoutConstraintAxisVertical;
    self.listStack.spacing = 8.0;
    [self.contentStack addArrangedSubview:self.listStack];

    PDMGlassPillButton *selectAllBtn = [[PDMGlassPillButton alloc] initWithTitle:@"Select All" symbolName:@"checkmark.circle"];
    selectAllBtn.verticalPadding = 12.0;
    [selectAllBtn addTarget:self action:@selector(handleSelectAllTap) forControlEvents:UIControlEventTouchUpInside];
    [self.bottomBarStack addArrangedSubview:selectAllBtn];

    self.downloadBtn = [[PDMGlassPillButton alloc] initWithTitle:@"Download (0)" symbolName:@"arrow.down.circle.fill"];
    self.downloadBtn.prominentAccent = YES;
    self.downloadBtn.verticalPadding = 12.0;
    [self.downloadBtn addTarget:self action:@selector(handleBatchSendTap) forControlEvents:UIControlEventTouchUpInside];
    [self.bottomBarStack addArrangedSubview:self.downloadBtn];

    [self rebuildFiltersAndList];
}

- (NSArray<PDMPageResource *> *)filteredResources {
    if ([self.activeFilter isEqualToString:@"All"]) {
        return self.resources;
    }
    NSMutableArray<PDMPageResource *> *arr = [NSMutableArray array];
    for (PDMPageResource *r in self.resources) {
        if ([r.category isEqualToString:self.activeFilter]) {
            [arr addObject:r];
        }
    }
    return arr;
}

- (void)rebuildFiltersAndList {
    PDMThemeSpec *spec = [PDMThemeManager sharedManager].currentSpec;
    for (UIView *v in [self.filterRow.arrangedSubviews copy]) {
        [self.filterRow removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    NSArray<NSString *> *cats = @[@"All", @"Videos", @"Audio", @"Images", @"Archives", @"Documents"];
    for (NSUInteger i = 0; i < cats.count; i++) {
        PDMGlassChip *chip = [[PDMGlassChip alloc] initWithTitle:cats[i] subtitle:nil];
        chip.tag = (NSInteger)i;
        chip.chipSelected = [self.activeFilter isEqualToString:cats[i]];
        [chip addTarget:self action:@selector(handleFilterTap:) forControlEvents:UIControlEventTouchUpInside];
        [self.filterRow addArrangedSubview:chip];
    }

    for (UIView *v in [self.listStack.arrangedSubviews copy]) {
        [self.listStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }

    NSArray<PDMPageResource *> *items = [self filteredResources];
    if (items.count == 0) {
        UILabel *empty = [[UILabel alloc] init];
        empty.text = @"No resources in this category.";
        empty.font = [[PDMThemeManager sharedManager] bodyFontOfSize:14.0 weight:UIFontWeightMedium];
        empty.textColor = spec.secondaryTextColor;
        empty.textAlignment = NSTextAlignmentCenter;
        [self.listStack addArrangedSubview:empty];
    } else {
        for (NSUInteger i = 0; i < items.count; i++) {
            PDMPageResource *r = items[i];
            PDMGlassView *card = [[PDMGlassView alloc] initWithCornerRadius:14.0 elevated:r.selected];
            card.showAmbientShadow = NO;
            if (r.selected) {
                card.customBorderColor = spec.accentColor;
                card.customTintColor = [spec.accentColor colorWithAlphaComponent:0.16];
            }
            UIControl *tap = [[UIControl alloc] init];
            tap.tag = (NSInteger)i;
            tap.translatesAutoresizingMaskIntoConstraints = NO;
            [tap addTarget:self action:@selector(handleItemToggle:) forControlEvents:UIControlEventTouchUpInside];
            [card.contentView addSubview:tap];

            UIStackView *row = [[UIStackView alloc] init];
            row.axis = UILayoutConstraintAxisHorizontal;
            row.alignment = UIStackViewAlignmentCenter;
            row.spacing = 10.0;
            row.userInteractionEnabled = NO;
            row.translatesAutoresizingMaskIntoConstraints = NO;
            [tap addSubview:row];

            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18.0 weight:UIImageSymbolWeightSemibold];
            UIImageView *chk = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:(r.selected ? @"checkmark.circle.fill" : @"circle") withConfiguration:cfg]];
            chk.tintColor = r.selected ? spec.accentColor : spec.tertiaryTextColor;
            [chk setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
            [row addArrangedSubview:chk];

            UIStackView *txt = [[UIStackView alloc] init];
            txt.axis = UILayoutConstraintAxisVertical;
            txt.spacing = 2.0;
            [row addArrangedSubview:txt];

            UILabel *t = [[UILabel alloc] init];
            t.text = r.title.length > 0 ? r.title : r.urlString.lastPathComponent;
            t.font = [[PDMThemeManager sharedManager] bodyFontOfSize:13.5 weight:UIFontWeightSemibold];
            t.textColor = spec.primaryTextColor;
            t.lineBreakMode = NSLineBreakByTruncatingMiddle;
            [txt addArrangedSubview:t];

            UILabel *sub = [[UILabel alloc] init];
            sub.text = [NSString stringWithFormat:@"%@ · %@", r.category, r.urlString];
            sub.font = [[PDMThemeManager sharedManager] tabularFontOfSize:11.0 weight:UIFontWeightRegular];
            sub.textColor = spec.secondaryTextColor;
            sub.lineBreakMode = NSLineBreakByTruncatingMiddle;
            [txt addArrangedSubview:sub];

            [NSLayoutConstraint activateConstraints:@[
                [tap.topAnchor constraintEqualToAnchor:card.contentView.topAnchor],
                [tap.bottomAnchor constraintEqualToAnchor:card.contentView.bottomAnchor],
                [tap.leadingAnchor constraintEqualToAnchor:card.contentView.leadingAnchor],
                [tap.trailingAnchor constraintEqualToAnchor:card.contentView.trailingAnchor],
                [row.topAnchor constraintEqualToAnchor:tap.topAnchor constant:10.0],
                [row.bottomAnchor constraintEqualToAnchor:tap.bottomAnchor constant:-10.0],
                [row.leadingAnchor constraintEqualToAnchor:tap.leadingAnchor constant:12.0],
                [row.trailingAnchor constraintEqualToAnchor:tap.trailingAnchor constant:-12.0]
            ]];
            [self.listStack addArrangedSubview:card];
        }
    }
    [self updateDownloadButtonCount];
}

- (void)updateDownloadButtonCount {
    NSInteger count = 0;
    for (PDMPageResource *r in self.resources) {
        if (r.selected) count++;
    }
    self.downloadBtn.titleText = [NSString stringWithFormat:@"Download (%ld)", (long)count];
}

- (void)handleFilterTap:(PDMGlassChip *)sender {
    [[PDMThemeManager sharedManager] triggerSelectionHaptic];
    NSArray<NSString *> *cats = @[@"All", @"Videos", @"Audio", @"Images", @"Archives", @"Documents"];
    if (sender.tag >= 0 && sender.tag < (NSInteger)cats.count) {
        self.activeFilter = cats[(NSUInteger)sender.tag];
        [self rebuildFiltersAndList];
    }
}

- (void)handleItemToggle:(UIControl *)sender {
    [[PDMThemeManager sharedManager] triggerSelectionHaptic];
    NSArray<PDMPageResource *> *items = [self filteredResources];
    if (sender.tag >= 0 && sender.tag < (NSInteger)items.count) {
        items[(NSUInteger)sender.tag].selected = !items[(NSUInteger)sender.tag].selected;
        [self rebuildFiltersAndList];
    }
}

- (void)handleSelectAllTap {
    [[PDMThemeManager sharedManager] triggerLightImpact];
    NSArray<PDMPageResource *> *items = [self filteredResources];
    BOOL allSelected = YES;
    for (PDMPageResource *r in items) {
        if (!r.selected) {
            allSelected = NO;
            break;
        }
    }
    for (PDMPageResource *r in items) {
        r.selected = !allSelected;
    }
    [self rebuildFiltersAndList];
}

- (void)handleBatchSendTap {
    NSMutableArray<PDMPageResource *> *sel = [NSMutableArray array];
    for (PDMPageResource *r in self.resources) {
        if (r.selected) [sel addObject:r];
    }
    if (sel.count == 0) {
        [[PDMThemeManager sharedManager] triggerWarningHaptic];
        [PDMToastBanner showInView:self.view message:@"Select at least one resource first." symbolName:@"exclamationmark.circle"];
        return;
    }
    [[PDMThemeManager sharedManager] triggerSuccessHaptic];
    void (^cb)(NSArray<PDMPageResource *> *) = self.onBatchDownload;
    [self dismissViewControllerAnimated:YES completion:^{
        if (cb) cb(sel);
    }];
}

@end
