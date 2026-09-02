import SwiftUI
import UIKit

/// Handles Simulator / device external displays so they are not an empty black window.
final class ExternalDisplaySceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let background = UIColor(DesignTokens.background)
        let hosting = UIHostingController(rootView: ExternalDisplayRootView())
        hosting.view.backgroundColor = background

        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = background
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        self.window = window
    }
}

private struct ExternalDisplayRootView: View {
    var body: some View {
        ZStack {
            DesignTokens.background.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "baseball.fill")
                    .font(.largeTitle)
                    .foregroundStyle(DesignTokens.accent)
                Text("#iWasThere")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(DesignTokens.primaryText)
            }
        }
        .preferredColorScheme(.dark)
    }
}

enum SceneSessionRoleHelpers {
    static func isExternalDisplay(_ role: UISceneSession.Role) -> Bool {
        role.rawValue.lowercased().contains("external")
    }
}
