// FreePlayer shell — fp layer: native HTTP (no CORS, stable on unreliable links).
// Split out of FPBridge.swift; wired up by FPBridge.registerAll.

import Foundation

extension FPBridge {

    static func registerNetwork(into core: BridgeCore) {
        // ── Network (native stack: no CORS, stable on unreliable links) ──
        core.register("httpGetJson") { call in
            let urlStr = call.args.first as? String ?? ""
            HttpClient.httpGet(urlStr,
                { result, data in
                    let parsed = (try? JSONSerialization.jsonObject(with: data)) ?? NSNull()
                    result["body"] = parsed
                },
                { result in call.reply(result) })
        }

        core.register("httpGetBase64") { call in
            let urlStr = call.args.first as? String ?? ""
            HttpClient.httpGet(urlStr,
                { result, data in
                    result["base64"] = data.base64EncodedString()
                },
                { result in call.reply(result) })
        }
    }
}
