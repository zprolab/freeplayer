// FreePlayer shell — plugin filesystem access
// Plugins live one level deep under ~/Library/Application Support/FreePlayer/plugins.
// All renderer-facing reads are confined to a plugin's own directory.

#import "pluginfs.h"
#import <AppKit/AppKit.h>

namespace fpplugin {

static NSString *baseDir(void) {
  NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                       NSUserDomainMask, YES);
  NSString *dir = [paths.firstObject stringByAppendingPathComponent:@"FreePlayer/plugins"];
  NSFileManager *fm = NSFileManager.defaultManager;
  if (![fm fileExistsAtPath:dir]) {
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
  }
  return dir;
}

NSString *pluginsDir(void) { return baseDir(); }

static NSString *pluginRoot(NSString *pluginId) {
  return [baseDir() stringByAppendingPathComponent:pluginId];
}

// Whitelist a plugin id before it is used as a path component: no slashes,
// no dot names, and the standardized root must round-trip back to the same
// last path component — otherwise `..`-laden ids would drift the root
// outside plugins/ and defeat the read confinement below.
static BOOL validPluginId(NSString *pluginId) {
  if (pluginId.length == 0) return NO;
  if ([pluginId containsString:@"/"]) return NO;
  if ([pluginId isEqualToString:@"."] || [pluginId isEqualToString:@".."]) return NO;
  NSString *root = [pluginRoot(pluginId) stringByStandardizingPath];
  if (![root.lastPathComponent isEqualToString:pluginId]) return NO;
  return [root hasPrefix:[baseDir() stringByAppendingString:@"/"]];
}

NSArray<NSDictionary *> *listPlugins(void) {
  NSFileManager *fm = NSFileManager.defaultManager;
  NSMutableArray *out = [NSMutableArray array];
  NSArray *entries = [fm contentsOfDirectoryAtPath:baseDir() error:nil];
  for (NSString *name in entries) {
    if ([name hasPrefix:@"."]) continue;
    NSString *dir = [pluginRoot(name) stringByStandardizingPath];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:dir isDirectory:&isDir] || !isDir) continue;
    NSString *manifestPath = [dir stringByAppendingPathComponent:@"manifest.json"];
    NSData *data = [NSData dataWithContentsOfFile:manifestPath];
    if (!data) {
      [out addObject:@{ @"id": name, @"error": @"manifest.json missing" }];
      continue;
    }
    // Cap the manifest at 64KB — reject oversized files instead of loading
    // them whole (same limit as readPluginFile)
    if (data.length > 64 * 1024) {
      [out addObject:@{ @"id": name, @"error": @"manifest.json too large" }];
      continue;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:NSDictionary.class]) {
      [out addObject:@{ @"id": name, @"error": @"manifest.json invalid" }];
      continue;
    }
    [out addObject:@{ @"id": name, @"manifestRaw": json }];
  }
  return out;
}

NSString *readPluginFile(NSString *pluginId, NSString *relPath) {
  if (!validPluginId(pluginId) || relPath.length == 0) return nil;
  // Resolve the root the same way as the candidate: stringByResolving-
  // SymlinksInPath canonicalizes to on-disk case, so comparing an un-resolved
  // root against a resolved candidate always failed on case-insensitive APFS.
  NSString *root = [[pluginRoot(pluginId) stringByStandardizingPath] stringByResolvingSymlinksInPath];
  NSString *candidate = [[root stringByAppendingPathComponent:relPath] stringByStandardizingPath];
  NSString *resolved = [candidate stringByResolvingSymlinksInPath];
  if (![resolved hasPrefix:[root stringByAppendingString:@"/"]] &&
      ![resolved isEqualToString:root]) {
    return nil; // traversal or symlink escape
  }
  BOOL isDir = NO;
  if (![[NSFileManager defaultManager] fileExistsAtPath:resolved isDirectory:&isDir] || isDir) return nil;
  NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:resolved error:nil];
  NSUInteger limit = [[relPath stringByStandardizingPath] isEqualToString:@"manifest.json"]
      ? 64 * 1024 : 2 * 1024 * 1024;
  if ([attrs[NSFileSize] unsignedLongLongValue] > limit) return nil;
  NSString *content = [[NSString alloc] initWithContentsOfFile:resolved encoding:NSUTF8StringEncoding error:nil];
  return content;
}

BOOL removePlugin(NSString *pluginId) {
  // Same whitelist as reads: a plugin id with a slash (or "." / "..") must
  // never be used as a path component, or removal could target a sibling
  // directory under plugins/ instead of the plugin's own root.
  if (!validPluginId(pluginId)) return NO;
  return [[NSFileManager defaultManager] removeItemAtPath:pluginRoot(pluginId) error:nil];
}

void openPluginsDir(void) {
  NSURL *url = [NSURL fileURLWithPath:baseDir()];
  [[NSWorkspace sharedWorkspace] openURL:url];
}

}
