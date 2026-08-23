// FreePlayer shell — plugin filesystem access
// Plugins live one level deep under ~/Library/Application Support/FreePlayer/plugins.
// All renderer-facing reads are confined to a plugin's own directory.

import Foundation
import AppKit

enum PluginFS {

    private static func baseDir() -> String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("FreePlayer/plugins").path
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir) {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func pluginsDir() -> String { baseDir() }

    private static func pluginRoot(_ pluginId: String) -> String {
        (baseDir() as NSString).appendingPathComponent(pluginId)
    }

    // Whitelist a plugin id before it is used as a path component: no slashes,
    // no dot names, and the standardized root must round-trip back to the same
    // last path component — otherwise `..`-laden ids would drift the root
    // outside plugins/ and defeat the read confinement below.
    private static func validPluginId(_ pluginId: String) -> Bool {
        if pluginId.isEmpty { return false }
        if pluginId.contains("/") { return false }
        if pluginId == "." || pluginId == ".." { return false }
        let root = (pluginRoot(pluginId) as NSString).standardizingPath
        if (root as NSString).lastPathComponent != pluginId { return false }
        guard root.hasPrefix(baseDir() + "/") else { return false }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else { return false }
        guard let type = try? FileManager.default.attributesOfItem(atPath: root)[.type] as? FileAttributeType,
              type != .typeSymbolicLink else { return false }
        let baseReal = URL(fileURLWithPath: baseDir()).resolvingSymlinksInPath().path
        let rootReal = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
        return rootReal.hasPrefix(baseReal + "/")
    }

    static func listPlugins() -> [[String: Any]] {
        let fm = FileManager.default
        var out: [[String: Any]] = []
        let entries = (try? fm.contentsOfDirectory(atPath: baseDir())) ?? []
        for name in entries {
            if name.hasPrefix(".") { continue }
            if !validPluginId(name) { continue }
            let dir = (pluginRoot(name) as NSString).standardizingPath
            var isDir: ObjCBool = false
            if !fm.fileExists(atPath: dir, isDirectory: &isDir) || !isDir.boolValue { continue }
            let manifestPath = (dir as NSString).appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)) else {
                out.append(["id": name, "error": "manifest.json missing"])
                continue
            }
            // Cap the manifest at 64KB — reject oversized files instead of loading
            // them whole (same limit as readPluginFile)
            if data.count > 64 * 1024 {
                out.append(["id": name, "error": "manifest.json too large"])
                continue
            }
            guard let json = try? JSONSerialization.jsonObject(with: data), json is [String: Any] else {
                out.append(["id": name, "error": "manifest.json invalid"])
                continue
            }
            out.append(["id": name, "manifestRaw": json])
        }
        return out
    }

    static func readPluginFile(_ pluginId: String, _ relPath: String) -> String? {
        if !validPluginId(pluginId) || relPath.isEmpty { return nil }
        // Resolve the root the same way as the candidate: resolving symlinks
        // canonicalizes to on-disk case, so comparing an un-resolved root
        // against a resolved candidate always failed on case-insensitive APFS.
        let root = (pluginRoot(pluginId) as NSString).standardizingPath
        let candidate = ((root as NSString).appendingPathComponent(relPath) as NSString).standardizingPath
        let resolved = URL(fileURLWithPath: candidate).resolvingSymlinksInPath().path
        let rootReal = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
        if !resolved.hasPrefix(rootReal + "/") && resolved != rootReal {
            return nil // traversal or symlink escape
        }
        var isDir: ObjCBool = false
        let fm = FileManager.default
        if !fm.fileExists(atPath: resolved, isDirectory: &isDir) || isDir.boolValue { return nil }
        let size = ((try? fm.attributesOfItem(atPath: resolved))?[.size] as? NSNumber)?.uint64Value ?? 0
        let limit: UInt64 = ((relPath as NSString).standardizingPath == "manifest.json") ? 64 * 1024 : 2 * 1024 * 1024
        if size > limit { return nil }
        return try? String(contentsOfFile: resolved, encoding: .utf8)
    }

    @discardableResult
    static func removePlugin(_ pluginId: String) -> Bool {
        // Same whitelist as reads: a plugin id with a slash (or "." / "..") must
        // never be used as a path component, or removal could target a sibling
        // directory under plugins/ instead of the plugin's own root.
        if !validPluginId(pluginId) { return false }
        return (try? FileManager.default.removeItem(atPath: pluginRoot(pluginId))) != nil
    }

    static func openPluginsDir() {
        NSWorkspace.shared.open(URL(fileURLWithPath: baseDir()))
    }
}
