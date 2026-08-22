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
}
