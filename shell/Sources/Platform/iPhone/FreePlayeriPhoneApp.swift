// FreePlayer — standalone iPhone entry point.

import SwiftUI
import UIKit

@main
struct FreePlayeriPhoneApp: App {
    var body: some Scene {
        WindowGroup {
            IPhoneWebContainer()
                .ignoresSafeArea()
        }
    }
}

struct IPhoneWebContainer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> WebViewController {
        WebViewController()
    }

    func updateUIViewController(_ uiViewController: WebViewController, context: Context) {}
}
