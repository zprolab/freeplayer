// FreePlayer shell — JS<->native bridge
// Injects window.freeplayer (mirror of electron/preload.js), console capture,
// and a window-drag shim (WKWebView has no -webkit-app-region support).

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <ImageIO/ImageIO.h>
#include <atomic>
#include <netdb.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include "db.h"
#include "bridge.h"
#include "metadata.h"
#include "paths.h"
#include "tray.h"
#import "pluginfs.h"

// M12: in-flight import counter — app termination waits for it to drain
std::atomic<int> gImportTasks{0};

bool fpPendingImports(void) {
  return gImportTasks.load() > 0;
}

// Q1: completion group for in-flight imports — applicationWillTerminate
// waits on this (bounded) before closing the DB, replacing the poll loop.
dispatch_group_t fpImportGroup(void) {
  static dispatch_group_t g = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ g = dispatch_group_create(); });
  return g;
}

// Recursive audio file scan (M3: skip hidden dirs without descending; use
// the enumerator's own attributes instead of stat-ing every entry; S7: cap
// at 100k entries / 60s so a hostile root can't wedge the app)
static NSArray *scanAudioFiles(NSString *root) {
  NSMutableArray *found = [NSMutableArray array];
  NSFileManager *fm = NSFileManager.defaultManager;
  NSDirectoryEnumerator *en = [fm enumeratorAtPath:root];
  NSUInteger scanned = 0;
  CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
  for (NSString *rel in en) {
    if (++scanned >= 100000 || CFAbsoluteTimeGetCurrent() - start > 60.0) break;
    NSDictionary *attrs = [en fileAttributes];
    BOOL isDir = [attrs[NSFileType] isEqualToString:NSFileTypeDirectory];
    if (isDir) {
      // Hidden directory (.git, .Trashes, downloader caches): don't descend
      if ([rel.lastPathComponent hasPrefix:@"."]) [en skipDescendants];
      continue;
    }
    if ([rel.lastPathComponent hasPrefix:@"."]) continue; // hidden file
    NSString *full = [root stringByAppendingPathComponent:rel];
    if (fpIsAudioFile(full)) {
      [found addObject:full];
    }
  }
  return found;
}

// S7: scanDirectory is renderer-callable, so it may only enumerate roots the
// user actually picked natively (import NSOpenPanel result, drag-and-drop
// paths) — otherwise it's an arbitrary filesystem enumeration primitive.
static NSMutableOrderedSet *gTrustedScanRoots = nil; // main thread only

static void fpAddTrustedScanRoot(NSString *root) {
  if (root.length == 0) return;
  if (!gTrustedScanRoots) gTrustedScanRoots = [NSMutableOrderedSet new];
  [gTrustedScanRoots addObject:root];
  while (gTrustedScanRoots.count > 128) [gTrustedScanRoots removeObjectAtIndex:0];
}

static BOOL fpIsTrustedScanRoot(NSString *root) {
  NSString *norm = [root stringByStandardizingPath];
  for (NSString *t in gTrustedScanRoots) {
    NSString *tn = [t stringByStandardizingPath];
    if ([norm hasPrefix:[tn stringByAppendingString:@"/"]] || [norm isEqualToString:tn]) return YES;
  }
  return NO;
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
// itself can only be set by the native NSOpenPanel flows. Implemented once
// in paths.mm (Q2), including symlink resolution (S3d).

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

// S6: SSRF guard — https-only (http is tolerated solely for localhost, i.e.
// the dev server), and the host must not resolve to loopback / link-local /
// private / multicast / unspecified addresses. Every resolved address must
// be public: a hostname that resolves to a mix of public + private IPs is
// rejected (getaddrinfo on the bare host, then one check per address).
static BOOL fpUrlAllowed(NSURL *url) {
  if (![url.scheme isEqualToString:@"https"] && ![url.scheme isEqualToString:@"http"]) return NO;
  NSString *host = url.host.lowercaseString;
  if (host.length == 0) return NO;
  if ([url.scheme isEqualToString:@"http"] && ![host isEqualToString:@"localhost"]) return NO;
  if ([host isEqualToString:@"localhost"]) return YES;

  struct addrinfo hints = {};
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  struct addrinfo *res = NULL;
  if (getaddrinfo(host.UTF8String, NULL, &hints, &res) != 0) return NO;
  BOOL allowed = YES;
  for (struct addrinfo *ai = res; ai; ai = ai->ai_next) {
    if (ai->ai_family == AF_INET) {
      uint32_t a = ntohl(((struct sockaddr_in *)ai->ai_addr)->sin_addr.s_addr);
      if (a == 0                 // 0.0.0.0
          || (a >> 24) == 127    // 127.0.0.0/8
          || (a >> 16) == 0xA9FE // 169.254.0.0/16 link-local
          || (a >> 24) == 10     // 10.0.0.0/8
          || (a >> 20) == 0xAC1  // 172.16.0.0/12
          || (a >> 16) == 0xC0A8 // 192.168.0.0/16
          || (a >> 28) == 0xE) { // 224.0.0.0/4 multicast
        allowed = NO;
        break;
      }
    } else if (ai->ai_family == AF_INET6) {
      struct in6_addr *a6 = &((struct sockaddr_in6 *)ai->ai_addr)->sin6_addr;
      if (IN6_IS_ADDR_UNSPECIFIED(a6) || IN6_IS_ADDR_LOOPBACK(a6)
          || IN6_IS_ADDR_LINKLOCAL(a6) || IN6_IS_ADDR_MULTICAST(a6)) {
        allowed = NO;
        break;
      }
    } else {
      allowed = NO;
      break;
    }
  }
  freeaddrinfo(res);
  return allowed;
}

// Shared GET pipeline: validates scheme + host (S6 — never file://, and no
// loopback/private targets), follows redirects only when each hop re-passes
// fpUrlAllowed (cap 5), enforces a size cap, shapes {ok, status,
// retryAfter?, error?}, hands the body to `fill` on success, and hops back
// to the main thread to reply.
static void fpHttpGet(NSString *urlStr, NSNumber *mid, void (^replyBlock)(NSNumber *, id),
                      void (^fill)(NSMutableDictionary *, NSData *)) {
  if (urlStr.length == 0) { replyBlock(mid, @{ @"ok": @NO, @"error": @"empty url" }); return; }
  NSURL *url = [NSURL URLWithString:urlStr];
  if (!url) { replyBlock(mid, @{ @"ok": @NO, @"error": @"bad url" }); return; }
  if (!fpUrlAllowed(url)) { replyBlock(mid, @{ @"ok": @NO, @"error": @"url not allowed" }); return; }

  NSString *ver = NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"dev";
  NSString *ua = [NSString stringWithFormat:@"FreePlayer/%@ (+https://github.com/zprolab/FreePlayer)", ver];

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    __block NSURL *current = url;
    __block BOOL done = NO;
    NSInteger redirects = 0;
    while (!done) {
      NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:current];
      req.timeoutInterval = 10;
      // Descriptive User-Agent — LRCLIB and iTunes both ask clients to
      // identify themselves so abuse is attributable instead of IP-banned.
      [req setValue:ua forHTTPHeaderField:@"User-Agent"];
      dispatch_semaphore_t sem = dispatch_semaphore_create(0);
      __block BOOL loopAgain = NO;
      NSURLSessionDataTask *task = [fpSharedSession() dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
          NSHTTPURLResponse *http = (NSHTTPURLResponse *)resp;
          if (err) {
            result[@"ok"] = @NO;
            result[@"error"] = err.localizedDescription ?: @"network error";
            done = YES;
          } else if (http.statusCode >= 300 && http.statusCode < 400) {
            // Redirect: re-validate the target, then loop (manual follow so
            // every hop passes fpUrlAllowed — the session would follow
            // redirects implicitly otherwise)
            NSString *loc = http.allHeaderFields[@"Location"];
            NSURL *next = loc.length > 0
                ? [NSURL URLWithString:loc relativeToURL:current].absoluteURL : nil;
            if (next && fpUrlAllowed(next)) {
              current = next;
              loopAgain = YES;
            } else {
              result[@"ok"] = @NO;
              result[@"error"] = loc.length ? @"redirect target not allowed" : @"redirect without location";
              done = YES;
            }
          } else if (http.statusCode >= 400) {
            result[@"ok"] = @NO;
            result[@"status"] = @(http.statusCode);
            result[@"error"] = @"http error";
            NSString *ra = http.allHeaderFields[@"Retry-After"];
            if (ra.length > 0) result[@"retryAfter"] = ra;
            done = YES;
          } else if (data.length > kMaxHttpBytes) {
            result[@"ok"] = @NO;
            result[@"error"] = @"response too large";
            done = YES;
          } else {
            result[@"ok"] = @YES;
            result[@"status"] = @(http.statusCode);
            fill(result, data);
            done = YES;
          }
          dispatch_semaphore_signal(sem);
        }];
      [task resume];
      dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
      if (loopAgain) {
        redirects++;
        if (redirects > 5) {
          result[@"ok"] = @NO;
          result[@"error"] = @"too many redirects";
          break;
        }
      }
    }
    dispatch_async(dispatch_get_main_queue(), ^{ replyBlock(mid, result); });
  });
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
  // S7: dropped paths are user-picked natively — trust them as scan roots
  for (NSString *p in paths) fpAddTrustedScanRoot(p);
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

// S16: page console output goes to the system log — truncate and redact
// common secret patterns (Bearer tokens, api keys, passwords, auth headers).
static NSString *fpRedactConsole(NSString *msg) {
  if (msg.length > 300) msg = [msg substringToIndex:300];
  static NSArray<NSRegularExpression *> *res = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSMutableArray *arr = [NSMutableArray array];
    for (NSString *pat in @[
      @"(?i)(Bearer\\s+)[A-Za-z0-9._~+/=-]+",
      @"(?i)(api[_-]?key\\s*[:=]\\s*)[^\\s,;]+",
      @"(?i)(password\\s*[:=]\\s*)[^\\s,;]+",
      @"(?i)(authorization\\s*[:=]\\s*)[^\\s,;]+",
    ]) {
      NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pat options:0 error:nil];
      if (re) [arr addObject:re];
    }
    res = arr;
  });
  for (NSRegularExpression *re in res) {
    msg = [re stringByReplacingMatchesInString:msg options:0
                                         range:NSMakeRange(0, msg.length)
                                  withTemplate:@"$1***"];
  }
  return msg;
}

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
  if (![message.name isEqualToString:@"freeplayer"]) return;
  // S2: only main-frame messages from a webview this app owns — a subframe
  // (or a stray page in another webview) must never reach the bridge.
  if (!message.frameInfo.isMainFrame || !fpIsAppWebView(message.webView)) return;
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
    NSLog(@"[page %@] %@", a.firstObject ?: @"log",
          fpRedactConsole(a.count > 1 && [a[1] isKindOfClass:NSString.class] ? a[1] : @""));
    return;
  }
  if ([method isEqualToString:@"__dragStart"]) {
    // Kick off AppKit's modal window drag with a synthetic mouse event.
    // Q3: JS screenX/screenY are CSS pixels — scale by the backing scale
    // factor, and use the screen that contains the window (multi-screen).
    NSWindow *win = message.webView.window;
    if (!win) return;
    CGFloat scale = win.backingScaleFactor ?: 1.0;
    CGFloat sx = [args.firstObject doubleValue] * scale;
    CGFloat sy = (args.count > 1 ? [args[1] doubleValue] : 0) * scale;
    NSScreen *screen = win.screen ?: NSScreen.mainScreen;
    CGFloat screenH = screen.frame.size.height;
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
      if (![d isKindOfClass:NSDictionary.class]) { reply(idNum, @NO); return; }
      NSString *key = d[@"key"];
      if (![key isKindOfClass:NSString.class] || key.length == 0) { reply(idNum, @NO); return; }
      // NEW-2: library_dir is the trust anchor for the file-read boundary —
      // only the native NSOpenPanel flows (importDialog/selectLibraryDir) may
      // set it; a renderer-writable anchor would let XSS widen the boundary
      // and read arbitrary files via getCover/media:///getLrc.
      if ([key isEqualToString:@"library_dir"]) {
        reply(idNum, @NO);
        return;
      }
      // S3c/Q11: renderer-writable keys are allowlisted — everything else
      // (incl. import_mode with an unvalidated value) is rejected.
      if ([key isEqualToString:@"import_mode"]) {
        NSString *mode = [d[@"value"] description];
        if (![mode isEqualToString:@"copy"] && ![mode isEqualToString:@"symlink"]) {
          reply(idNum, @NO);
          return;
        }
        reply(idNum, @(fpdb::setSetting(key, mode)));
        return;
      }
      static NSSet<NSString *> *plain = nil;
      static dispatch_once_t once;
      dispatch_once(&once, ^{
        plain = [NSSet setWithArray:@[
          @"volume", @"tray_enabled", @"tray_notify", @"start_hidden",
          @"start_on_boot", @"default_volume", @"default_visualizer",
        ]];
      });
      if ([plain containsObject:key]
          || [key hasPrefix:@"plugin."]
          || [key hasPrefix:@"plugin_perms_"]
          || [key hasPrefix:@"meta."]) {
        reply(idNum, @(fpdb::setSetting(key, d[@"value"])));
      } else {
        reply(idNum, @NO);
      }
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
      // S8: the renderer's own confirm dialog is not enough — one IPC call
      // wipes every track/playlist/history entry AND all settings, so gate
      // it behind a native confirmation dialog too.
      NSAlert *alert = [[NSAlert alloc] init];
      alert.alertStyle = NSAlertStyleWarning;
      alert.messageText = @"Reset Database";
      alert.informativeText = @"This will permanently delete all tracks, playlists, listening history, and settings. This cannot be undone.";
      [alert addButtonWithTitle:@"Reset Everything"];
      [alert addButtonWithTitle:@"Cancel"];
      reply(idNum, @([alert runModal] == NSAlertFirstButtonReturn && fpdb::resetDatabase()));
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
      int64_t tid = [args.firstObject longLongValue];
      id track = fpdb::getTrackById(tid);
      BOOL ok = fpdb::deleteTrack(tid);
      // S9: remove the track's cover file (and the .covers dir when it
      // empties) — no orphaned payloads outside the DB
      if (ok && [track isKindOfClass:NSDictionary.class]) {
        NSString *cover = track[@"cover_path"];
        if ([cover isKindOfClass:NSString.class] && cover.length) {
          NSFileManager *fm = NSFileManager.defaultManager;
          if (fpIsPathInLibrary(cover)) {
            [fm removeItemAtPath:cover error:nil];
            [fm removeItemAtPath:cover.stringByDeletingLastPathComponent error:nil];
          }
        }
      }
      reply(idNum, @(ok));
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
      // S14: clamp the limit — a renderer-supplied unbounded LIMIT would
      // serialize the whole history table into one reply
      long limit = [args.firstObject longValue];
      if (limit < 1 || limit > 1000) limit = 50;
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
      if (![coverPath isKindOfClass:NSString.class] || !fpIsPathInLibrary(coverPath)) {
        reply(idNum, NSNull.null);
        return;
      }
      NSNumber *mid = idNum;
      // Q7: base64-encode on the background queue — only the small reply
      // string hops to the main thread
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSData *data = [NSData dataWithContentsOfFile:coverPath];
        NSString *encoded = nil;
        if (data) {
          NSString *ext = coverPath.pathExtension.lowercaseString;
          NSString *mime = [ext isEqualToString:@"png"] ? @"image/png"
                          : [ext isEqualToString:@"webp"] ? @"image/webp"
                          : @"image/jpeg";
          encoded = [NSString stringWithFormat:@"data:%@;base64,%@", mime,
                     [data base64EncodedStringWithOptions:0]];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
          reply(mid, encoded ?: NSNull.null);
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
        if (!fpIsPathInLibrary(lrcPath)) {
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
      if (!fpIsPathInLibrary(lrcPath)) {
        reply(idNum, @NO);
        return;
      }
      reply(idNum, @(fpdb::setTrackLrc([d[@"trackId"] longLongValue], lrcPath)));
    } else if ([method isEqualToString:@"saveLrcContent"]) {
      int64_t tid = [args.firstObject longLongValue];
      NSString *content = args.count > 1 ? args[1] : nil;
      if (![content isKindOfClass:NSString.class]) { reply(idNum, @{ @"success": @NO }); return; }
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
      // S4: belt-and-braces — the target derives from a DB row, but never
      // write outside the library
      if (!fpIsPathInLibrary(target)) {
        reply(idNum, @{ @"success": @NO });
        return;
      }
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
      // S9: unbounded payloads are capped (~5 MB decoded ≈ 7M base64 chars)
      if (b64.length > 7 * 1024 * 1024 || !img || img.length > 5 * 1024 * 1024) {
        reply(idNum, @{ @"success": @NO });
        return;
      }
      CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)img, NULL);
      if (!src) { reply(idNum, @{ @"success": @NO }); return; }
      // S9: only JPEG/PNG/WebP/HEIC are accepted; anything else is rejected
      // instead of being written verbatim (format spoofing)
      UTType *imgType = nil;
      CFStringRef srcType = CGImageSourceGetType(src);
      if (srcType) imgType = [UTType typeWithIdentifier:(__bridge NSString *)srcType];
      BOOL knownFormat = imgType != nil
          && ([imgType conformsToType:UTTypeJPEG] || [imgType conformsToType:UTTypePNG]
              || [imgType conformsToType:UTTypeWebP] || [imgType conformsToType:UTTypeHEIC]);
      if (!knownFormat) {
        CFRelease(src);
        reply(idNum, @{ @"success": @NO });
        return;
      }
      // S9: non-JPEG input is re-encoded to JPEG so the .jpg name is honest
      BOOL isJpeg = [imgType conformsToType:UTTypeJPEG];
      NSData *outImg = img;
      BOOL reencodeOk = YES;
      if (!isJpeg) {
        reencodeOk = NO;
        CGImageRef image = CGImageSourceCreateImageAtIndex(src, 0, NULL);
        if (image) {
          NSMutableData *jpegData = [NSMutableData data];
          CGImageDestinationRef dst = CGImageDestinationCreateWithData(
              (__bridge CFMutableDataRef)jpegData, (__bridge CFStringRef)UTTypeJPEG.identifier, 1, NULL);
          if (dst) {
            NSDictionary *props = @{ (id)kCGImageDestinationLossyCompressionQuality: @0.85 };
            CGImageDestinationAddImage(dst, image, (__bridge CFDictionaryRef)props);
            if (CGImageDestinationFinalize(dst)) {
              outImg = jpegData;
              reencodeOk = YES;
            }
            CFRelease(dst);
          }
          CGImageRelease(image);
        }
      }
      CFRelease(src);
      if (!reencodeOk) {
        reply(idNum, @{ @"success": @NO });
        return;
      }
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
      // S4: belt-and-braces — never write outside the library
      if (!fpIsPathInLibrary(coverPath)) {
        reply(idNum, @{ @"success": @NO });
        return;
      }
      NSError *writeErr = nil;
      BOOL ok = [outImg writeToFile:coverPath options:NSDataWritingAtomic error:&writeErr];
      if (!ok) NSLog(@"[bridge] cover write failed: %@", writeErr);
      if (ok) ok = fpdb::setTrackCover(tid, coverPath);
      reply(idNum, ok ? @{ @"success": @YES, @"coverPath": coverPath } : @{ @"success": @NO });
    } else if ([method isEqualToString:@"removeLrc"]) {
      reply(idNum, @(fpdb::clearTrackLrc([args.firstObject longLongValue])));
    } else if ([method isEqualToString:@"uploadLrc"]) {
      int64_t tid = [args.firstObject longLongValue];
      NSDictionary *track = fpdb::getTrackById(tid);
      if (![track isKindOfClass:NSDictionary.class]) { reply(idNum, @{ @"error": @"Track not found" }); return; }
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
        // S13: never silently overwrite an existing sidecar, and surface
        // write failures instead of pretending the copy succeeded
        if ([NSFileManager.defaultManager fileExistsAtPath:target]) {
          reply(idNum, @{ @"success": @NO, @"error": @"A lyrics file with that name already exists" });
          return;
        }
        if (!fpIsPathInLibrary(target)) {
          reply(idNum, @{ @"success": @NO, @"error": @"target outside library" });
          return;
        }
        NSData *raw = [NSData dataWithContentsOfFile:chosen];
        if (raw) {
          NSError *wErr = nil;
          if (![raw writeToFile:target options:NSDataWritingAtomic error:&wErr]) {
            reply(idNum, @{ @"success": @NO, @"error": wErr.localizedDescription ?: @"write failed" });
            return;
          }
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
      // S7: the panel-selected directory becomes a trusted scan root
      fpAddTrustedScanRoot(sourceDir);
      NSString *libraryDir = fpdb::getSetting(@"library_dir", nil);
      reply(idNum, @{ @"canceled": @NO, @"sourceDir": sourceDir, @"libraryDir": libraryDir ?: NSNull.null });
    } else if ([method isEqualToString:@"scanDirectory"]) {
      // S7: only roots the user picked natively may be enumerated — a
      // renderer-supplied root is an arbitrary filesystem scan otherwise
      NSString *dir = args.firstObject;
      if (![dir isKindOfClass:NSString.class] || !fpIsTrustedScanRoot(dir)) {
        reply(idNum, @[]);
        return;
      }
      // M3: directory walk off the main thread; S5: the walk itself can
      // throw (enumerator quirks) — never let it crash the app
      NSNumber *mid = idNum;
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @try {
          NSArray *files = scanAudioFiles(dir);
          dispatch_async(dispatch_get_main_queue(), ^{ reply(mid, files); });
        } @catch (NSException *e) {
          NSLog(@"[bridge] scanDirectory exception: %@", e);
          dispatch_async(dispatch_get_main_queue(), ^{ reject(mid, e.reason ?: @"scan failed"); });
        }
      });
    } else if ([method isEqualToString:@"importFiles"]) {
      // S5: validate the payload shape BEFORE touching a background queue —
      // malformed args must never reach the importer
      NSDictionary *data = args.firstObject;
      NSArray *files = data[@"files"];
      if (![data isKindOfClass:NSDictionary.class] || ![files isKindOfClass:NSArray.class]) {
        reply(idNum, @{ @"imported": @0, @"errors": @[], @"error": @"bad import payload" });
        return;
      }
      for (id f in files) {
        if (![f isKindOfClass:NSString.class]) {
          reply(idNum, @{ @"imported": @0, @"errors": @[], @"error": @"bad import payload" });
          return;
        }
      }
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

      // M12: count in-flight imports so app termination can wait for them.
      // Q1: the dispatch group is the completion signal the termination path
      // waits on — the old poll loop could race sqlite3_close.
      gImportTasks.fetch_add(1);
      dispatch_group_enter(fpImportGroup());

      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @try {
        // H4: extract metadata concurrently (bounded), keep order-insensitive
        dispatch_queue_t extractQ = dispatch_queue_create("fp.extract", DISPATCH_QUEUE_CONCURRENT);
        dispatch_queue_t collectQ = dispatch_queue_create("fp.collect", DISPATCH_QUEUE_SERIAL);
        dispatch_group_t group = dispatch_group_create();
        NSMutableArray *prepared = [NSMutableArray array];
        for (NSString *filePath in files) {
          // S3b: only audio files may enter the library — everything else is
          // skipped with a recorded error (defense in depth on the source
          // paths, which the renderer controls)
          if (!fpIsAudioFile(filePath)) {
            [errors addObject:@{ @"file": filePath, @"error": @"not an audio file" }];
            continue;
          }
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
          @try {
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
              // S4: replace path separators AND "."/".." components with
              // underscores — ".." in artist/album tags must never escape
              // the library (pathWithComponents + createDirectoryAtPath
              // would happily create dirs outside storedLib)
              auto safe = ^NSString *(NSString *s) {
                if (![s isKindOfClass:NSString.class]) return @"";
                NSMutableArray *parts = [NSMutableArray array];
                for (NSString *c in [s componentsSeparatedByString:@"/"]) {
                  [parts addObject:([c isEqualToString:@"."] || [c isEqualToString:@".."]) ? @"_" : c];
                }
                return [parts componentsJoinedByString:@"_"];
              };
              NSString *artist = safe(meta[@"artist"]);
              NSString *album = safe(meta[@"album"]);
              NSString *albumDir = [NSString pathWithComponents:@[ storedLib, artist, album ]];
              // S4: belt-and-braces — the sanitized dir must still be inside
              // the (standardized) library
              if (!fpIsPathInLibrary(albumDir)) {
                [errors addObject:@{ @"file": filePath, @"error": @"unsafe album path" }];
                continue;
              }
              // Q5: every file op records its failure into `errors` instead
              // of being silently dropped (UNIQUE collisions etc.)
              NSError *err = nil;
              if (![fm fileExistsAtPath:albumDir]
                  && ![fm createDirectoryAtPath:albumDir withIntermediateDirectories:YES attributes:nil error:&err]) {
                [errors addObject:@{ @"file": filePath, @"error": err.localizedDescription ?: @"directory creation failed" }];
                continue;
              }
              NSString *targetPath = [albumDir stringByAppendingPathComponent:baseName];
              BOOL exists = [fm fileExistsAtPath:targetPath];
              if (!exists) {
                if ([importMode isEqualToString:@"symlink"]) {
                  NSError *lErr = nil;
                  if (![fm createSymbolicLinkAtPath:targetPath withDestinationPath:filePath error:&lErr]) {
                    [errors addObject:@{ @"file": filePath, @"error": lErr.localizedDescription ?: @"symlink failed" }];
                    continue;
                  }
                } else {
                  NSError *cErr = nil;
                  if (![fm copyItemAtPath:filePath toPath:targetPath error:&cErr]) {
                    [errors addObject:@{ @"file": filePath, @"error": cErr.localizedDescription ?: @"copy failed" }];
                    continue;
                  }
                }
              }

              // Cover art -> <albumDir>/.covers/cover.ext
              NSString *coverPath = nil;
              NSData *artwork = meta[@"artwork"];
              if (artwork) {
                NSString *coverDir = [albumDir stringByAppendingPathComponent:@".covers"];
                if (![fm fileExistsAtPath:coverDir]) {
                  NSError *dErr = nil;
                  if (![fm createDirectoryAtPath:coverDir withIntermediateDirectories:YES attributes:nil error:&dErr]) {
                    NSLog(@"[bridge] cover dir create failed: %@", dErr);
                  }
                }
                coverPath = [coverDir stringByAppendingPathComponent:@"cover.jpg"];
                if (![fm fileExistsAtPath:coverPath]) {
                  NSError *wErr = nil;
                  if (![artwork writeToFile:coverPath options:NSDataWritingAtomic error:&wErr]) {
                    NSLog(@"[bridge] cover write failed: %@", wErr);
                    coverPath = nil; // keep the track, drop only the cover
                  }
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
          // on busy_timeout while it is). Q5: failed inserts are counted and
          // reported instead of being ignored.
          const NSUInteger insertBatch = 50;
          for (NSUInteger i = 0; i < tracksToInsert.count; i += insertBatch) {
            BOOL tx = fpdb::beginTransaction();
            NSUInteger end = MIN(i + insertBatch, tracksToInsert.count);
            for (NSUInteger j = i; j < end; j++) {
              NSDictionary *td = tracksToInsert[j];
              if (!fpdb::insertTrack(td)) {
                [errors addObject:@{ @"file": td[@"file_path"] ?: @"?", @"error": @"database insert failed" }];
                imported--;
              }
            }
            if (tx) fpdb::commitTransaction();
          }
          NSDictionary *result = @{
            @"imported": @(imported),
            @"skipped": @(skipped),
            @"errors": errors,
          };
          gImportTasks.fetch_sub(1);
          dispatch_group_leave(fpImportGroup());
          dispatch_async(dispatch_get_main_queue(), ^{
            reply(mid, result);
          });
          } @catch (NSException *e) {
            NSLog(@"[bridge] import exception: %@\n%@", e, [e callStackSymbols]);
            gImportTasks.fetch_sub(1);
            dispatch_group_leave(fpImportGroup());
            dispatch_async(dispatch_get_main_queue(), ^{
              reject(mid, e.reason ?: @"import failed");
            });
          }
        });
        } @catch (NSException *e) {
          NSLog(@"[bridge] import exception: %@\n%@", e, [e callStackSymbols]);
          gImportTasks.fetch_sub(1);
          dispatch_group_leave(fpImportGroup());
          dispatch_async(dispatch_get_main_queue(), ^{
            reject(mid, e.reason ?: @"import failed");
          });
        }
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
      BOOL hidden = fptraySettingBool(@"start_hidden", NO);
      reply(idNum, @{ @"openAtLogin": @(fptrayLoginItemEnabled()),
                      @"openAsHidden": @(hidden) });
    } else if ([method isEqualToString:@"setLoginItemSettings"]) {
      NSDictionary *d = args.firstObject;
      if (d[@"openAsHidden"] != nil) {
        fpdb::setSetting(@"start_hidden", [d[@"openAsHidden"] boolValue] ? @"1" : @"0");
      }
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
