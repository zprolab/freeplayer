// FreePlayer shell — shared path helpers (see paths.h)

#import "paths.h"
#include "db.h"

static const char *kAudioExtensions[] = {
  "mp3", "flac", "m4a", "mp4", "aac", "wav", "ogg", "oga", "opus",
  "wma", "aif", "aiff", "m4b"
};

BOOL fpIsAudioFile(NSString *path) {
  NSString *ext = path.pathExtension.lowercaseString;
  if (ext.length == 0) return NO;
  for (const char *e : kAudioExtensions) {
    if ([ext isEqualToString:@(e)]) return YES;
  }
  return NO;
}

BOOL fpIsPathInLibrary(NSString *path) {
  NSString *libRaw = fpdb::getSetting(@"library_dir", nil);
  if (libRaw.length == 0) return NO;
  NSString *libNorm = [libRaw stringByStandardizingPath];
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
  if ([resNorm hasPrefix:[libNorm stringByAppendingString:@"/"]]
      || [resNorm isEqualToString:libNorm]) {
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
