import SwiftUI
import UIKit

enum AppAppearance {
    static func configureNavigationBar() {
        let background = UIColor(DesignTokens.background)
        let titleColor = UIColor.white

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = background
        appearance.titleTextAttributes = [.foregroundColor: titleColor]
        appearance.largeTitleTextAttributes = [.foregroundColor: titleColor]
        appearance.shadowColor = .clear

        let nav = UINavigationBar.appearance()
        nav.standardAppearance = appearance
        nav.scrollEdgeAppearance = appearance
        nav.compactAppearance = appearance
        nav.tintColor = .white
        nav.barStyle = .black
    }

    static func configureTabBar() {
        let background = UIColor(DesignTokens.background)

        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = background
        appearance.shadowColor = .clear

        let item = UITabBarItemAppearance()
        let white: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.white]
        item.normal.iconColor = .white
        item.normal.titleTextAttributes = white
        item.selected.iconColor = .white
        item.selected.titleTextAttributes = white
        appearance.stackedLayoutAppearance = item
        appearance.inlineLayoutAppearance = item
        appearance.compactInlineLayoutAppearance = item

        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.tintColor = .white
        tabBar.unselectedItemTintColor = .white
        tabBar.barStyle = .black
    }

    static func configureWindow() {
        let background = UIColor(DesignTokens.background)
        UIWindow.appearance().backgroundColor = background
    }
}
