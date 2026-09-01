import SwiftUI

/// Simple dark backdrop with soft vignette for auth screens.
struct StadiumAuthBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.11),
                    Color(red: 0.09, green: 0.10, blue: 0.13),
                    Color(red: 0.05, green: 0.07, blue: 0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.45)
                ],
                center: .center,
                startRadius: 120,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}

#Preview {
    StadiumAuthBackground()
}
