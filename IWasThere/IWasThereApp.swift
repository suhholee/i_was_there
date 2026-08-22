import SwiftUI
import SwiftData

@main
struct IWasThereApp: App {
    private let container: ModelContainer

    init() {
        AppAppearance.configureNavigationBar()
        container = Self.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.modelContext, container.mainContext)
        }
        .modelContainer(container)
    }

    private static func makeContainer() -> ModelContainer {
        let schema = Schema([
            UserProfile.self,
            AttendedGame.self,
            GamePlayerStat.self,
            GamePhoto.self
        ])
        // Named store avoids colliding with older prototype default.store files.
        let configuration = ModelConfiguration(
            "IWasThereStore",
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            Self.wipeStoreFiles(around: configuration.url)
            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                let memory = ModelConfiguration(
                    "IWasThereMemory",
                    schema: schema,
                    isStoredInMemoryOnly: true
                )
                return try! ModelContainer(for: schema, configurations: [memory])
            }
        }
    }

    private static func wipeStoreFiles(around url: URL) {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        try? fm.removeItem(at: url)
        for ext in ["store", "sqlite", "sqlite-wal", "sqlite-shm"] {
            try? fm.removeItem(at: dir.appendingPathComponent("\(base).\(ext)"))
        }
        if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.contains("IWasThere") || file.lastPathComponent.contains("default") {
                try? fm.removeItem(at: file)
            }
        }
    }
}
