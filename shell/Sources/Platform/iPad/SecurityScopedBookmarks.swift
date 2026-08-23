// FreePlayer shell — iPad security-scoped bookmark persistence.
// iOS sandbox: a directory picked via UIDocumentPicker is only readable while
// its security-scoped access is active AND its bookmark survives restarts.
// We persist one bookmark per picked folder (path → bookmark data) in
// UserDefaults, restore access at launch, and keep access alive for the
// process lifetime (the app is a document browser; re-picking re-grants it).

import Foundation

enum SecurityScopedBookmarks {

    private static let storeKey = "fp.ios.securityScopedBookmarks"

    /// Persist security-scoped access for `url` (if not already stored) and
    /// start accessing it. Returns the standardized path, or nil on failure.
    @discardableResult
    static func adopt(_ url: URL) -> String? {
        let path = url.standardizedFileURL.path
        var store = UserDefaults.standard.dictionary(forKey: storeKey) as? [String: Data] ?? [:]
        if store[path] == nil,
           let data = try? url.bookmarkData(
               options: [],
               includingResourceValuesForKeys: nil, relativeTo: nil) {
            store[path] = data
            UserDefaults.standard.set(store, forKey: storeKey)
        }
        _ = url.startAccessingSecurityScopedResource()
        return path
    }

    /// Restore every stored bookmark and start accessing each. Called at app
    /// launch so previously picked folders keep working after a restart.
    /// Returns the list of restored (standardized) paths.
    @discardableResult
    static func restoreAll() -> [String] {
        let store = UserDefaults.standard.dictionary(forKey: storeKey) as? [String: Data] ?? [:]
        var restored: [String] = []
        for (path, data) in store {
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil, bookmarkDataIsStale: &stale) else { continue }
            _ = url.startAccessingSecurityScopedResource()
            restored.append(url.standardizedFileURL.path)
        }
        return restored
    }

    /// Remove a stored bookmark (used when a folder is no longer needed).
    static func forget(_ path: String) {
        var store = UserDefaults.standard.dictionary(forKey: storeKey) as? [String: Data] ?? [:]
        store.removeValue(forKey: path)
        UserDefaults.standard.set(store, forKey: storeKey)
    }
}
