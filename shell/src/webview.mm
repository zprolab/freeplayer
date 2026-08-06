// FreePlayer shell — ShellWebView implementation

#import "webview.h"

@implementation ShellWebView

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
  if ([[sender.draggingPasteboard types] containsObject:NSPasteboardTypeFileURL]) {
    return NSDragOperationCopy;
  }
  return [super draggingEntered:sender];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
  NSArray<NSURL *> *urls = [sender.draggingPasteboard
      readObjectsForClasses:@[ NSURL.class ]
                    options:@{ NSPasteboardURLReadingFileURLsOnlyKey : @YES }];
  NSMutableArray<NSString *> *paths = [NSMutableArray array];
  for (NSURL *u in urls) {
    [paths addObject:u.path];
  }
  if (paths.count > 0) {
    fpHandleDropPaths(paths);
    return YES;
  }
  return [super performDragOperation:sender];
}

@end
