// FreePlayer shell — app entry: frameless window + WKWebView
// Mirrors the Electron shell's chrome: hidden title bar (hiddenInset),
// traffic lights at (16, 14), full-size content view.

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#include "db.h"
#include "bridge.h"
#include "tray.h"
#include "webview.h"
#include "paths.h"

@interface MediaSchemeHandler : NSObject <WKURLSchemeHandler>
@end
@interface BridgeHandler : NSObject <WKScriptMessageHandler>
@end

// S1: navigation lockdown — the bridge user script is injected on every
// main-frame load and gBridge stays registered across navigations, so a
// renderer redirect to any https:// page hands the attacker the whole
// window.freeplayer surface. Main-frame navigations may only go to app://
// (bundled UI, eq, onboarding) or, in dev binaries, the same origin the
// shell was configured to load.

@class FpNavGate; // navigation lockdown delegate (defined below)

// WebKit does NOT retain scheme handlers / (per docs) message handlers —
// keep strong globals for the app lifetime to avoid dangling dealloc.
MediaSchemeHandler *gScheme = nil;
BridgeHandler *gBridge = nil;
WKWebView *gWebView = nil;
NSWindow *gWindow = nil;
WKWebView *gEqWebView = nil;
static NSWindow *gEqWindow = nil;
static WKWebView *gObWebView = nil;
static FpNavGate *gNavGate = nil;
static NSURL *gMainLoadURL = nil;

static BOOL fpSameOrigin(NSURL *a, NSURL *b) {
  if (!a || !b) return NO;
  if (![a.scheme isEqualToString:b.scheme]) return NO;
  if (![a.host isEqualToString:b.host]) return NO;
  NSInteger pa = a.port ? a.port.integerValue : ([a.scheme isEqualToString:@"https"] ? 443 : 80);
  NSInteger pb = b.port ? b.port.integerValue : ([b.scheme isEqualToString:@"https"] ? 443 : 80);
  return pa == pb;
}

@interface FpNavGate : NSObject <WKNavigationDelegate>
@end

@implementation FpNavGate
- (void)webView:(WKWebView *)webView
    decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
                    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
  WKFrameInfo *frame = navigationAction.targetFrame;
  // New-window requests (target=_blank / window.open): never open them
  if (!frame) { decisionHandler(WKNavigationActionPolicyCancel); return; }
  // Subframes get no bridge (S2) — their navigations are harmless
  if (!frame.isMainFrame) { decisionHandler(WKNavigationActionPolicyAllow); return; }
  NSURL *url = navigationAction.request.URL;
  if ([url.scheme isEqualToString:@"app"]) {
    decisionHandler(WKNavigationActionPolicyAllow);
    return;
  }
  BOOL bundled = [[[NSBundle mainBundle] bundlePath] hasSuffix:@".app"];
  if (!bundled && gMainLoadURL && fpSameOrigin(url, gMainLoadURL)) {
    decisionHandler(WKNavigationActionPolicyAllow);
    return;
  }
  NSLog(@"[shell] blocked main-frame navigation to %@", url.absoluteString);
  decisionHandler(WKNavigationActionPolicyCancel);
}
@end

// S2: only our own webviews may talk to the bridge
BOOL fpIsAppWebView(WKWebView *w) {
  return w == gWebView || w == gEqWebView || w == gObWebView;
}

void fpSetWebRoot(NSString *root);

// ── App lifecycle ──
@interface ShellAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property (nonatomic, strong) id backgroundActivity;
@end

@implementation ShellAppDelegate

// Menu actions targeting the renderer (playback, views, import) are routed
// through one selector; the action string is a controlled whitelist below.
- (void)fpMenuAction:(NSMenuItem *)sender {
  NSString *action = sender.representedObject;
  if (action.length == 0) return;
  NSString *js = [NSString stringWithFormat:
      @"try { window.__freeplayerMenuAction && window.__freeplayerMenuAction('%@'); } catch (e) {}",
      action];
  dispatch_async(dispatch_get_main_queue(), ^{
    [gWebView evaluateJavaScript:js completionHandler:nil];
  });
}

- (void)buildMenu {
  NSMenu *mainMenu = [[NSMenu alloc] init];

  // ── FreePlayer (app) menu ──
  NSMenuItem *appItem = [[NSMenuItem alloc] init];
  [mainMenu addItem:appItem];
  NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"FreePlayer"];
  [appMenu addItemWithTitle:@"About FreePlayer"
                     action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
  [appMenu addItem:[NSMenuItem separatorItem]];
  NSMenuItem *settingsItem = [[NSMenuItem alloc] initWithTitle:@"Settings…"
                                                        action:@selector(fpMenuAction:)
                                                 keyEquivalent:@","];
  settingsItem.target = self;
  settingsItem.representedObject = @"view-settings";
  [appMenu addItem:settingsItem];
  [appMenu addItem:[NSMenuItem separatorItem]];
  [appMenu addItemWithTitle:@"Hide FreePlayer" action:@selector(hide:) keyEquivalent:@"h"];
  [appMenu addItemWithTitle:@"Quit FreePlayer" action:@selector(terminate:) keyEquivalent:@"q"];
  appItem.submenu = appMenu;

  // ── File ──
  NSMenuItem *fileItem = [[NSMenuItem alloc] init];
  [mainMenu addItem:fileItem];
  NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
  NSMenuItem *importItem = [[NSMenuItem alloc] initWithTitle:@"Import Music…"
                                                      action:@selector(fpMenuAction:)
                                               keyEquivalent:@"o"];
  importItem.target = self;
  importItem.representedObject = @"import";
  [fileMenu addItem:importItem];
  [fileMenu addItem:[NSMenuItem separatorItem]];
  [fileMenu addItemWithTitle:@"Close Window" action:@selector(performClose:) keyEquivalent:@"w"];
  fileItem.submenu = fileMenu;

  // ── Edit (standard responder chain — works with the webview) ──
  NSMenuItem *editItem = [[NSMenuItem alloc] init];
  [mainMenu addItem:editItem];
  NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
  [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
  [editMenu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
  [editMenu addItem:[NSMenuItem separatorItem]];
  [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
  [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
  [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
  [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
  editItem.submenu = editMenu;

  // ── Playback ──
  NSMenuItem *playItem = [[NSMenuItem alloc] init];
  [mainMenu addItem:playItem];
  NSMenu *playMenu = [[NSMenu alloc] initWithTitle:@"Playback"];
  [playMenu addItem:[self menuItem:@"Play / Pause" action:@"playpause" key:@"p"]];
  [playMenu addItem:[self menuItem:@"Next Track" action:@"next" key:@"→"]];
  [playMenu addItem:[self menuItem:@"Previous Track" action:@"prev" key:@"←"]];
  playItem.submenu = playMenu;

  // ── View ──
  NSMenuItem *viewItem = [[NSMenuItem alloc] init];
  [mainMenu addItem:viewItem];
  NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
  [viewMenu addItem:[self menuItem:@"Library" action:@"view-library" key:@"1"]];
  [viewMenu addItem:[self menuItem:@"Now Playing" action:@"view-now-playing" key:@"2"]];
  [viewMenu addItem:[self menuItem:@"Statistics" action:@"view-stats" key:@"3"]];
  [viewMenu addItem:[self menuItem:@"Plugins" action:@"view-plugins" key:@"4"]];
  [viewMenu addItem:[NSMenuItem separatorItem]];
  NSMenuItem *eqItem = [[NSMenuItem alloc] initWithTitle:@"Equalizer…"
                                                  action:@selector(fpMenuAction:)
                                           keyEquivalent:@"e"];
  eqItem.keyEquivalentModifierMask = NSEventModifierFlagOption | NSEventModifierFlagCommand;
  eqItem.target = self;
  eqItem.representedObject = @"open-eq";
  [viewMenu addItem:eqItem];
  viewItem.submenu = viewMenu;

  // ── Window ──
  NSMenuItem *winItem = [[NSMenuItem alloc] init];
  [mainMenu addItem:winItem];
  NSMenu *winMenu = [[NSMenu alloc] initWithTitle:@"Window"];
  [winMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
  [winMenu addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
  [winMenu addItem:[NSMenuItem separatorItem]];
  [winMenu addItemWithTitle:@"Bring All to Front"
                     action:@selector(arrangeInFront:) keyEquivalent:@""];
  winItem.submenu = winMenu;

  NSApp.mainMenu = mainMenu;
}

// Playback/View menu items share the fpMenuAction: selector; ⌘ modifier is
// the default so only explicit modifiers need overrides.
- (NSMenuItem *)menuItem:(NSString *)title action:(NSString *)action key:(NSString *)key {
  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                action:@selector(fpMenuAction:)
                                         keyEquivalent:key];
  item.target = self;
  item.representedObject = action;
  return item;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  if (!fpdb::open(fpdb::defaultDbPath())) {
    NSLog(@"[shell] FATAL: db open failed");
    [NSApp terminate:nil];
    return;
  }
  // H#1: record symlinks created by pre-update imports so the S3e
  // containment check keeps them playable (background, runs once).
  fpSymlinkBackfill();

  [self buildMenu];

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
  // S12: a bundled .app fails closed when its web assets are missing (no
  // silent dev-server fallback), and env/userdefaults overrides
  // (FP_WEB_ROOT/FP_URL/FP_DB) apply to dev binaries only.
  NSUserDefaults *defs = NSUserDefaults.standardUserDefaults;
  BOOL bundled = [[[NSBundle mainBundle] bundlePath] hasSuffix:@".app"];
  NSString *webRoot = nil;
  if (bundled) {
    webRoot = [[NSBundle mainBundle].resourcePath stringByAppendingPathComponent:@"web"];
    if (webRoot.length == 0 || ![NSFileManager.defaultManager fileExistsAtPath:webRoot]) {
      NSAlert *alert = [[NSAlert alloc] init];
      alert.alertStyle = NSAlertStyleCritical;
      alert.messageText = @"FreePlayer is damaged";
      alert.informativeText = [NSString stringWithFormat:
          @"The bundled web assets were not found at %@.\n\nReinstall the app to fix this.", webRoot ?: @"?"];
      [alert addButtonWithTitle:@"Quit"];
      [alert runModal];
      [NSApp terminate:nil];
      return;
    }
  } else {
    NSString *defRoot = [defs stringForKey:@"FP_WEB_ROOT"];
    if (defRoot.length > 0) webRoot = defRoot;
    NSString *envRoot = NSProcessInfo.processInfo.environment[@"FP_WEB_ROOT"];
    if (envRoot.length > 0) webRoot = envRoot;
  }

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
  // Web Inspector (Safari > Develop > FreePlayer): on by default for dev
  // binaries (no .app bundle); bundled builds opt in via FP_INSPECT=1
  // (env or `defaults write`).
  if (@available(macOS 13.3, *)) {
    BOOL dev = ![[[NSBundle mainBundle] bundlePath] hasSuffix:@".app"];
    webView.inspectable = dev
        || [NSUserDefaults.standardUserDefaults boolForKey:@"FP_INSPECT"]
        || (getenv("FP_INSPECT") != NULL);
  }
  // S1: every webview shares the navigation gate (main frame: app:// or the
  // configured dev origin only)
  if (!gNavGate) gNavGate = [[FpNavGate alloc] init];
  webView.navigationDelegate = gNavGate;
  gWebView = webView;
  window.contentView = webView;

  // Launch-at-login hidden: a login-item launch happens in the loginwindow
  // session before any user app activation, so the frontmost app is still
  // loginwindow here. Manual launches (Dock/terminal) have a real frontmost
  // app, so the window always shows for those.
  BOOL hideOnLaunch = NO;
  if (fpdb::getSetting(@"library_dir", nil) && fptraySettingBool(@"start_hidden", NO)) {
    NSRunningApplication *front = NSWorkspace.sharedWorkspace.frontmostApplication;
    hideOnLaunch = front != nil
        && [front.bundleIdentifier isEqualToString:@"com.apple.loginwindow"];
  }
  if (hideOnLaunch) {
    [window orderOut:nil];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
      [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    });
  } else {
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
  }

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
    // Dev binaries only — a bundled app already failed closed above, so the
    // FP_URL overrides below can never downgrade a release build to the
    // dev server.
    NSString *url = [defs stringForKey:@"FP_URL"];
    if (url.length == 0) url = NSProcessInfo.processInfo.environment[@"FP_URL"];
    if (url.length == 0) url = @"http://localhost:5173";
    loadURL = [NSURL URLWithString:url];
    NSLog(@"[shell] dev mode, loading %@", url);
  }
  [webView loadRequest:[NSURLRequest requestWithURL:loadURL]];
  gMainLoadURL = loadURL;

  // First-run: hide the main window and show the onboarding wizard until a
  // library directory is set (library_dir is native-set only).
  if (!fpdb::getSetting(@"library_dir", nil)) {
    [window orderOut:nil];
    fpOpenOnboardingWindow();
  }
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
    fpHideEqWindow();
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
  // Q1: wait (bounded) for in-flight imports to finish instead of polling a
  // counter — the group drains exactly when the last import batch completed
  // (including the exception paths), so sqlite3_close no longer races a
  // background insert. fpdb functions are null-guarded as a safety net.
  dispatch_group_wait(fpImportGroup(), dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)));
  fpdb::close();
}

// ── Equalizer window: second native window + WKWebView ──

void fpOpenEqWindow(void) {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (gEqWindow) {
      [gEqWindow makeKeyAndOrderFront:nil];
      [NSApp activateIgnoringOtherApps:YES];
      return;
    }
    NSRect frame = NSMakeRect(0, 0, 580, 340);
    NSWindow *win = [[NSWindow alloc] initWithContentRect:frame
        styleMask:(NSWindowStyleMaskTitled |
                   NSWindowStyleMaskClosable |
                   NSWindowStyleMaskMiniaturizable |
                   NSWindowStyleMaskFullSizeContentView)
          backing:NSBackingStoreBuffered
            defer:NO];
    win.title = @"Equalizer";
    win.titlebarAppearsTransparent = YES;
    win.titleVisibility = NSWindowTitleHidden;
    win.releasedWhenClosed = NO;
    win.backgroundColor = [NSColor colorWithSRGBRed:0.13 green:0.13 blue:0.15 alpha:1.0];
    [win center];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    config.preferences.javaScriptCanOpenWindowsAutomatically = NO;
    if (gScheme && gBridge) {
      [config setURLSchemeHandler:gScheme forURLScheme:@"media"];
      [config setURLSchemeHandler:gScheme forURLScheme:@"app"];
      [config.userContentController addScriptMessageHandler:gBridge name:@"freeplayer"];
    }
    WKUserScript *bridgeScript = [[WKUserScript alloc]
        initWithSource:fpBridgeScript()
         injectionTime:WKUserScriptInjectionTimeAtDocumentStart
      forMainFrameOnly:YES];
    [config.userContentController addUserScript:bridgeScript];

    ShellWebView *webView = [[ShellWebView alloc] initWithFrame:frame configuration:config];
    webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    if (gNavGate) webView.navigationDelegate = gNavGate;
    win.contentView = webView;
    gEqWebView = webView;
    gEqWindow = win;

    // Q8: build the URL with NSURLComponents — stringByAppendingString
    // breaks dev URLs that already carry a query string
    NSURL *eqURL = nil;
    NSURLComponents *comp = [NSURLComponents componentsWithURL:gMainLoadURL resolvingAgainstBaseURL:NO];
    comp.queryItems = @[ [NSURLQueryItem queryItemWithName:@"view" value:@"eq"] ];
    eqURL = comp.URL;
    [webView loadRequest:[NSURLRequest requestWithURL:eqURL]];
    [win makeKeyAndOrderFront:nil];
  });
}

void fpHideEqWindow(void) {
  dispatch_async(dispatch_get_main_queue(), ^{
    [gEqWindow orderOut:nil];
  });
}

// ── Onboarding window: first-run wizard (640x480) ──

static NSWindow *gObWindow = nil;

void fpOpenOnboardingWindow(void) {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (gObWindow) {
      [gObWindow makeKeyAndOrderFront:nil];
      [NSApp activateIgnoringOtherApps:YES];
      return;
    }
    NSRect frame = NSMakeRect(0, 0, 640, 480);
    NSWindow *win = [[NSWindow alloc] initWithContentRect:frame
        styleMask:(NSWindowStyleMaskTitled |
                   NSWindowStyleMaskClosable |
                   NSWindowStyleMaskMiniaturizable |
                   NSWindowStyleMaskResizable |
                   NSWindowStyleMaskFullSizeContentView)
          backing:NSBackingStoreBuffered
            defer:NO];
    win.title = @"Welcome to FreePlayer";
    win.titlebarAppearsTransparent = YES;
    win.titleVisibility = NSWindowTitleHidden;
    win.releasedWhenClosed = NO;
    win.backgroundColor = [NSColor colorWithSRGBRed:0.98 green:0.98 blue:0.98 alpha:1.0];
    [win center];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    config.preferences.javaScriptCanOpenWindowsAutomatically = NO;
    if (gScheme && gBridge) {
      [config setURLSchemeHandler:gScheme forURLScheme:@"media"];
      [config setURLSchemeHandler:gScheme forURLScheme:@"app"];
      [config.userContentController addScriptMessageHandler:gBridge name:@"freeplayer"];
    }
    WKUserScript *bridgeScript = [[WKUserScript alloc]
        initWithSource:fpBridgeScript()
         injectionTime:WKUserScriptInjectionTimeAtDocumentStart
      forMainFrameOnly:YES];
    [config.userContentController addUserScript:bridgeScript];

    ShellWebView *webView = [[ShellWebView alloc] initWithFrame:frame configuration:config];
    webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    if (gNavGate) webView.navigationDelegate = gNavGate;
    win.contentView = webView;
    gObWebView = webView;
    gObWindow = win;

    // Q8: same URL-building fix as the EQ window
    NSURL *obURL = nil;
    NSURLComponents *comp = [NSURLComponents componentsWithURL:gMainLoadURL resolvingAgainstBaseURL:NO];
    comp.queryItems = @[ [NSURLQueryItem queryItemWithName:@"view" value:@"onboarding"] ];
    obURL = comp.URL;
    [webView loadRequest:[NSURLRequest requestWithURL:obURL]];
    [win makeKeyAndOrderFront:nil];
  });
}

void fpCloseOnboardingWindow(void) {
  dispatch_async(dispatch_get_main_queue(), ^{
    [gObWindow orderOut:nil];
  });
}

void fpFinishOnboarding(void) {
  dispatch_async(dispatch_get_main_queue(), ^{
    [gObWindow orderOut:nil];
    [gWebView reload];
    [gWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
  });
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
