// FreePlayer shell — media:// + app:// scheme handlers
//   media://<encoded path>  — local audio files (Range support for <audio>)
//   app://<relative path>   — bundled web assets (prod UI)

#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#include <atomic>
#include "db.h"

static NSString *gWebRoot = nil;
void fpSetWebRoot(NSString *root) { gWebRoot = [root copy]; }

// L2: media:// must only stream files inside the library directory — an
// unrestricted path here is an arbitrary local-file read primitive.
static BOOL pathInsideLibrary(NSString *path) {
  NSString *lib = fpdb::getSetting(@"library_dir", nil);
  if (lib.length == 0) return NO;
  NSString *libNorm = [lib stringByStandardizingPath];
  NSString *pathNorm = [path stringByStandardizingPath];
  return [pathNorm hasPrefix:[libNorm stringByAppendingString:@"/"]]
      || [pathNorm isEqualToString:libNorm];
}

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
    // H6: standardize the path and pin it inside gWebRoot — ".." components
    // must never escape the bundled assets directory.
    NSString *rootNorm = [gWebRoot stringByStandardizingPath];
    NSString *file = [[rootNorm stringByAppendingPathComponent:[rel stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]]] stringByStandardizingPath];
    if (![file hasPrefix:[rootNorm stringByAppendingString:@"/"]] && ![file isEqualToString:rootNorm]) {
      [task didFailWithError:[NSError errorWithDomain:@"FreePlayerShell" code:400 userInfo:@{ NSLocalizedDescriptionKey : @"invalid app:// path" }]];
      return;
    }
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

  // L2: only library-owned files may stream
  if (!pathInsideLibrary(path)) {
    [task didFailWithError:[NSError errorWithDomain:@"FreePlayerShell" code:403
                                           userInfo:@{ NSLocalizedDescriptionKey : @"outside library" }]];
    return;
  }

  NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
  if (!fh) {
    [task didFailWithError:[NSError errorWithDomain:NSPOSIXErrorDomain code:ENOENT userInfo:@{ NSLocalizedDescriptionKey : path }]];
    return;
  }
  unsigned long long fileSize = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil].fileSize;

  // Parse Range header — supports "bytes=start-end", "bytes=start-", "bytes=-suffix"
  unsigned long long start = 0, end = fileSize > 0 ? fileSize - 1 : 0;
  BOOL hasRange = NO;
  BOOL rangeInvalid = NO;
  NSString *range = task.request.allHTTPHeaderFields[@"Range"];
  if (range.length > 0) {
    // M13: reject multi-range requests ("bytes=0-1,4-5") explicitly.
    // #7: range-unit is case-insensitive (RFC 7233); tolerate trailing space.
    NSString *lower = [range lowercaseString];
    if (![lower hasPrefix:@"bytes="]) {
      rangeInvalid = YES;
    } else {
      NSScanner *sc = [NSScanner scannerWithString:[range substringFromIndex:@"bytes=".length]];
      if ([sc scanString:@"-" intoString:NULL]) {
        // Suffix range: last N bytes
        long long suffix = -1;
        if ([sc scanLongLong:&suffix] && suffix > 0 && fileSize > 0) {
          hasRange = YES;
          start = (unsigned long long)suffix >= fileSize ? 0 : fileSize - (unsigned long long)suffix;
          end = fileSize - 1;
        } else {
          rangeInvalid = YES;
        }
      } else {
        long long s = -1;
        if ([sc scanLongLong:&s] && s >= 0) {
          start = (unsigned long long)s;
          hasRange = YES;
          long long e = -1;
          if ([sc scanString:@"-" intoString:NULL] && [sc scanLongLong:&e] && e >= 0) {
            end = (unsigned long long)e;
          }
          // NEW-4: bytes=5-3 (end before start) is unsatisfiable → 416
          if (end < start) {
            rangeInvalid = YES;
          } else if (end >= fileSize) {
            end = fileSize > 0 ? fileSize - 1 : 0;
          }
        } else {
          rangeInvalid = YES;
        }
      }
      // Anything left after the range (e.g. multi-range "0-1,4-5") is unsupported
      NSString *rest = [range substringFromIndex:@"bytes=".length + sc.scanLocation];
      if ([[rest stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] length] > 0) {
        rangeInvalid = YES;
      }
    }
    if (rangeInvalid) hasRange = NO;
  }

  // M13: unsatisfiable/invalid Range → 416 with Content-Range: bytes */size
  if (rangeInvalid) {
    NSDictionary *h416 = @{
      @"Content-Range": [NSString stringWithFormat:@"bytes */%llu", fileSize],
      @"Content-Length": @"0",
      @"Accept-Ranges": @"bytes",
    };
    NSHTTPURLResponse *r416 = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:416 HTTPVersion:@"HTTP/1.1" headerFields:h416];
    dispatch_async(dispatch_get_main_queue(), ^{
      // #5: always clear the flag — an early return here would leak it
      std::atomic<bool> *flag = stoppedFlagForTask(task);
      if (flag->load()) {
        clearStoppedFlag(task);
        return;
      }
      @try {
        [task didReceiveResponse:r416];
        [task didFinish];
      } @catch (NSException *e) {}
      clearStoppedFlag(task);
    });
    return;
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
  // H1: read in 64KB chunks but flush to the main queue in ~1MB batches with
  // flow control (max ~8 batches in flight) so a large file can never queue
  // unbounded NSData on the main thread. readDataOfLength: returns a fresh
  // NSData — no extra copy per chunk; only the batch flush copies.
  const NSUInteger chunk = 64 * 1024;
  const NSUInteger batchChunks = 16;      // 1MB per main-queue hop
  const long maxInFlight = 8;             // ~8MB of queued data at most
  __block unsigned long long remaining = length;
  __block BOOL finished = NO;
  __block std::atomic<long> *inFlight = new std::atomic<long>(0);
  __block NSMutableData *buf = [NSMutableData dataWithCapacity:batchChunks * chunk];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    auto flushBatch = ^(NSData *out) {
      inFlight->fetch_add(1);
      dispatch_async(dispatch_get_main_queue(), ^{
        if (!stopped->load() && !finished) {
          @try { [task didReceiveData:out]; } @catch (NSException *e) {}
        }
        inFlight->fetch_sub(1);
      });
    };
    while (remaining > 0 && !stopped->load()) {
      NSUInteger n = (NSUInteger)MIN(remaining, chunk);
      NSData *data = [fh readDataOfLength:n];
      if (data.length == 0) break;
      [buf appendData:data];
      remaining -= data.length;
      if (buf.length >= batchChunks * chunk) {
        // Backpressure: wait until the main queue drains below the cap
        while (inFlight->load() >= maxInFlight && !stopped->load()) {
          usleep(2000);
        }
        if (stopped->load()) break;
        flushBatch([buf copy]);
        [buf setLength:0];
      }
    }
    if (buf.length > 0 && !stopped->load()) {
      while (inFlight->load() >= maxInFlight && !stopped->load()) {
        usleep(2000);
      }
      if (!stopped->load()) {
        flushBatch([buf copy]);
        [buf setLength:0];
      }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      [fh closeFile];
      if (!stopped->load() && !finished) {
        finished = YES;
        @try { [task didFinish]; } @catch (NSException *e) {}
      }
      clearStoppedFlag(task);
      delete inFlight;
    });
  });
}

- (void)webView:(WKWebView *)webView stopURLSchemeTask:(id<WKURLSchemeTask>)task {
  // NEW-5: only mark tasks we actually know — a post-completion stop must not
  // create a stuck flag that a future request (reusing the task pointer)
  // would inherit as an instant-cancel
  NSNumber *key = @((uintptr_t)task);
  std::atomic<bool> *flag = (std::atomic<bool> *)[gStoppedTasks[key] pointerValue];
  if (flag) flag->store(true);
}

@end
