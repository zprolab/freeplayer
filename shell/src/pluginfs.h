#pragma once
#import <Foundation/Foundation.h>

namespace fpplugin {
NSString *pluginsDir(void);
NSArray<NSDictionary *> *listPlugins(void);
NSString *readPluginFile(NSString *pluginId, NSString *relPath);
BOOL removePlugin(NSString *pluginId);
void openPluginsDir(void);
}
