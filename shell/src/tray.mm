// FreePlayer shell — tray (M5): status item, playback menu, media keys,
// login item. Communicates with the webview via evaluateJavaScript.
// NOTE: no ObjC objects are ever passed back from evaluateJavaScript
// completions — all state crosses the bridge as plain JSON via messages.

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <ServiceManagement/ServiceManagement.h>
#import <ServiceManagement/SMAppService.h>
#import <UserNotifications/UserNotifications.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include "tray.h"
#include "db.h"

static NSStatusItem *gStatusItem = nil;
static NSMenuItem *gPlayPauseItem = nil;
static NSMenuItem *gNowPlayingItem = nil;
static NSMenu *gMenu = nil; // NSStatusItem.menu is not reliably retained
static NSString *gTrackTitle = @"";
static NSString *gTrackArtist = @"";
static BOOL gPlaying = NO;
static int64_t gNowPlayingGen = 0; // #6: stale-cover guard (main thread only)
static FpTray *gTray = nil; // instance target for menu actions

static NSString *nowPlayingLabel(void) {
  if (gTrackTitle.length == 0) return @"♪ Nothing playing";
  if (gTrackArtist.length == 0) return [NSString stringWithFormat:@"♪ %@", gTrackTitle];
  return [NSString stringWithFormat:@"♪ %@ — %@", gTrackTitle, gTrackArtist];
}

static void pushToWebview(NSString *fn, NSString *action) {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (gWebView) {
      NSString *js = [NSString stringWithFormat:@"window.freeplayer.%@('%@')", fn, action];
      [gWebView evaluateJavaScript:js completionHandler:nil];
    }
  });
}

@implementation FpTray

+ (void)create {
  gTray = [FpTray new];
  gStatusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
  gStatusItem.button.title = @"▶";
  gStatusItem.button.toolTip = @"FreePlayer";

  NSMenu *menu = [[NSMenu alloc] init];

  gNowPlayingItem = [[NSMenuItem alloc] initWithTitle:nowPlayingLabel() action:nil keyEquivalent:@""];
  gNowPlayingItem.enabled = NO;
  [menu addItem:gNowPlayingItem];
  [menu addItem:NSMenuItem.separatorItem];

  gPlayPauseItem = [[NSMenuItem alloc] initWithTitle:@"Play/Pause" action:@selector(playPause) keyEquivalent:@""];
  gPlayPauseItem.target = gTray;
  [menu addItem:gPlayPauseItem];

  NSMenuItem *next = [[NSMenuItem alloc] initWithTitle:@"Next Track" action:@selector(nextTrack) keyEquivalent:@""];
  next.target = gTray;
  [menu addItem:next];

  NSMenuItem *prev = [[NSMenuItem alloc] initWithTitle:@"Previous Track" action:@selector(prevTrack) keyEquivalent:@""];
  prev.target = gTray;
  [menu addItem:prev];

  [menu addItem:NSMenuItem.separatorItem];

  NSMenuItem *show = [[NSMenuItem alloc] initWithTitle:@"Show FreePlayer" action:@selector(showWindow) keyEquivalent:@""];
  show.target = gTray;
  [menu addItem:show];

  NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit FreePlayer" action:@selector(quitApp) keyEquivalent:@""];
  quit.target = gTray;
  [menu addItem:quit];

  gStatusItem.menu = menu;
  gMenu = menu; // keep the menu (and its items) alive for the app lifetime

  // M14: request notification permission up front (UNUserNotificationCenter
  // requires it; the tray-hide notification then just works). Dev binaries
  // (no .app bundle) must skip this — the API throws
  // "bundleProxyForCurrentProcess is nil" outside a proper bundle.
  if ([NSBundle.mainBundle.bundlePath hasSuffix:@".app"]) {
    [UNUserNotificationCenter.currentNotificationCenter
        requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound)
                      completionHandler:^(BOOL __unused granted, NSError *__unused err) {}];
  }

  NSLog(@"[tray] created; login item enabled=%d", fptrayLoginItemEnabled());

  // Media keys (macOS Control Center / keyboard media keys)
  MPRemoteCommandCenter *cc = MPRemoteCommandCenter.sharedCommandCenter;
  [cc.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *__unused e) {
    pushToWebview(@"_pushMediaKey", @"playpause"); return MPRemoteCommandHandlerStatusSuccess;
  }];
  [cc.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *__unused e) {
    pushToWebview(@"_pushMediaKey", @"playpause"); return MPRemoteCommandHandlerStatusSuccess;
  }];
  [cc.togglePlayPauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *__unused e) {
    pushToWebview(@"_pushMediaKey", @"playpause"); return MPRemoteCommandHandlerStatusSuccess;
  }];
  [cc.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *__unused e) {
    pushToWebview(@"_pushMediaKey", @"next"); return MPRemoteCommandHandlerStatusSuccess;
  }];
  [cc.previousTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *__unused e) {
    pushToWebview(@"_pushMediaKey", @"previous"); return MPRemoteCommandHandlerStatusSuccess;
  }];
}

+ (void)setPlaying:(BOOL)playing {
  gPlaying = playing;
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!gStatusItem || !gStatusItem.button || !gPlayPauseItem) return;
    gStatusItem.button.title = gPlaying ? @"⏸" : @"▶";
    gPlayPauseItem.title = gPlaying ? @"Pause" : @"Play";
    // Control Center: keep the playback rate in sync (system advances the
    // progress bar from ElapsedPlaybackTime + rate + duration)
    MPNowPlayingInfoCenter *np = MPNowPlayingInfoCenter.defaultCenter;
    NSMutableDictionary *info = [np.nowPlayingInfo mutableCopy];
    if (info) {
      info[MPNowPlayingInfoPropertyPlaybackRate] = gPlaying ? @1.0 : @0.0;
      np.nowPlayingInfo = info;
    }
  });
}

// Safe path: track info comes from the DB (bridge playStart), never from
// WebKit-owned objects. Also feeds Control Center (title/artist/artwork).
+ (void)setNowPlayingFromTrack:(NSDictionary *)track {
  gTrackTitle = [track[@"title"] isKindOfClass:NSString.class] ? track[@"title"] : @"";
  gTrackArtist = [track[@"artist"] isKindOfClass:NSString.class] ? track[@"artist"] : @"";
  NSString *album = [track[@"album"] isKindOfClass:NSString.class] ? track[@"album"] : nil;
  double dur = [track[@"duration"] doubleValue];
  NSString *cover = [track[@"cover_path"] isKindOfClass:NSString.class] ? track[@"cover_path"] : nil;
  // #6: generation guard — two rapid track changes decode out of order; only
  // the latest generation may publish to Control Center
  int64_t gen = ++gNowPlayingGen;
  // L4: decode the cover image off the main thread (fires on every track change)
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSImage *img = cover.length > 0 ? [[NSImage alloc] initWithContentsOfFile:cover] : nil;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (gen != gNowPlayingGen) return; // a newer track won the race
      if (gNowPlayingItem) gNowPlayingItem.title = nowPlayingLabel();
      if (gStatusItem) gStatusItem.button.toolTip = gTrackTitle.length ? gTrackTitle : @"FreePlayer";

      NSMutableDictionary *info = [NSMutableDictionary dictionary];
      if (gTrackTitle.length) info[MPMediaItemPropertyTitle] = gTrackTitle;
      if (gTrackArtist.length) info[MPMediaItemPropertyArtist] = gTrackArtist;
      if (album.length) info[MPMediaItemPropertyAlbumTitle] = album;
      if (dur > 0) info[MPMediaItemPropertyPlaybackDuration] = @(dur);
      if (img) {
        info[MPMediaItemPropertyArtwork] = [[MPMediaItemArtwork alloc]
            initWithBoundsSize:NSMakeSize(600, 600)
                 requestHandler:^NSImage *(CGSize __unused size) { return img; }];
      }
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @0;
      info[MPNowPlayingInfoPropertyPlaybackRate] = gPlaying ? @1.0 : @0.0;
      MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = info;
    });
  });
}

// ── menu actions ──
- (void)playPause { NSLog(@"[tray] menu: playPause"); pushToWebview(@"_pushControl", @"playpause"); }
- (void)nextTrack { NSLog(@"[tray] menu: next"); pushToWebview(@"_pushControl", @"next"); }
- (void)prevTrack { NSLog(@"[tray] menu: prev"); pushToWebview(@"_pushControl", @"previous"); }
- (void)showWindow {
  dispatch_async(dispatch_get_main_queue(), ^{
    [NSApp activateIgnoringOtherApps:YES];
    if (gWindow) {
      [gWindow makeKeyAndOrderFront:nil];
    }
  });
}
- (void)quitApp {
  dispatch_async(dispatch_get_main_queue(), ^{
    [NSApp terminate:nil];
  });
}

@end

// ── Login item (M5) ──

BOOL fptrayLoginItemEnabled(void) {
  if (@available(macOS 13.0, *)) {
    @try {
      return SMAppService.mainAppService.status == SMAppServiceStatusEnabled;
    } @catch (NSException *e) {
      return NO;
    }
  }
  return NO;
}

BOOL fptraySetLoginItem(BOOL enabled) {
  if (@available(macOS 13.0, *)) {
    NSError *err = nil;
    BOOL ok = enabled
      ? [SMAppService.mainAppService registerAndReturnError:&err]
      : [SMAppService.mainAppService unregisterAndReturnError:&err];
    if (!ok) {
      NSLog(@"[tray] login item %@ failed: %@", enabled ? @"register" : @"unregister",
            err ?: @"unknown error");
    }
    return ok;
  }
  return NO;
}

// Coerce a DB setting (may be NSString or NSNumber) to a boolean
BOOL fptraySettingBool(NSString *key, BOOL fallback) {
  id val = fpdb::getSetting(key, nil);
  if (val == nil || [val isKindOfClass:NSNull.class]) return fallback;
  if ([val isKindOfClass:NSNumber.class]) return [val boolValue];
  if ([val isKindOfClass:NSString.class]) {
    NSString *s = [(NSString *)val lowercaseString];
    return [s isEqualToString:@"true"] || [s isEqualToString:@"1"]
        || [s isEqualToString:@"1.0"] || [s isEqualToString:@"yes"]
        || [s isEqualToString:@"on"] || [val boolValue];
  }
  return fallback;
}

// Notification when minimized to tray (tray_notify setting)
void fptrayShowHiddenNotification(void) {
  if (!fptraySettingBool(@"tray_notify", YES)) return;
  if (![NSBundle.mainBundle.bundlePath hasSuffix:@".app"]) return; // dev binary: no notifications
  @try {
    UNUserNotificationCenter *center = UNUserNotificationCenter.currentNotificationCenter;
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
      if (settings.authorizationStatus != UNAuthorizationStatusAuthorized
          && settings.authorizationStatus != UNAuthorizationStatusProvisional) {
        return;
      }
      UNMutableNotificationContent *c = [UNMutableNotificationContent new];
      c.title = @"FreePlayer";
      c.body = @"App is still running in the system tray";
      UNNotificationRequest *req = [UNNotificationRequest requestWithIdentifier:@"tray-hide-notify"
                                                                        content:c trigger:nil];
      [center addNotificationRequest:req withCompletionHandler:nil];
    }];
  } @catch (NSException *e) {
    NSLog(@"[tray] notification unavailable: %@", e.reason ?: @"?");
  }
}
