// FreePlayer — iPad entry (SwiftUI lifecycle + WKWebView hosting).

import SwiftUI

@main
struct FreePlayerIOSApp: App {
    var body: some Scene {
        WindowGroup {
            WebContainer()
                .ignoresSafeArea()
        }
    }
}

/// Hosts the full web UI (React bundle) in a WKWebView.
struct WebContainer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> WebViewController {
        WebViewController()
    }

    func updateUIViewController(_ uiViewController: WebViewController, context: Context) {}
}