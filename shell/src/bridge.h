// FreePlayer shell — bridge declarations
#pragma once
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NSString *fpBridgeScript();
void fpOpenEqWindow(void);
void fpHideEqWindow(void);
void fpOpenOnboardingWindow(void);
void fpCloseOnboardingWindow(void);
void fpFinishOnboarding(void);
bool fpPendingImports(void);   // M12: in-flight import counter for termination
dispatch_group_t fpImportGroup(void); // Q1: completion signal for in-flight imports
BOOL fpIsAppWebView(WKWebView *webView); // S2: is this a bridge-owning webview?
extern WKWebView *gEqWebView;
