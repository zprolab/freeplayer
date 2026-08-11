// FreePlayer shell — shared path helpers (see paths.h)

#import "paths.h"
#include "db.h"

static const char *kAudioExtensions[] = {
  "mp3", "flac", "m4a", "mp4", "aac", "wav", "ogg", "oga", "opus",
  "wma", "aif", "aiff", "m4b", "ape", "wv", "tak", "ac3", "dts", "amr"
};

BOOL fpIsAudioFile(NSString *path) {
  NSString *ext = path.pathExtension.lowercaseString;
  if (ext.length == 0) return NO;
  for (const char *e : kAudioExtensions) {
    if ([ext isEqualToString:@(e)]) return YES;
  }
  return NO;
}

// H#1: one-time backfill of import-created symlink records. The S3e
// containment check trusts only symlinks whose resolved target is recorded
// in imported_symlinks; tracks imported before that feature existed have no
// record and would silently stop streaming. Walk the track table once and
// record every in-library symlink. Guarded by a settings flag.
void fpSymlinkBackfill(void) {
  if (fpdb::getSetting(@"symlink_backfill_done", nil) != nil) return;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSDictionary *t in fpdb::getAllTracks(@"", @"imported_at", @"ASC")) {
      @autoreleasepool {
        NSString *p = t[@"file_path"];
        if (![p isKindOfClass:NSString.class] || p.length == 0) continue;
        if ([fm attributesOfItemAtPath:p error:NULL].fileType == NSFileTypeSymbolicLink) {
          NSString *resolved = [NSURL fileURLWithPath:p].URLByResolvingSymlinksInPath.path;
          if (resolved.length > 0) fpdb::recordSymlink(p, resolved);
        }
      }
    }
    fpdb::setSetting(@"symlink_backfill_done", @"1");
  });
}

BOOL fpIsPathInLibrary(NSString *path) {
  NSString *libRaw = fpdb::getSetting(@"library_dir", nil);
  if (libRaw.length == 0) return NO;
  NSString *libNorm = [libRaw stringByStandardizingPath];
  // H#3: the library root itself may be a symlink (common on macOS) — a
  // resolved path must be accepted against the RESOLVED root too, or every
  // read breaks for such libraries.
  NSString *libResolved = [NSURL fileURLWithPath:libNorm].URLByResolvingSymlinksInPath.path;
  NSString *pathNorm = [path stringByStandardizingPath];
  BOOL prefixOk = [pathNorm hasPrefix:[libNorm stringByAppendingString:@"/"]]
      || [pathNorm isEqualToString:libNorm];
  if (!prefixOk) return NO;
  // S3d: resolve every symlink component — the final target must still be
  // inside the library, or a renderer-planted symlink becomes an arbitrary
  // local-file read via media:// / getCover. (Nonexistent tails resolve
  // to themselves, so write-path checks below stay usable.)
  NSString *resolved = [NSURL fileURLWithPath:path].URLByResolvingSymlinksInPath.path;
  if (resolved.length == 0) return NO;
  NSString *resNorm = [resolved stringByStandardizingPath];
  BOOL insideResolvedRoot = [resNorm hasPrefix:[libResolved stringByAppendingString:@"/"]]
      || [resNorm isEqualToString:libResolved];
  if ([resNorm hasPrefix:[libNorm stringByAppendingString:@"/"]]
      || [resNorm isEqualToString:libNorm] || insideResolvedRoot) {
    return YES;
  }
  // S3e: symlinks the import pipeline itself created are trusted — their
  // resolved targets are recorded in the DB at import time. A link only
  // passes when its CURRENT on-disk target still matches the recorded one:
  // a tampered or re-pointed symlink resolves differently and is rejected.
  // This keeps the app's symlink import mode working (its targets
  // legitimately live outside the library) while closing the boundary.
  if (![pathNorm isEqualToString:resNorm]) {
    NSString *recorded = fpdb::symlinkTarget(pathNorm);
    if (recorded.length > 0 && [resNorm isEqualToString:[recorded stringByStandardizingPath]]) {
      return YES;
    }
  }
  return NO;
}
