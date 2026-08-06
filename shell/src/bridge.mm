// FreePlayer shell — JS<->native bridge
// Injects window.freeplayer (mirror of electron/preload.js), console capture,
// and a window-drag shim (WKWebView has no -webkit-app-region support).

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#include "db.h"
#include "bridge.h"
#include "metadata.h"
#include "tray.h"

static const char *kAudioExtensions[] = { "mp3", "flac", "m4a", "aac", "ogg", "wav", "opus", "mp4" };

static BOOL isAudioFile(NSString *path) {
  NSString *ext = path.pathExtension.lowercaseString;
  for (const char *e : kAudioExtensions) {
    if ([ext isEqualToString:@(e)]) return YES;
  }
  return NO;
}

// Recursive audio file scan
static NSArray *scanAudioFiles(NSString *root) {
  NSMutableArray *found = [NSMutableArray array];
  NSFileManager *fm = NSFileManager.defaultManager;
  NSDirectoryEnumerator *en = [fm enumeratorAtPath:root];
  for (NSString *rel in en) {
    if ([rel hasPrefix:@"."]) continue; // hidden dirs/files
    NSString *full = [root stringByAppendingPathComponent:rel];
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:full isDirectory:&isDir]) {
      if (isDir) {
        if ([rel hasPrefix:@"."]) [en skipDescendants];
      } else if (isAudioFile(full)) {
        [found addObject:full];
      }
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
    // Media keys / tray (M5)
    onMediaKey: (callback) => { window.__freeplayerMediaKeyHandler = callback; },
    sendPlaybackState: (isPlaying) => api._invoke('sendPlaybackState', { isPlaying }),
    onPlaybackControl: (callback) => { window.__freeplayerPlaybackHandler = callback; },
    // Login item (M5)
    getLoginItemSettings: () => api._invoke('getLoginItemSettings'),
    setLoginItemSettings: (data) => api._invoke('setLoginItemSettings', data),
    // Native file drop -> renderer import flow
    onDropFiles: (callback) => { window.__freeplayerDropHandler = callback; },
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
  auto reject = ^(NSNumber *mid, NSString *why) {
    NSString *escaped = [why stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
    NSString *js = [NSString stringWithFormat:@"window.freeplayer._reject(%ld, '%@')",
                    (long)mid.integerValue, escaped];
    [message.webView evaluateJavaScript:js completionHandler:nil];
  };

  NSLog(@"[shell] method=%@", method);

  @try {
    // ── Settings / setup ──
    if ([method isEqualToString:@"isSetup"]) {
      NSString *dir = fpdb::getSetting(@"library_dir", nil);
      reply(idNum, @{ @"setup": dir ? @YES : @NO, @"libraryDir": dir ?: NSNull.null });
    } else if ([method isEqualToString:@"getSetting"]) {
      reply(idNum, fpdb::getSetting(args.firstObject, nil) ?: NSNull.null);
    } else if ([method isEqualToString:@"setSetting"]) {
      NSDictionary *d = args.firstObject;
      reply(idNum, @(fpdb::setSetting(d[@"key"], d[@"value"])));
    } else if ([method isEqualToString:@"resetDatabase"]) {
      reply(idNum, @(fpdb::resetDatabase()));
    }
    // ── Tracks ──
    else if ([method isEqualToString:@"getTracks"]) {
      NSDictionary *p = args.firstObject;
      reply(idNum, fpdb::getAllTracks(p[@"search"] ?: @"", p[@"sortBy"] ?: @"imported_at", p[@"sortDir"] ?: @"DESC"));
    } else if ([method isEqualToString:@"getTrack"]) {
      reply(idNum, fpdb::getTrackById([args.firstObject longLongValue]));
    } else if ([method isEqualToString:@"updateTrack"]) {
      NSDictionary *d = args.firstObject;
      reply(idNum, @(fpdb::updateTrack([d[@"id"] longLongValue], d)));
    } else if ([method isEqualToString:@"deleteTrack"]) {
      reply(idNum, @(fpdb::deleteTrack([args.firstObject longLongValue])));
    } else if ([method isEqualToString:@"getTrackCount"]) {
      reply(idNum, @(fpdb::getTrackCount()));
    } else if ([method isEqualToString:@"getTotalDuration"]) {
      reply(idNum, @(fpdb::getTotalDuration()));
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
    // ── Stats ──
    else if ([method isEqualToString:@"getPlayHistory"]) {
      reply(idNum, fpdb::getPlayHistory([args.firstObject longValue] ?: 50));
    } else if ([method isEqualToString:@"getStats"]) {
      reply(idNum, fpdb::getListeningStats());
    }
    // ── Cover art ──
    else if ([method isEqualToString:@"getCover"]) {
      NSString *coverPath = args.firstObject;
      NSData *data = [NSData dataWithContentsOfFile:coverPath];
      if (data) {
        NSString *ext = coverPath.pathExtension.lowercaseString;
        NSString *mime = [ext isEqualToString:@"png"] ? @"image/png"
                        : [ext isEqualToString:@"webp"] ? @"image/webp"
                        : @"image/jpeg";
        reply(idNum, [NSString stringWithFormat:@"data:%@;base64,%@", mime, [data base64EncodedStringWithOptions:0]]);
      } else {
        reply(idNum, NSNull.null);
      }
    }
    // ── Playlists ──
    else if ([method isEqualToString:@"getPlaylists"]) {
      reply(idNum, fpdb::getAllPlaylists());
    } else if ([method isEqualToString:@"createPlaylist"]) {
      NSDictionary *d = args.firstObject;
      reply(idNum, @{ @"lastInsertRowid": @(fpdb::createPlaylist(d[@"name"], d[@"description"])) });
    } else if ([method isEqualToString:@"renamePlaylist"]) {
      NSDictionary *d = args.firstObject;
      reply(idNum, @(fpdb::renamePlaylist([d[@"id"] longLongValue], d[@"name"])));
    } else if ([method isEqualToString:@"deletePlaylist"]) {
      reply(idNum, @(fpdb::deletePlaylist([args.firstObject longLongValue])));
    } else if ([method isEqualToString:@"getPlaylistTracks"]) {
      reply(idNum, fpdb::getPlaylistTracks([args.firstObject longLongValue]));
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
      reply(idNum, @(fpdb::setTrackLrc([d[@"trackId"] longLongValue], d[@"lrcPath"])));
    } else if ([method isEqualToString:@"removeLrc"]) {
      reply(idNum, @(fpdb::clearTrackLrc([args.firstObject longLongValue])));
    } else if ([method isEqualToString:@"uploadLrc"]) {
      int64_t tid = [args.firstObject longLongValue];
      NSDictionary *track = fpdb::getTrackById(tid);
      if ([track isKindOfClass:NSNull.class]) { reply(idNum, @{ @"error": @"Track not found" }); return; }
      NSOpenPanel *panel = [NSOpenPanel openPanel];
      panel.title = @"Select LRC Lyrics File";
      panel.allowedFileTypes = @[ @"lrc" ];
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
        }
        fpdb::setTrackLrc(tid, chosen);
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
      if (!libraryDir) {
        NSOpenPanel *libPanel = [NSOpenPanel openPanel];
        libPanel.title = @"Select destination library directory";
        libPanel.canChooseFiles = NO;
        libPanel.canChooseDirectories = YES;
        libPanel.canCreateDirectories = YES;
        if ([libPanel runModal] != NSModalResponseOK) {
          reply(idNum, @{ @"canceled": @YES });
          return;
        }
        libraryDir = libPanel.URL.path;
        fpdb::setSetting(@"library_dir", libraryDir);
      }
      reply(idNum, @{ @"canceled": @NO, @"sourceDir": sourceDir, @"libraryDir": libraryDir });
    } else if ([method isEqualToString:@"scanDirectory"]) {
      NSArray *files = scanAudioFiles(args.firstObject);
      reply(idNum, files);
    } else if ([method isEqualToString:@"importFiles"]) {
      NSDictionary *data = args.firstObject;
      NSArray *files = data[@"files"];
      NSString *libraryDir = data[@"libraryDir"];
      NSString *importMode = fpdb::getSetting(@"import_mode", @"copy"); // copy | symlink
      NSMutableArray *errors = [NSMutableArray array];
      __block NSInteger imported = 0, skipped = 0;

      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        for (NSString *filePath in files) {
          @autoreleasepool {
            NSString *baseName = filePath.lastPathComponent;
            NSString *ext = filePath.pathExtension.lowercaseString;
            // Replace path separators with underscores to match the electron app
            auto safe = ^NSString *(NSString *s) {
              return [s stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
            };
            NSDictionary *meta = fpmeta::extractAtPath(filePath);
            if (!meta) {
              [errors addObject:@{ @"file": filePath, @"error": @"Unreadable audio file" }];
              continue;
            }
            NSString *artist = safe(meta[@"artist"]);
            NSString *album = safe(meta[@"album"]);
            NSString *albumDir = [NSString pathWithComponents:@[ libraryDir, artist, album ]];
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

            fpdb::insertTrack(trackData);
            if (exists) skipped++; else imported++;
          }
        }
        NSDictionary *result = @{
          @"imported": @(imported),
          @"skipped": @(skipped),
          @"errors": errors,
        };
        dispatch_async(dispatch_get_main_queue(), ^{
          reply(idNum, result);
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
    } else {
      reject(idNum, [NSString stringWithFormat:@"not implemented: %@", method]);
    }
  } @catch (NSException *e) {
    NSLog(@"[shell] handler exception for %@: %@\n%@", method, e, [e callStackSymbols]);
    reject(idNum, e.reason ?: @"internal error");
  }
}

@end
