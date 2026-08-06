#import <Foundation/Foundation.h>
#include "metadata.h"

int main(int argc, char **argv) {
  @autoreleasepool {
    for (int i = 1; i < argc; i++) {
      NSString *path = [NSString stringWithUTF8String:argv[i]];
      NSDictionary *m = fpmeta::extractAtPath(path);
      NSLog(@"== %@\n%@", path, m);
      NSLog(@"sidecar: %@", fpmeta::findSidecarLrc(path));
    }
  }
  return 0;
}
