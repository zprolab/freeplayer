// FreePlayer shell — app entry: frameless window + WKWebView
// Mirrors the Electron shell's chrome: hidden title bar (hiddenInset),
// traffic lights at (16, 14), full-size content view.

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#include "db.h"
#include "bridge.h"
#include "tray.h"
#include "webview.h"

@interface MediaSchemeHandler : NSObject <WKURLSchemeHandler>
@end
@interface BridgeHandler : NSObject <WKScriptMessageHandler>
@end

void fpSetWebRoot(NSString *root);

// WebKit does NOT retain scheme handlers / (per docs) message handlers —
// keep strong globals for the app lifetime to avoid dangling dealloc.
MediaSchemeHandler *gScheme = nil;
BridgeHandler *gBridge = nil;
WKWebView *gWebView = nil;
NSWindow *gWindow = nil;

// ── App lifecycle ──
@interface ShellAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property (nonatomic, strong) id backgroundActivity;
@end

@implementation ShellAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  if (!fpdb::open(fpdb::defaultDbPath())) {
    NSLog(@"[shell] FATAL: db open failed");
    [NSApp terminate:nil];
    return;
  }

  NSRect frame = NSMakeRect(0, 0, 1280, 820);
  NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                 styleMask:(NSWindowStyleMaskTitled |
                                                            NSWindowStyleMaskClosable |
                                                            NSWindowStyleMaskMiniaturizable |
                                                            NSWindowStyleMaskResizable |
                                                            NSWindowStyleMaskFullSizeContentView)
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO];
  window.title = @"FreePlayer";
  window.titlebarAppearsTransparent = YES;
  window.titleVisibility = NSWindowTitleHidden;
  // Programmatic windows default to releasedWhenClosed=YES, which over-releases
  // the window (AppKit registry + our own reference) at close → SIGSEGV at exit.
  window.releasedWhenClosed = NO;
  window.backgroundColor = [NSColor colorWithSRGBRed:0.13 green:0.13 blue:0.15 alpha:1.0];
  window.minSize = NSMakeSize(960, 600);
  window.delegate = self;
  gWindow = window;
  NSLog(@"[shell] window delegate set: %@", window.delegate ? @"yes" : @"NO");
  [window center];

  // Prod/dev decision FIRST — WKWebViewConfiguration is copied at
  // initWithFrame:configuration:, so everything must be set before.
  NSUserDefaults *defs = NSUserDefaults.standardUserDefaults;
  NSString *webRoot = nil;
  if ([[[NSBundle mainBundle] bundlePath] hasSuffix:@".app"]) {
    webRoot = [[NSBundle mainBundle].resourcePath stringByAppendingPathComponent:@"web"];
  }
  NSString *defRoot = [defs stringForKey:@"FP_WEB_ROOT"];
  if (defRoot.length > 0) webRoot = defRoot;
  NSString *envRoot = NSProcessInfo.processInfo.environment[@"FP_WEB_ROOT"];
  if (envRoot.length > 0) webRoot = envRoot;

  WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
  config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
  config.preferences.javaScriptCanOpenWindowsAutomatically = NO;
  if (webRoot.length > 0 && [NSFileManager.defaultManager fileExistsAtPath:webRoot]) {
    // Prod: no persistent cache/disk store needed
    config.websiteDataStore = WKWebsiteDataStore.nonPersistentDataStore;
  }

  gScheme = [[MediaSchemeHandler alloc] init];
  [config setURLSchemeHandler:gScheme forURLScheme:@"media"];
  [config setURLSchemeHandler:gScheme forURLScheme:@"app"];

  gBridge = [[BridgeHandler alloc] init];
  [config.userContentController addScriptMessageHandler:gBridge name:@"freeplayer"];

  WKUserScript *bridgeScript = [[WKUserScript alloc]
      initWithSource:fpBridgeScript()
       injectionTime:WKUserScriptInjectionTimeAtDocumentStart
    forMainFrameOnly:YES];
  [config.userContentController addUserScript:bridgeScript];

  ShellWebView *webView = [[ShellWebView alloc] initWithFrame:frame configuration:config];
  webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  gWebView = webView;
  window.contentView = webView;

  [window makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];

  [FpTray create];

  // Deterministic close for teardown debugging: FP_AUTOCLOSE_SECONDS
  NSString *autoClose = NSProcessInfo.processInfo.environment[@"FP_AUTOCLOSE_SECONDS"];
  if (autoClose.length > 0) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(autoClose.doubleValue * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
      NSLog(@"[shell] auto-closing window");
      [window close];
    });
  }

  NSURL *loadURL = nil;
  if (webRoot.length > 0 && [NSFileManager.defaultManager fileExistsAtPath:webRoot]) {
    fpSetWebRoot(webRoot);
    loadURL = [NSURL URLWithString:@"app://index.html"];
    NSLog(@"[shell] prod mode, webRoot=%@", webRoot);
  } else {
    NSString *url = [defs stringForKey:@"FP_URL"];
    if (url.length == 0) url = NSProcessInfo.processInfo.environment[@"FP_URL"];
    if (url.length == 0) url = @"http://localhost:5173";
    loadURL = [NSURL URLWithString:url];
    NSLog(@"[shell] dev mode, loading %@", url);
  }
  [webView loadRequest:[NSURLRequest requestWithURL:loadURL]];
}

// ── Close-to-tray: a music player must survive window close ──

- (void)setBackgroundPlayback:(BOOL)enabled {
  if (enabled && !self.backgroundActivity) {
    // Keeps App Nap from throttling hidden background playback
    self.backgroundActivity = [NSProcessInfo.processInfo
        beginActivityWithOptions:NSActivityBackground reason:@"Background audio playback"];
  } else if (!enabled && self.backgroundActivity) {
    [NSProcessInfo.processInfo endActivity:self.backgroundActivity];
    self.backgroundActivity = nil;
  }
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
  BOOL trayOn = fptraySettingBool(@"tray_enabled", YES);
  if (trayOn) {
    [sender orderOut:nil]; // hide, keep playing in the tray
    [self setBackgroundPlayback:YES];
    fptrayShowHiddenNotification();
    return NO;
  }
  // Tray disabled: closing the window quits the app explicitly
  [NSApp terminate:nil];
  return NO;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
  if (!flag && gWindow) {
    [gWindow makeKeyAndOrderFront:nil];
  }
  return YES;
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
  [self setBackgroundPlayback:NO];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
  // Close-to-tray: orderOut during performClose can look like a window close;
  // never auto-terminate here — windowShouldClose decides instead.
  return NO;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
  fpdb::close();
}

@end

int main(int, const char *[]) {
  @autoreleasepool {
    NSApplication *app = [NSApplication sharedApplication];
    [app setActivationPolicy:NSApplicationActivationPolicyRegular];
    ShellAppDelegate *delegate = [[ShellAppDelegate alloc] init];
    app.delegate = delegate;
    [app run];
  }
  return 0;
}
