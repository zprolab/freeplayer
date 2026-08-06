// FreePlayer shell — media:// + app:// scheme handlers
//   media://<encoded path>  — local audio files (Range support for <audio>)
//   app://<relative path>   — bundled web assets (prod UI)

#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#include <atomic>

static NSString *gWebRoot = nil;
void fpSetWebRoot(NSString *root) { gWebRoot = [root copy]; }

// Per-task cancellation flags (main-thread dictionary of atomics; the
// streaming loop reads the atomic from a background queue).
static NSMutableDictionary *gStoppedTasks = nil;
static std::atomic<bool> *stoppedFlagForTask(id<WKURLSchemeTask> task) {
  if (!gStoppedTasks) gStoppedTasks = [NSMutableDictionary dictionary];
  NSNumber *key = @((uintptr_t)task);
  std::atomic<bool> *flag = (std::atomic<bool> *)[gStoppedTasks[key] pointerValue];
  if (!flag) {
    flag = new std::atomic<bool>(false);
    gStoppedTasks[key] = [NSValue valueWithPointer:flag];
  }
  return flag;
}
static void clearStoppedFlag(id<WKURLSchemeTask> task) {
  NSNumber *key = @((uintptr_t)task);
  std::atomic<bool> *flag = (std::atomic<bool> *)[gStoppedTasks[key] pointerValue];
  if (flag) {
    delete flag;
    [gStoppedTasks removeObjectForKey:key];
  }
}

@interface MediaSchemeHandler : NSObject <WKURLSchemeHandler>
@end

static NSString *mimeForPath(NSString *path) {
  NSString *ext = path.pathExtension.lowercaseString;
  if ([ext isEqualToString:@"html"] || [ext isEqualToString:@"htm"]) return @"text/html; charset=utf-8";
  if ([ext isEqualToString:@"js"] || [ext isEqualToString:@"mjs"]) return @"text/javascript";
  if ([ext isEqualToString:@"css"]) return @"text/css";
  if ([ext isEqualToString:@"json"] || [ext isEqualToString:@"map"]) return @"application/json";
  if ([ext isEqualToString:@"svg"]) return @"image/svg+xml";
  if ([ext isEqualToString:@"woff2"]) return @"font/woff2";
  if ([ext isEqualToString:@"woff"]) return @"font/woff";
  if ([ext isEqualToString:@"ttf"]) return @"font/ttf";
  if ([ext isEqualToString:@"ico"]) return @"image/x-icon";
  if ([ext isEqualToString:@"flac"]) return @"audio/flac";
  if ([ext isEqualToString:@"mp3"]) return @"audio/mpeg";
  if ([ext isEqualToString:@"m4a"]) return @"audio/mp4";
  if ([ext isEqualToString:@"mp4"]) return @"audio/mp4";
  if ([ext isEqualToString:@"ogg"] || [ext isEqualToString:@"oga"]) return @"audio/ogg";
  if ([ext isEqualToString:@"wav"]) return @"audio/wav";
  if ([ext isEqualToString:@"aac"]) return @"audio/aac";
  if ([ext isEqualToString:@"opus"]) return @"audio/ogg";
  if ([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"]) return @"image/jpeg";
  if ([ext isEqualToString:@"png"]) return @"image/png";
  if ([ext isEqualToString:@"webp"]) return @"image/webp";
  if ([ext isEqualToString:@"gif"]) return @"image/gif";
  if ([ext isEqualToString:@"lrc"]) return @"text/plain; charset=utf-8";
  return @"application/octet-stream";
}

@implementation MediaSchemeHandler

- (void)webView:(WKWebView *)webView startURLSchemeTask:(id<WKURLSchemeTask>)task {
  NSURL *url = task.request.URL;

  // ── app:// — bundled web assets ──
  if ([url.scheme isEqualToString:@"app"]) {
    NSString *rel = url.path; // "/index.html", "/assets/x.js"
    if (rel.length == 0 || [rel isEqualToString:@"/"]) rel = @"/index.html";
    NSString *file = [gWebRoot stringByAppendingPathComponent:[rel stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]]];
    NSData *data = [NSData dataWithContentsOfFile:file];
    if (!data) {
      [task didFailWithError:[NSError errorWithDomain:NSPOSIXErrorDomain code:ENOENT userInfo:@{ NSLocalizedDescriptionKey : file }]];
      return;
    }
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"HTTP/1.1"
                                                            headerFields:@{
      @"Content-Type": mimeForPath(file),
      @"Content-Length": [NSString stringWithFormat:@"%lu", (unsigned long)data.length],
      @"Cache-Control": @"no-cache",
    }];
    [task didReceiveResponse:response];
    [task didReceiveData:data];
    [task didFinish];
    return;
  }

  // ── media:// — local audio files with Range support ──
  NSString *raw = url.absoluteString; // "media://%2FVolumes%2F..."
  if (![raw hasPrefix:@"media://"]) {
    [task didFailWithError:[NSError errorWithDomain:@"FreePlayerShell" code:400 userInfo:nil]];
    return;
  }
  NSString *encodedPath = [raw substringFromIndex:@"media://".length];
  NSString *path = [encodedPath stringByRemovingPercentEncoding];
  if (path.length == 0) {
    [task didFailWithError:[NSError errorWithDomain:@"FreePlayerShell" code:400 userInfo:nil]];
    return;
  }

  NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
  if (!fh) {
    [task didFailWithError:[NSError errorWithDomain:NSPOSIXErrorDomain code:ENOENT userInfo:@{ NSLocalizedDescriptionKey : path }]];
    return;
  }
  unsigned long long fileSize = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil].fileSize;

  // Parse Range header
  unsigned long long start = 0, end = fileSize > 0 ? fileSize - 1 : 0;
  BOOL hasRange = NO;
  NSString *range = task.request.allHTTPHeaderFields[@"Range"];
  if (range.length > 0) {
    // "bytes=start-end" or "bytes=start-"
    NSScanner *sc = [NSScanner scannerWithString:range];
    if ([sc scanString:@"bytes=" intoString:NULL]) {
      long long s = -1;
      if ([sc scanLongLong:&s] && s >= 0) {
        start = (unsigned long long)s;
        hasRange = YES;
        long long e = -1;
        if ([sc scanString:@"-" intoString:NULL] && [sc scanLongLong:&e] && e >= (long long)start) {
          end = (unsigned long long)e;
        }
        if (end >= fileSize) end = fileSize > 0 ? fileSize - 1 : 0;
        if (start > end) { start = 0; hasRange = NO; }
      }
    }
  }

  unsigned long long length = (end >= start) ? end - start + 1 : 0;
  NSMutableDictionary *headers = [NSMutableDictionary dictionaryWithDictionary:@{
    @"Content-Type": mimeForPath(path),
    @"Accept-Ranges": @"bytes",
    @"Cache-Control": @"no-cache",
  }];
  NSInteger status = 200;
  if (hasRange) {
    status = 206;
    headers[@"Content-Range"] = [NSString stringWithFormat:@"bytes %llu-%llu/%llu", start, end, fileSize];
  }
  headers[@"Content-Length"] = [NSString stringWithFormat:@"%llu", length];
  NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:headers];

  // Per-task cancellation flag (stop on THIS task must not kill others)
  std::atomic<bool> *stopped = stoppedFlagForTask(task);
  dispatch_async(dispatch_get_main_queue(), ^{
    if (stopped->load()) return;
    [task didReceiveResponse:response];
  });

  [fh seekToFileOffset:start];
  const NSUInteger chunk = 64 * 1024;
  __block unsigned long long remaining = length;
  __block BOOL finished = NO;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    while (remaining > 0 && !stopped->load()) {
      NSUInteger n = (NSUInteger)MIN(remaining, chunk);
      NSData *data = [fh readDataOfLength:n];
      if (data.length == 0) break;
      NSData *copy = [data copy];
      dispatch_async(dispatch_get_main_queue(), ^{
        if (!stopped->load() && !finished) {
          @try { [task didReceiveData:copy]; } @catch (NSException *e) {}
        }
      });
      remaining -= data.length;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      [fh closeFile];
      if (!stopped->load() && !finished) {
        finished = YES;
        @try { [task didFinish]; } @catch (NSException *e) {}
      }
      clearStoppedFlag(task);
    });
  });
}

- (void)webView:(WKWebView *)webView stopURLSchemeTask:(id<WKURLSchemeTask>)task {
  std::atomic<bool> *stopped = stoppedFlagForTask(task);
  stopped->store(true);
}

@end
