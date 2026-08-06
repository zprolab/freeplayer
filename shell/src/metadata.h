// FreePlayer shell — metadata declarations
#pragma once
#import <Foundation/Foundation.h>

namespace fpmeta {
NSString *findSidecarLrc(NSString *audioPath);
NSDictionary *extractAtPath(NSString *path); // call on background queue
} // namespace fpmeta
