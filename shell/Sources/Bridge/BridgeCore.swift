// FreePlayer shell — 通用桥层 (generic bridge core).
//
// WebKit-free dispatch core: a method registry + call lifecycle + outbound
// events. Any transport can feed it — WKScriptMessageHandler today, Android /
// Windows transports later. FreePlayer-specific methods are registered by
// FPBridge (fp注册层); platform-specific methods are registered by the
// PlatformBridge conformance (平台分配层). This file must NOT import WebKit,
// AppKit or UIKit — it compiles unchanged on any platform with Foundation.

import Foundation

/// A single bridge invocation. Handlers may reply asynchronously (background
/// queue, delayed picker callback, …). reply/reject are one-shot: the first
/// call wins, everything after is ignored (the renderer's pending map already
/// drops late resolves — this guard makes the native side match).
final class BridgeCall {
    let id: NSNumber
    let method: String
    let args: [Any]

    private let replyFn: (Any?) -> Void
    private let rejectFn: (String?) -> Void
    private let gate = NSLock()
    private var finished = false

    init(id: NSNumber, method: String, args: [Any],
         reply: @escaping (Any?) -> Void,
         reject: @escaping (String?) -> Void) {
        self.id = id
        self.method = method
        self.args = args
        self.replyFn = reply
        self.rejectFn = reject
    }

    func reply(_ obj: Any?) {
        gate.lock(); defer { gate.unlock() }
        guard !finished else { return }
        finished = true
        replyFn(obj)
    }

    func reject(_ why: String?) {
        gate.lock(); defer { gate.unlock() }
        guard !finished else { return }
        finished = true
        rejectFn(why)
    }
}

/// Generic bridge core: method registry + dispatch + outbound events.
final class BridgeCore {
    typealias Handler = (BridgeCall) -> Void

    private var registry: [String: Handler] = [:]
    private let lock = NSLock()

    /// Outbound event sink — set by the transport (BridgeHandler). Payload
    /// must be JSON-serializable.
    var emitter: ((String, Any) -> Void)?

    func register(_ method: String, _ handler: @escaping Handler) {
        lock.lock(); defer { lock.unlock() }
        registry[method] = handler
    }

    func unregister(_ method: String) {
        lock.lock(); defer { lock.unlock() }
        registry.removeValue(forKey: method)
    }

    /// Registered method names (for tests / diagnostics).
    var registeredMethods: Set<String> {
        lock.lock(); defer { lock.unlock() }
        return Set(registry.keys)
    }

    private func handler(for method: String) -> Handler? {
        lock.lock(); defer { lock.unlock() }
        return registry[method]
    }

    /// Route one renderer call. `reply`/`reject` keep the transport's own
    /// signatures so the transport does not change its serialization.
    func dispatch(method: String, args: [Any], idNum: NSNumber,
                  reply: @escaping (NSNumber, Any?) -> Void,
                  reject: @escaping (NSNumber, String?) -> Void) {
        guard let h = handler(for: method) else {
            reject(idNum, "not implemented: \(method)")
            return
        }
        let call = BridgeCall(id: idNum, method: method, args: args,
                              reply: { reply(idNum, $0) },
                              reject: { reject(idNum, $0) })
        h(call)
    }

    /// Fire an outbound event toward the renderer (e.g. EQ sync).
    func emit(_ channel: String, _ payload: Any) {
        emitter?(channel, payload)
    }
}
