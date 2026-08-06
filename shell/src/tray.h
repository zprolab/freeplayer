// FreePlayer shell — tray declarations
#pragma once
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <AppKit/AppKit.h>

extern WKWebView *gWebView;
extern NSWindow *gWindow;

@interface FpTray : NSObject
+ (void)create;
+ (void)setPlaying:(BOOL)playing;
+ (void)setNowPlayingFromTrack:(NSDictionary *)track;
@end

BOOL fptrayLoginItemEnabled(void);
BOOL fptraySetLoginItem(BOOL enabled);
