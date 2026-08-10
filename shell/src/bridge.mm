// FreePlayer shell — JS<->native bridge
// Injects window.freeplayer (mirror of electron/preload.js), console capture,
// and a window-drag shim (WKWebView has no -webkit-app-region support).

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <atomic>
#include "db.h"
#include "bridge.h"
#include "metadata.h"
#include "tray.h"
#import "pluginfs.h"

static const char *kAudioExtensions[] = { "mp3", "flac", "m4a", "aac", "ogg", "wav", "opus", "mp4" };

// M12: in-flight import counter — app termination waits for it to drain
std::atomic<int> gImportTasks{0};

bool fpPendingImports(void) {
  return gImportTasks.load() > 0;
}

static BOOL isAudioFile(NSString *path) {
  NSString *ext = path.pathExtension.lowercaseString;
  for (const char *e : kAudioExtensions) {
    if ([ext isEqualToString:@(e)]) return YES;
  }
  return NO;
}

// Recursive audio file scan (M3: skip hidden dirs without descending; use
// the enumerator's own attributes instead of stat-ing every entry)
static NSArray *scanAudioFiles(NSString *root) {
  NSMutableArray *found = [NSMutableArray array];
  NSFileManager *fm = NSFileManager.defaultManager;
  NSDirectoryEnumerator *en = [fm enumeratorAtPath:root];
  for (NSString *rel in en) {
    NSDictionary *attrs = [en fileAttributes];
    BOOL isDir = [attrs[NSFileType] isEqualToString:NSFileTypeDirectory];
    if (isDir) {
      // Hidden directory (.git, .Trashes, downloader caches): don't descend
      if ([rel.lastPathComponent hasPrefix:@"."]) [en skipDescendants];
      continue;
    }
    if ([rel.lastPathComponent hasPrefix:@"."]) continue; // hidden file
    NSString *full = [root stringByAppendingPathComponent:rel];
    if (isAudioFile(full)) {
      [found addObject:full];
    }
  }
  return found;
}

// ── Injected script ──
static const char *kBridgeScript = R"JS(
(() => {
  const pending = new Map();
  let seq = 0;

  const api = {
    // Import (M3: scan pipeline)
    importDialog: () => api._invoke('importDialog'),
    scanDirectory: (dirPath) => api._invoke('scanDirectory', dirPath),
    importFiles: (data) => api._invoke('importFiles', data),
    // Tracks
    getTracks: (params) => api._invoke('getTracks', params),
    getTrack: (id) => api._invoke('getTrack', id),
    updateTrack: (data) => api._invoke('updateTrack', data),
    deleteTrack: (id) => api._invoke('deleteTrack', id),
    getTrackCount: () => api._invoke('getTrackCount'),
    getTotalDuration: () => api._invoke('getTotalDuration'),
    // Network (native stack: no CORS, stable on unreliable links)
    httpGetJson: (url) => api._invoke('httpGetJson', url),
    httpGetBase64: (url) => api._invoke('httpGetBase64', url),
    // Playback history
    playStart: (trackId) => api._invoke('playStart', trackId),
    playEnd: (data) => api._invoke('playEnd', data),
    // History & Stats
    getPlayHistory: (limit) => api._invoke('getPlayHistory', limit),
    getStats: () => api._invoke('getStats'),
    // Cover art
    getCover: (coverPath) => api._invoke('getCover', coverPath),
    // Settings
    getSetting: (key) => api._invoke('getSetting', key),
    setSetting: (data) => api._invoke('setSetting', data),
    isSetup: () => api._invoke('isSetup'),
    selectLibraryDir: () => api._invoke('selectLibraryDir'),
    resetDatabase: () => api._invoke('resetDatabase'),
    // Playlists
    createPlaylist: (data) => api._invoke('createPlaylist', data),
    getPlaylists: () => api._invoke('getPlaylists'),
    addToPlaylist: (data) => api._invoke('addToPlaylist', data),
    addTracksToPlaylist: (data) => api._invoke('addTracksToPlaylist', data),
    setPlaylistTracks: (data) => api._invoke('setPlaylistTracks', data),
    getPlaylistTracks: (playlistId) => api._invoke('getPlaylistTracks', playlistId),
    removeFromPlaylist: (data) => api._invoke('removeFromPlaylist', data),
    deletePlaylist: (playlistId) => api._invoke('deletePlaylist', playlistId),
    renamePlaylist: (data) => api._invoke('renamePlaylist', data),
    // LRC Lyrics
    getLrc: (trackId) => api._invoke('getLrc', trackId),
    setLrc: (data) => api._invoke('setLrc', data),
    uploadLrc: (trackId) => api._invoke('uploadLrc', trackId),
    removeLrc: (trackId) => api._invoke('removeLrc', trackId),
    saveLrcContent: (trackId, content) => api._invoke('saveLrcContent', trackId, content),
    saveCover: (trackId, base64) => api._invoke('saveCover', trackId, base64),
    // Media keys / tray (M5)
    onMediaKey: (callback) => { window.__freeplayerMediaKeyHandler = callback; },
    sendPlaybackState: (isPlaying) => api._invoke('sendPlaybackState', { isPlaying }),
    onPlaybackControl: (callback) => { window.__freeplayerPlaybackHandler = callback; },
    // Login item (M5)
    getLoginItemSettings: () => api._invoke('getLoginItemSettings'),
    setLoginItemSettings: (data) => api._invoke('setLoginItemSettings', data),
    // Equalizer (10-band)
    openEq: () => api._invoke('openEqWindow'),
    getEqState: () => api._invoke('getEqState'),
    setEq: (data) => api._invoke('setEq', data),
    onEqChange: (callback) => { window.__freeplayerEqHandler = callback; },
    // Native file drop -> renderer import flow
    onDropFiles: (callback) => { window.__freeplayerDropHandler = callback; },
    // First-run onboarding
    finishOnboarding: () => api._invoke('finishOnboarding'),
    // Plugins
    listPlugins: () => api._invoke('listPlugins'),
    readPluginFile: (id, rel) => api._invoke('readPluginFile', id, rel),
    openPluginsDir: () => api._invoke('openPluginsDir'),
    uninstallPlugin: (id) => api._invoke('uninstallPlugin', id),
  };

  api._invoke = (method, ...args) => new Promise((resolve, reject) => {
    const id = ++seq;
    pending.set(id, { resolve, reject });
    window.webkit.messageHandlers.freeplayer.postMessage({ id, method, args });
  });

  window.freeplayer = api;
  window.freeplayer._resolve = (id, result) => {
    const p = pending.get(id);
    if (!p) return;
    pending.delete(id);
    p.resolve(result);
  };
  window.freeplayer._reject = (id, err) => {
    const p = pending.get(id);
    if (!p) return;
    pending.delete(id);
    p.reject(new Error(String(err)));
  };
  // Tray menu -> playback control channel
  window.freeplayer._pushControl = (action) => {
    if (window.__freeplayerPlaybackHandler) {
      try { window.__freeplayerPlaybackHandler({ action }); } catch (e) {}
    }
  };
  // System media keys -> media key channel
  window.freeplayer._pushMediaKey = (action) => {
    if (window.__freeplayerMediaKeyHandler) {
      try { window.__freeplayerMediaKeyHandler(action); } catch (e) {}
    }
  };
  // Native file drop -> paths into the renderer
  window.freeplayer._pushDrop = (paths) => {
    if (window.__freeplayerDropHandler) {
      try { window.__freeplayerDropHandler(paths); } catch (e) {}
    }
  };
  window.freeplayer._pushEq = (state) => {
    if (window.__freeplayerEqHandler) {
      try { window.__freeplayerEqHandler(state); } catch (e) {}
    }
  };

  // ── Window drag shim ──
  // WKWebView strips -webkit-app-region (Chromium-only), so map the app's
  // known regions directly. Keep in sync with App.css -webkit-app-region rules.
  const DRAG_SEL = '.top-bar, .sidebar, .sidebar-header, .sidebar-logo';
  const NO_DRAG_SEL = '.top-bar-right, .sidebar-nav, .sidebar-footer, .nav-item,'
    + ' button, input, textarea, select, a, [contenteditable]';

  document.addEventListener('mousedown', (e) => {
    if (e.button !== 0) return;
    const t = e.target;
    if (!t.closest) return;
    if (t.closest(NO_DRAG_SEL)) return;
    if (!t.closest(DRAG_SEL)) return;
    try {
      window.webkit.messageHandlers.freeplayer.postMessage({
        id: 0, method: '__dragStart', args: [e.screenX, e.screenY],
      });
      e.preventDefault();
    } catch (err) {}
  });

  // ── Console capture ──
  ['log', 'warn', 'error', 'info'].forEach((lv) => {
    const orig = console[lv];
    console[lv] = (...a) => {
      orig.apply(console, a);
      try {
        window.webkit.messageHandlers.freeplayer.postMessage({
          id: 0, method: '__console', args: [lv, a.map((x) => {
            if (x instanceof Error) return (x.stack || x.message).slice(0, 1200);
            try { return JSON.stringify(x); } catch { return String(x); }
          }).join(' ')],
        });
      } catch (e) {}
    };
  });
  window.addEventListener('error', (e) => {
    try {
      window.webkit.messageHandlers.freeplayer.postMessage({
        id: 0, method: '__console',
        args: ['error', 'window.onerror: ' + (e.message || '') + ' @ ' + (e.filename || '') + ':' + (e.lineno || '')],
      });
    } catch (err) {}
  });
  window.addEventListener('unhandledrejection', (e) => {
    try {
      const r = e.reason;
      window.webkit.messageHandlers.freeplayer.postMessage({
        id: 0, method: '__console',
        args: ['error', 'unhandledrejection: ' + (r && (r.stack || r.message) || String(r)).slice(0, 1200)],
      });
    } catch (err) {}
  });

  window.webkit.messageHandlers.freeplayer.postMessage({ id: 0, method: '__ready', args: [] });
})();
)JS";

NSString *fpBridgeScript() {
  return [NSString stringWithUTF8String:kBridgeScript];
}

// M7: verbose IPC logging gated behind FP_VERBOSE (env or defaults)
static BOOL fpVerboseLogging(void) {
  static int v = -1;
  if (v == -1) {
    v = (getenv("FP_VERBOSE") != NULL
         || [NSUserDefaults.standardUserDefaults boolForKey:@"FP_VERBOSE"]) ? 1 : 0;
  }
  return v == 1;
}

// Shared library containment check — the trust anchor for all renderer-
// facing file reads (covers, LRC, media streaming). See NEW-2: library_dir
// itself can only be set by the native NSOpenPanel flows.
static BOOL fpPathInLibrary(NSString *path) {
  NSString *libNorm = [fpdb::getSetting(@"library_dir", nil) stringByStandardizingPath];
  if (libNorm.length == 0) return NO;
  NSString *pathNorm = [path stringByStandardizingPath];
  return [pathNorm hasPrefix:[libNorm stringByAppendingString:@"/"]]
      || [pathNorm isEqualToString:libNorm];
}

// ── Native HTTP (M1: shared helper + one session for json/base64) ──
static const NSUInteger kMaxHttpBytes = 8 * 1024 * 1024; // H5: response cap

static NSURLSession *fpSharedSession(void) {
  static NSURLSession *session = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.waitsForConnectivity = YES;             // L1: don't fail instantly offline
    cfg.timeoutIntervalForRequest = 10;
    cfg.timeoutIntervalForResource = 30;
    session = [NSURLSession sessionWithConfiguration:cfg];
  });
  return session;
}

// Shared GET pipeline: validates scheme (H5 — never file:// or friends),
// enforces a size cap, shapes {ok, status, retryAfter?, error?}, hands the
// body to `fill` on success, and hops back to the main thread to reply.
static void fpHttpGet(NSString *urlStr, NSNumber *mid, void (^replyBlock)(NSNumber *, id),
                      void (^fill)(NSMutableDictionary *, NSData *)) {
  if (urlStr.length == 0) { replyBlock(mid, @{ @"ok": @NO, @"error": @"empty url" }); return; }
  NSURL *url = [NSURL URLWithString:urlStr];
  if (!url) { replyBlock(mid, @{ @"ok": @NO, @"error": @"bad url" }); return; }
  // H5: http/https only — NSURLSession would happily serve file:// (arbitrary
  // local file read from a compromised renderer)
  if (![url.scheme isEqualToString:@"http"] && ![url.scheme isEqualToString:@"https"]) {
    replyBlock(mid, @{ @"ok": @NO, @"error": @"unsupported scheme" });
    return;
  }
  NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
  req.timeoutInterval = 10;
  // Descriptive User-Agent — LRCLIB and iTunes both ask clients to identify
  // themselves so abuse is attributable instead of IP-banned.
  NSString *ver = NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"dev";
  [req setValue:[NSString stringWithFormat:@"FreePlayer/%@ (+https://github.com/zprolab/FreePlayer)", ver]
      forHTTPHeaderField:@"User-Agent"];
  NSURLSessionDataTask *task = [fpSharedSession() dataTaskWithRequest:req
    completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
      NSHTTPURLResponse *http = (NSHTTPURLResponse *)resp;
      NSMutableDictionary *result = [NSMutableDictionary dictionary];
      if (err) {
        result[@"ok"] = @NO;
        result[@"error"] = err.localizedDescription ?: @"network error";
      } else if (http.statusCode >= 400) {
        result[@"ok"] = @NO;
        result[@"status"] = @(http.statusCode);
        result[@"error"] = @"http error";
        NSString *ra = http.allHeaderFields[@"Retry-After"];
        if (ra.length > 0) result[@"retryAfter"] = ra;
      } else if (data.length > kMaxHttpBytes) {
        result[@"ok"] = @NO;
        result[@"error"] = @"response too large";
      } else {
        result[@"ok"] = @YES;
        result[@"status"] = @(http.statusCode);
        fill(result, data);
      }
      dispatch_async(dispatch_get_main_queue(), ^{ replyBlock(mid, result); });
    }];
  [task resume];
}

// ── Equalizer state: settings table + cross-window broadcast ──
static NSString *eqKey(NSString *suffix) {
  return [NSString stringWithFormat:@"eq.%@", suffix];
}

static NSDictionary *fpEqStateDict(void) {
  NSMutableArray *gains = [NSMutableArray array];
  NSString *raw = fpdb::getSetting(eqKey(@"gains"), nil);
  for (NSString *p in [raw componentsSeparatedByString:@","]) {
    [gains addObject:@(p.doubleValue)];
  }
  while (gains.count < 10) [gains addObject:@0];
  id enabled = fpdb::getSetting(eqKey(@"enabled"), nil);
  id preset = fpdb::getSetting(eqKey(@"preset"), nil);
  return @{
    @"enabled": @([enabled isKindOfClass:NSString.class] ? [enabled boolValue] : NO),
    @"preset": [preset isKindOfClass:NSString.class] ? preset : @"平坦",
    @"gains": gains,
  };
}

static void fpSaveEq(NSDictionary *d) {
  NSArray *g = d[@"gains"];
  NSMutableArray *vals = [NSMutableArray array];
  for (id v in g) {
    [vals addObject:[NSString stringWithFormat:@"%.1f", [v doubleValue]]];
  }
  // M6: one transaction instead of three autocommits (fsync per write);
  // if the transaction can't start, fall back to plain autocommit writes
  BOOL tx = fpdb::beginTransaction();
  fpdb::setSetting(eqKey(@"enabled"), [d[@"enabled"] boolValue] ? @"1" : @"0");
  fpdb::setSetting(eqKey(@"preset"), [d[@"preset"] isKindOfClass:NSString.class] ? d[@"preset"] : @"自定义");
  fpdb::setSetting(eqKey(@"gains"), [vals componentsJoinedByString:@","]);
  if (tx) fpdb::commitTransaction();
}

static void fpBroadcastEq(void) {
  dispatch_async(dispatch_get_main_queue(), ^{
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:fpEqStateDict() options:0 error:&err];
    if (err || !data) return;
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSString *js = [NSString stringWithFormat:@"window.freeplayer._pushEq(%@)", json];
    if (gWebView) [gWebView evaluateJavaScript:js completionHandler:nil];
    if (gEqWebView) [gEqWebView evaluateJavaScript:js completionHandler:nil];
  });
}

// Native file drop (ShellWebView) -> renderer import flow
void fpHandleDropPaths(NSArray<NSString *> *paths) {
  if (paths.count == 0) return;
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!gWebView) return;
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:paths options:0 error:&err];
    if (err || !data) return;
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSString *js = [NSString stringWithFormat:@"window.freeplayer._pushDrop(%@)", json];
    [gWebView evaluateJavaScript:js completionHandler:nil];
  });
}

// ── Native side ──
@interface BridgeHandler : NSObject <WKScriptMessageHandler>
@end

@implementation BridgeHandler

static NSWindow *shellWindow(void) {
  return NSApp.windows.count ? NSApp.windows[0] : nil;
}

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
  if (![message.name isEqualToString:@"freeplayer"]) return;
  if (![message.body isKindOfClass:NSDictionary.class]) return;
  NSDictionary *body = (NSDictionary *)message.body;
  NSNumber *idNum = body[@"id"];
  NSString *method = body[@"method"];
  NSArray *args = body[@"args"] ?: @[];

  if ([method isEqualToString:@"__ready"]) {
    NSLog(@"[shell] bridge ready, %@", message.webView.URL);
    // Diagnostics toggles (set after the page is up, avoids injection races)
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"FP_SPECTRO_TEST"]) {
      [message.webView evaluateJavaScript:@"window.__FP_SPECTRO_TEST = true;" completionHandler:nil];
    }
    return;
  }
  if ([method isEqualToString:@"__console"]) {
    NSArray *a = body[@"args"];
    NSLog(@"[page %@] %@", a.firstObject ?: @"log", a.count > 1 ? a[1] : @"");
    return;
  }
  if ([method isEqualToString:@"__dragStart"]) {
    // Kick off AppKit's modal window drag with a synthetic mouse event.
    NSWindow *win = shellWindow();
    if (!win) return;
    CGFloat sx = [args.firstObject doubleValue];
    CGFloat sy = args.count > 1 ? [args[1] doubleValue] : 0;
    CGFloat screenH = NSScreen.screens.firstObject.frame.size.height;
    NSPoint p = NSMakePoint(sx, screenH - sy);
    p = [win convertPointFromScreen:p];
    NSEvent *evt = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                       location:p
                                  modifierFlags:0
                                      timestamp:NSProcessInfo.processInfo.systemUptime
                                   windowNumber:win.windowNumber
                                        context:nil
                                    eventNumber:0
                                     clickCount:1
                                       pressure:1.0];
    [win performWindowDragWithEvent:evt];
    return;
  }

  // reply: window.freeplayer._resolve(id, <json>)
  auto reply = ^(NSNumber *mid, id obj) {
    NSString *json = nil;
    if (obj == nil || obj == NSNull.null) {
      json = @"null"; // NSNull is not a valid JSON top-level type
    } else {
      NSError *err = nil;
      // FragmentsAllowed: replies are often bare numbers/booleans (session ids, ok flags)
      NSData *data = [NSJSONSerialization dataWithJSONObject:obj
                                                    options:NSJSONWritingFragmentsAllowed
                                                      error:&err];
      if (err || !data) {
        NSLog(@"[shell] reply serialization failed for %@: %@", mid, err);
        return;
      }
      json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    NSString *js = [NSString stringWithFormat:@"window.freeplayer._resolve(%ld, %@)",
                    (long)mid.integerValue, json];
    [message.webView evaluateJavaScript:js completionHandler:nil];
  };
  // M2: JSON-encode the message — a JSON string is always valid JS, unlike
  // hand-escaping which broke on newlines / double quotes / U+2028
  auto reject = ^(NSNumber *mid, NSString *why) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:why ?: @"error" options:0 error:nil];
    NSString *json = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"\"error\"";
    NSString *js = [NSString stringWithFormat:@"window.freeplayer._reject(%ld, %@)",
                    (long)mid.integerValue, json];
    [message.webView evaluateJavaScript:js completionHandler:nil];
  };

  // M7: every-IPC NSLog is syscall spam on the playback hot path — gate it
  if (fpVerboseLogging()) NSLog(@"[shell] method=%@", method);

  @try {
    // ── Settings / setup ──
    if ([method isEqualToString:@"isSetup"]) {
      NSString *dir = fpdb::getSetting(@"library_dir", nil);
      reply(idNum, @{ @"setup": dir ? @YES : @NO, @"libraryDir": dir ?: NSNull.null });
    } else if ([method isEqualToString:@"getSetting"]) {
      reply(idNum, fpdb::getSetting(args.firstObject, nil) ?: NSNull.null);
    } else if ([method isEqualToString:@"setSetting"]) {
      NSDictionary *d = args.firstObject;
      NSString *key = d[@"key"];
      // NEW-2: library_dir is the trust anchor for the file-read boundary —
      // only the native NSOpenPanel flows (importDialog/selectLibraryDir) may
      // set it; a renderer-writable anchor would let XSS widen the boundary
      // and read arbitrary files via getCover/media:///getLrc.
      if ([key isEqualToString:@"library_dir"]) {
        reply(idNum, @NO);
        return;
      }
      reply(idNum, @(fpdb::setSetting(key, d[@"value"])));
    } else if ([method isEqualToString:@"getEqState"]) {
      reply(idNum, fpEqStateDict());
    } else if ([method isEqualToString:@"setEq"]) {
      NSDictionary *d = args.firstObject;
      fpSaveEq(d);
      fpBroadcastEq();
      reply(idNum, @YES);
    } else if ([method isEqualToString:@"openEqWindow"]) {
      fpOpenEqWindow();
      reply(idNum, @YES);
    } else if ([method isEqualToString:@"resetDatabase"]) {
      reply(idNum, @(fpdb::resetDatabase()));
    }
    // ── Tracks (H2: read-heavy queries + reply JSON off the main thread) ──
    else if ([method isEqualToString:@"getTracks"]) {
      NSDictionary *p = args.firstObject;
      NSString *search = p[@"search"] ?: @"";
      NSString *sortBy = p[@"sortBy"] ?: @"imported_at";
      NSString *sortDir = p[@"sortDir"] ?: @"DESC";
      NSNumber *mid = idNum;
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *rows = fpdb::getAllTracks(search, sortBy, sortDir);
        dispatch_async(dispatch_get_main_queue(), ^{ reply(mid, rows); });
      });
    } else if ([method isEqualToString:@"getTrack"]) {
      int64_t tid = [args.firstObject longLongValue];
      NSNumber *mid = idNum;
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        id track = fpdb::getTrackById(tid);
        dispatch_async(dispatch_get_main_queue(), ^{ reply(mid, track); });
      });
    } else if ([method isEqualToString:@"updateTrack"]) {
      NSDictionary *d = args.firstObject;
      reply(idNum, @(fpdb::updateTrack([d[@"id"] longLongValue], d)));
    } else if ([method isEqualToString:@"deleteTrack"]) {
      reply(idNum, @(fpdb::deleteTrack([args.firstObject longLongValue])));
    } else if ([method isEqualToString:@"getTrackCount"]) {
      NSNumber *mid = idNum;
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int64_t n = fpdb::getTrackCount();
        dispatch_async(dispatch_get_main_queue(), ^{ reply(mid, @(n)); });
      });
    } else if ([method isEqualToString:@"getTotalDuration"]) {
      NSNumber *mid = idNum;
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        double d = fpdb::getTotalDuration();
        dispatch_async(dispatch_get_main_queue(), ^{ reply(mid, @(d)); });
      });
    }
    // ── Playback history ──
    else if ([method isEqualToString:@"playStart"]) {
      int64_t tid = [args.firstObject longLongValue];
      int64_t sid = fpdb::startPlaySession(tid);
      // Tray + Control Center: track info straight from the DB (safe objects)
      id track = fpdb::getTrackById(tid);
      if ([track isKindOfClass:NSDictionary.class]) {
        [FpTray setNowPlayingFromTrack:track];
      }
      reply(idNum, @(sid));
    } else if ([method isEqualToString:@"playEnd"]) {
      NSDictionary *d = args.firstObject;
      reply(idNum, @(fpdb::endPlaySession([d[@"sessionId"] longLongValue],
                                          [d[@"durationSeconds"] doubleValue],
                                          [d[@"playPercentage"] doubleValue])));
    }
    // ── Stats (H2: off main thread) ──
    else if ([method isEqualToString:@"getPlayHistory"]) {
      long limit = [args.firstObject longValue] ?: 50;
      NSNumber *mid = idNum;
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *rows = fpdb::getPlayHistory(limit);
        dispatch_async(dispatch_get_main_queue(), ^{ reply(mid, rows); });
      });
    } else if ([method isEqualToString:@"getStats"]) {
      NSNumber *mid = idNum;
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *stats = fpdb::getListeningStats();
        dispatch_async(dispatch_get_main_queue(), ^{ reply(mid, stats); });
      });
    }
    // ── Cover art (H3: file read + base64 off the main thread; L2: the path
    // must live inside the library — getCover is a renderer-facing arbitrary
    // file read otherwise) ──
    else if ([method isEqualToString:@"getCover"]) {
      NSString *coverPath = args.firstObject;
      if (!fpPathInLibrary(coverPath)) {
        reply(idNum, NSNull.null);
        return;
      }
      NSNumber *mid = idNum;
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSData *data = [NSData dataWithContentsOfFile:coverPath];
        dispatch_async(dispatch_get_main_queue(), ^{
          if (data) {
            NSString *ext = coverPath.pathExtension.lowercaseString;
            NSString *mime = [ext isEqualToString:@"png"] ? @"image/png"
                            : [ext isEqualToString:@"webp"] ? @"image/webp"
                            : @"image/jpeg";
            reply(mid, [NSString stringWithFormat:@"data:%@;base64,%@", mime, [data base64EncodedStringWithOptions:0]]);
          } else {
            reply(mid, NSNull.null);
          }
        });
      });
    }
    // ── Network: JSON GET via native stack (no CORS, stable) ──
    else if ([method isEqualToString:@"httpGetJson"]) {
      fpHttpGet(args.firstObject, idNum, reply, ^(NSMutableDictionary *result, NSData *data) {
        id parsed = data.length > 0 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        result[@"body"] = parsed ?: NSNull.null;
      });
    }
    // ── Network: binary GET via native stack (cover art downloads) ──
    else if ([method isEqualToString:@"httpGetBase64"]) {
      fpHttpGet(args.firstObject, idNum, reply, ^(NSMutableDictionary *result, NSData *data) {
        result[@"base64"] = [data base64EncodedStringWithOptions:0] ?: @"";
      });
    }
    // ── Playlists (H2: reads off main thread) ──
    else if ([method isEqualToString:@"getPlaylists"]) {
      NSNumber *mid = idNum;
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *rows = fpdb::getAllPlaylists();
        dispatch_async(dispatch_get_main_queue(), ^{ reply(mid, rows); });
      });
    } else if ([method isEqualToString:@"createPlaylist"]) {
      NSDictionary *d = args.firstObject;
      reply(idNum, @{ @"lastInsertRowid": @(fpdb::createPlaylist(d[@"name"], d[@"description"])) });
    } else if ([method isEqualToString:@"renamePlaylist"]) {
      NSDictionary *d = args.firstObject;
      reply(idNum, @(fpdb::renamePlaylist([d[@"id"] longLongValue], d[@"name"])));
    } else if ([method isEqualToString:@"deletePlaylist"]) {
      reply(idNum, @(fpdb::deletePlaylist([args.firstObject longLongValue])));
    } else if ([method isEqualToString:@"getPlaylistTracks"]) {
      int64_t pid = [args.firstObject longLongValue];
      NSNumber *mid = idNum;
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *rows = fpdb::getPlaylistTracks(pid);
        dispatch_async(dispatch_get_main_queue(), ^{ reply(mid, rows); });
      });
    } else if ([method isEqualToString:@"addToPlaylist"]) {
      NSDictionary *d = args.firstObject;
      reply(idNum, @(fpdb::addTrackToPlaylist([d[@"playlistId"] longLongValue], [d[@"trackId"] longLongValue])));
    } else if ([method isEqualToString:@"addTracksToPlaylist"]) {
      NSDictionary *d = args.firstObject;
      reply(idNum, @(fpdb::addTracksToPlaylist([d[@"playlistId"] longLongValue], d[@"trackIds"])));
    } else if ([method isEqualToString:@"setPlaylistTracks"]) {
      NSDictionary *d = args.firstObject;
      reply(idNum, @(fpdb::setPlaylistTracks([d[@"playlistId"] longLongValue], d[@"trackIds"])));
    } else if ([method isEqualToString:@"removeFromPlaylist"]) {
      NSDictionary *d = args.firstObject;
      reply(idNum, @(fpdb::removeTrackFromPlaylist([d[@"playlistId"] longLongValue], [d[@"trackId"] longLongValue])));
    }
    // ── LRC ──
    else if ([method isEqualToString:@"getLrc"]) {
      int64_t tid = [args.firstObject longLongValue];
      NSString *lrcPath = fpdb::getTrackLrc(tid);
      if (!lrcPath) {
        // Sidecar detection: "Artist - Title_L.lrc" next to "Artist - Title_EM.flac"
        id track = fpdb::getTrackById(tid);
        if ([track isKindOfClass:NSDictionary.class]) {
          lrcPath = fpmeta::findSidecarLrc(track[@"file_path"]);
        }
      }
      if (!lrcPath || ![[NSFileManager defaultManager] fileExistsAtPath:lrcPath]) {
        reply(idNum, NSNull.null);
      } else {
        // NEW-1: lrc_path is stored verbatim from setLrc — never read a file
        // outside the library (arbitrary local-file read via getLrc)
        if (!fpPathInLibrary(lrcPath)) {
          reply(idNum, NSNull.null);
          return;
        }
        NSData *raw = [NSData dataWithContentsOfFile:lrcPath];
        NSString *content = [[NSString alloc] initWithData:raw encoding:NSUTF8StringEncoding];
        if (!content) { // fall back to GB18030 for CJK LRC files
          NSStringEncoding gb = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
          content = [[NSString alloc] initWithData:raw encoding:gb];
        }
        reply(idNum, content ? @{ @"content": content, @"path": lrcPath } : NSNull.null);
      }
    } else if ([method isEqualToString:@"setLrc"]) {
      NSDictionary *d = args.firstObject;
      NSString *lrcPath = d[@"lrcPath"];
      // NEW-1: reject out-of-library lrc paths (getLrc would read them back)
      if (!fpPathInLibrary(lrcPath)) {
        reply(idNum, @NO);
        return;
      }
      reply(idNum, @(fpdb::setTrackLrc([d[@"trackId"] longLongValue], lrcPath)));
    } else if ([method isEqualToString:@"saveLrcContent"]) {
      int64_t tid = [args.firstObject longLongValue];
      NSString *content = args.count > 1 ? args[1] : nil;
      NSDictionary *track = fpdb::getTrackById(tid);
      if (![track isKindOfClass:NSDictionary.class] || content.length == 0) {
        reply(idNum, @{ @"success": @NO });
        return;
      }
      NSString *audioPath = track[@"file_path"];
      NSString *audioStem = fpmeta::cleanAudioStem(audioPath.lastPathComponent.stringByDeletingPathExtension);
      // Name the sidecar with the track id: two files in one dir can share a
      // cleanStem (e.g. "Song.flac" + "Song_L.flac" both stem to "Song").
      // "<stem>.<tid>.lrc" never exact-matches a sibling, and findSidecarLrc's
      // prefix branch (fixed in Task 1 Step 1) skips ".<digits>" stems, so no
      // sibling can pick this file up either. The DB lrc_path (set below) is
      // what getLrc reads first anyway.
      NSString *target = [[audioPath.stringByDeletingLastPathComponent
                           stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%lld", audioStem, tid]]
                          stringByAppendingPathExtension:@"lrc"];
      NSError *err = nil;
      BOOL ok = [content writeToFile:target atomically:YES encoding:NSUTF8StringEncoding error:&err];
      if (ok) ok = fpdb::setTrackLrc(tid, target);
      reply(idNum, ok ? @{ @"success": @YES, @"lrcPath": target } : @{ @"success": @NO });
    } else if ([method isEqualToString:@"saveCover"]) {
      int64_t tid = [args.firstObject longLongValue];
      NSString *b64 = args.count > 1 ? args[1] : nil;
      NSDictionary *track = fpdb::getTrackById(tid);
      if (![track isKindOfClass:NSDictionary.class] || b64.length == 0) {
        reply(idNum, @{ @"success": @NO });
        return;
      }
      NSData *img = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
      if (!img) { reply(idNum, @{ @"success": @NO }); return; }
      CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)img, NULL);
      if (!src) { reply(idNum, @{ @"success": @NO }); return; }
      CFRelease(src);
      NSString *audioPath = track[@"file_path"];
      NSString *coverDir = [audioPath.stringByDeletingLastPathComponent stringByAppendingPathComponent:@".covers"];
      NSFileManager *fm = NSFileManager.defaultManager;
      if (![fm fileExistsAtPath:coverDir]) {
        NSError *dirErr = nil;
        if (![fm createDirectoryAtPath:coverDir withIntermediateDirectories:YES attributes:nil error:&dirErr]) {
          NSLog(@"[bridge] failed to create cover dir: %@", dirErr);
          reply(idNum, @{ @"success": @NO });
          return;
        }
      }
      NSString *coverPath = [coverDir stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"cover-%lld.jpg", tid]];
      BOOL ok = [img writeToFile:coverPath atomically:YES];
      if (ok) ok = fpdb::setTrackCover(tid, coverPath);
      reply(idNum, ok ? @{ @"success": @YES, @"coverPath": coverPath } : @{ @"success": @NO });
    } else if ([method isEqualToString:@"removeLrc"]) {
      reply(idNum, @(fpdb::clearTrackLrc([args.firstObject longLongValue])));
    } else if ([method isEqualToString:@"uploadLrc"]) {
      int64_t tid = [args.firstObject longLongValue];
      NSDictionary *track = fpdb::getTrackById(tid);
      if ([track isKindOfClass:NSNull.class]) { reply(idNum, @{ @"error": @"Track not found" }); return; }
      NSOpenPanel *panel = [NSOpenPanel openPanel];
      panel.title = @"Select LRC Lyrics File";
      panel.allowedContentTypes = @[ UTTypePlainText ];
      panel.canChooseFiles = YES;
      panel.canChooseDirectories = NO;
      panel.allowsMultipleSelection = NO;
      if ([panel runModal] == NSModalResponseOK) {
        NSString *chosen = panel.URL.path;
        // Mirror electron: copy the .lrc next to the audio file
        NSString *audioPath = track[@"file_path"];
        NSString *target = [audioPath.stringByDeletingLastPathComponent
                            stringByAppendingPathComponent:chosen.lastPathComponent];
        NSData *raw = [NSData dataWithContentsOfFile:chosen];
        if (raw) {
          [raw writeToFile:target atomically:YES];
          chosen = target;
          // Minor-2: only persist lrc_path when the copy actually succeeded —
          // otherwise the DB entry points outside the library (dead entry)
          fpdb::setTrackLrc(tid, chosen);
        }
        NSString *content = [[NSString alloc] initWithData:raw encoding:NSUTF8StringEncoding];
        if (!content) {
          NSStringEncoding gb = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
          content = [[NSString alloc] initWithData:raw encoding:gb];
        }
        reply(idNum, @{ @"success": @YES, @"content": content ?: @"", @"path": chosen });
      } else {
        reply(idNum, @{ @"canceled": @YES });
      }
    }
    // ── Import (M3) ──
    else if ([method isEqualToString:@"importDialog"]) {
      NSOpenPanel *panel = [NSOpenPanel openPanel];
      panel.title = @"Select directory containing music files";
      panel.canChooseFiles = NO;
      panel.canChooseDirectories = YES;
      panel.allowsMultipleSelection = NO;
      if ([panel runModal] != NSModalResponseOK) {
        reply(idNum, @{ @"canceled": @YES });
        return;
      }
      NSString *sourceDir = panel.URL.path;
      NSString *libraryDir = fpdb::getSetting(@"library_dir", nil);
      reply(idNum, @{ @"canceled": @NO, @"sourceDir": sourceDir, @"libraryDir": libraryDir ?: NSNull.null });
    } else if ([method isEqualToString:@"scanDirectory"]) {
      // M3: directory walk off the main thread
      NSString *dir = args.firstObject;
      NSNumber *mid = idNum;
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *files = scanAudioFiles(dir);
        dispatch_async(dispatch_get_main_queue(), ^{ reply(mid, files); });
      });
    } else if ([method isEqualToString:@"importFiles"]) {
      NSDictionary *data = args.firstObject;
      NSArray *files = data[@"files"];
      // Library dir is native-set only (onboarding / Settings); the renderer
      // never supplies it — crafted metadata can no longer redirect writes.
      NSString *storedLib = fpdb::getSetting(@"library_dir", nil);
      if (storedLib.length == 0) {
        reply(idNum, @{ @"imported": @0, @"errors": @[], @"error": @"library not set" });
        return;
      }
      NSString *importMode = fpdb::getSetting(@"import_mode", @"copy"); // copy | symlink
      NSMutableArray *errors = [NSMutableArray array];
      __block NSInteger imported = 0, skipped = 0;
      NSNumber *mid = idNum;

      // M12: count in-flight imports so app termination can wait for them
      gImportTasks.fetch_add(1);

      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // H4: extract metadata concurrently (bounded), keep order-insensitive
        dispatch_queue_t extractQ = dispatch_queue_create("fp.extract", DISPATCH_QUEUE_CONCURRENT);
        dispatch_queue_t collectQ = dispatch_queue_create("fp.collect", DISPATCH_QUEUE_SERIAL);
        dispatch_group_t group = dispatch_group_create();
        NSMutableArray *prepared = [NSMutableArray array];
        for (NSString *filePath in files) {
          dispatch_group_async(group, extractQ, ^{
            NSDictionary *meta = fpmeta::extractAtPath(filePath);
            // Track the nested append inside the group: dispatch_group_async
            // counts only this block's return, so the append must enter/leave
            // the group itself or notify could race the last append.
            dispatch_group_enter(group);
            dispatch_async(collectQ, ^{
              [prepared addObject:@[ filePath, meta ?: NSNull.null ]];
              dispatch_group_leave(group);
            });
          });
        }
        dispatch_group_notify(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
          NSFileManager *fm = NSFileManager.defaultManager;
          // Phase 2: copy/symlink + build track rows WITHOUT holding the DB
          // write lock (file IO is the slow part — see #3). No transaction
          // here, so main-thread writes (playStart, settings, EQ) stay fast.
          NSMutableArray *tracksToInsert = [NSMutableArray array];
          for (NSArray *entry in prepared) {
            @autoreleasepool {
              NSString *filePath = entry[0];
              NSDictionary *meta = entry[1];
              if (![meta isKindOfClass:NSDictionary.class]) {
                [errors addObject:@{ @"file": filePath, @"error": @"Unreadable audio file" }];
                continue;
              }
              NSString *baseName = filePath.lastPathComponent;
              // Replace path separators with underscores to match the electron app
              auto safe = ^NSString *(NSString *s) {
                return [s stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
              };
              NSString *artist = safe(meta[@"artist"]);
              NSString *album = safe(meta[@"album"]);
              NSString *albumDir = [NSString pathWithComponents:@[ storedLib, artist, album ]];
              if (![fm fileExistsAtPath:albumDir]) {
                [fm createDirectoryAtPath:albumDir withIntermediateDirectories:YES attributes:nil error:nil];
              }
              NSString *targetPath = [albumDir stringByAppendingPathComponent:baseName];
              BOOL exists = [fm fileExistsAtPath:targetPath];
              if (!exists) {
                if ([importMode isEqualToString:@"symlink"]) {
                  [fm createSymbolicLinkAtPath:targetPath withDestinationPath:filePath error:nil];
                } else {
                  [fm copyItemAtPath:filePath toPath:targetPath error:nil];
                }
              }

              // Cover art -> <albumDir>/.covers/cover.ext
              NSString *coverPath = nil;
              NSData *artwork = meta[@"artwork"];
              if (artwork) {
                NSString *coverDir = [albumDir stringByAppendingPathComponent:@".covers"];
                if (![fm fileExistsAtPath:coverDir]) {
                  [fm createDirectoryAtPath:coverDir withIntermediateDirectories:YES attributes:nil error:nil];
                }
                coverPath = [coverDir stringByAppendingPathComponent:@"cover.jpg"];
                if (![fm fileExistsAtPath:coverPath]) {
                  [artwork writeToFile:coverPath atomically:YES];
                }
              }

              NSMutableDictionary *trackData = [meta mutableCopy];
              trackData[@"file_path"] = targetPath;
              trackData[@"cover_path"] = coverPath ?: NSNull.null;
              trackData[@"replaygain_gain"] = @0;
              trackData[@"replaygain_peak"] = @0;
              [trackData removeObjectForKey:@"artwork"];

              [tracksToInsert addObject:trackData];
              if (exists) skipped++; else imported++;
            }
          }
          // Phase 3: batched inserts — short transactions so the write lock
          // is never held for the whole import (main-thread writers stall
          // on busy_timeout while it is).
          const NSUInteger insertBatch = 50;
          for (NSUInteger i = 0; i < tracksToInsert.count; i += insertBatch) {
            BOOL tx = fpdb::beginTransaction();
            NSUInteger end = MIN(i + insertBatch, tracksToInsert.count);
            for (NSUInteger j = i; j < end; j++) {
              fpdb::insertTrack(tracksToInsert[j]);
            }
            if (tx) fpdb::commitTransaction();
          }
          NSDictionary *result = @{
            @"imported": @(imported),
            @"skipped": @(skipped),
            @"errors": errors,
          };
          gImportTasks.fetch_sub(1);
          dispatch_async(dispatch_get_main_queue(), ^{
            reply(mid, result);
          });
        });
      });
    }
    // ── Tray (M5) ──
    else if ([method isEqualToString:@"selectLibraryDir"]) {
      NSOpenPanel *panel = [NSOpenPanel openPanel];
      panel.canChooseFiles = NO;
      panel.canChooseDirectories = YES;
      panel.canCreateDirectories = YES;
      panel.title = @"Select Library Directory";
      if ([panel runModal] == NSModalResponseOK) {
        NSString *dir = panel.URL.path;
        fpdb::setSetting(@"library_dir", dir);
        reply(idNum, @{ @"canceled": @NO, @"path": dir, @"libraryDir": dir });
      } else {
        reply(idNum, @{ @"canceled": @YES });
      }
    } else if ([method isEqualToString:@"sendPlaybackState"]) {
      NSDictionary *d = args.firstObject;
      BOOL playing = [d[@"isPlaying"] boolValue];
      [FpTray setPlaying:playing];
      reply(idNum, NSNull.null);
    }
    // ── Login item (M5) ──
    else if ([method isEqualToString:@"getLoginItemSettings"]) {
      reply(idNum, @{ @"openAtLogin": @(fptrayLoginItemEnabled()) });
    } else if ([method isEqualToString:@"setLoginItemSettings"]) {
      NSDictionary *d = args.firstObject;
      reply(idNum, @{ @"ok": @(fptraySetLoginItem([d[@"openAtLogin"] boolValue])) });
    }
    // ── Plugins ──
    else if ([method isEqualToString:@"listPlugins"]) {
      reply(idNum, fpplugin::listPlugins());
    }
    else if ([method isEqualToString:@"readPluginFile"]) {
      NSString *pid = args.count > 0 ? args[0] : nil;
      NSString *rel = args.count > 1 ? args[1] : nil;
      NSString *content = fpplugin::readPluginFile(pid, rel);
      reply(idNum, content ?: NSNull.null);
    }
    else if ([method isEqualToString:@"openPluginsDir"]) {
      fpplugin::openPluginsDir();
      reply(idNum, @YES);
    }
    else if ([method isEqualToString:@"uninstallPlugin"]) {
      reply(idNum, @(fpplugin::removePlugin(args.firstObject)));
    }
    else if ([method isEqualToString:@"finishOnboarding"]) {
      fpFinishOnboarding();
      reply(idNum, @YES);
    }
    else {
      reject(idNum, [NSString stringWithFormat:@"not implemented: %@", method]);
    }
  } @catch (NSException *e) {
    NSLog(@"[shell] handler exception for %@: %@\n%@", method, e, [e callStackSymbols]);
    reject(idNum, e.reason ?: @"internal error");
  }
}

@end
