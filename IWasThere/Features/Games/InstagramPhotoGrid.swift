import SwiftUI

/// Instagram-style square photo grid: 2 columns when narrow, 3 when wider.
struct InstagramPhotoGrid<Accessory: View>: View {
    let relativePaths: [String]
    var spacing: CGFloat = 2
    var narrowBreakpoint: CGFloat = 360
    @ViewBuilder var accessory: (Int) -> Accessory

    @State private var containerWidth: CGFloat = 390

    private var columns: Int {
        containerWidth < narrowBreakpoint ? 2 : 3
    }

    var body: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: spacing),
                count: columns
            ),
            spacing: spacing
        ) {
            ForEach(Array(relativePaths.enumerated()), id: \.offset) { index, path in
                ZStack(alignment: .topTrailing) {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            GamePhotoThumbnail(relativePath: path)
                        }
                        .clipped()
                    accessory(index)
                }
                .aspectRatio(1, contentMode: .fit)
                .clipped()
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { containerWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, newWidth in
                        if newWidth > 0 {
                            containerWidth = newWidth
                        }
                    }
            }
        )
    }
}

extension InstagramPhotoGrid where Accessory == EmptyView {
    init(relativePaths: [String], spacing: CGFloat = 2, narrowBreakpoint: CGFloat = 360) {
        self.relativePaths = relativePaths
        self.spacing = spacing
        self.narrowBreakpoint = narrowBreakpoint
        self.accessory = { _ in EmptyView() }
    }
}
