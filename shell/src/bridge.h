// FreePlayer shell — bridge declarations
#pragma once
#import <Foundation/Foundation.h>

NSString *fpBridgeScript();
void fpOpenEqWindow(void);
void fpHideEqWindow(void);
void fpOpenOnboardingWindow(void);
void fpCloseOnboardingWindow(void);
void fpFinishOnboarding(void);
bool fpPendingImports(void);   // M12: in-flight import counter for termination
extern WKWebView *gEqWebView;
