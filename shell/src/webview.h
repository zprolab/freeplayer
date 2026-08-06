// FreePlayer shell — WKWebView subclass
// Intercepts file drags: WKWebView exposes dropped files to JS without
// filesystem paths, so we grab the pasteboard paths natively instead.

#import <WebKit/WebKit.h>
#include <AppKit/AppKit.h>

@interface ShellWebView : WKWebView
@end

void fpHandleDropPaths(NSArray<NSString *> *paths);
