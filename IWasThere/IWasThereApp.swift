import SwiftUI
import SwiftData

@main
struct IWasThereApp: App {
    @State private var container: ModelContainer?

    init() {
        AppAppearance.configureNavigationBar()
        AppAppearance.configureTabBar()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    RootTabView()
                        .modelContainer(container)
                } else {
                    LaunchLoadingView()
                }
            }
            .task {
                guard container == nil else { return }
                container = Self.makeContainer()
            }
        }
    }

    /// Bump when the SwiftData schema changes incompatibly (e.g. adding `GameFriend`).
    private static let storeSchemaVersion = 2
    private static let schemaVersionKey = "IWasThereStoreSchemaVersion"

    private static func makeContainer() -> ModelContainer {
        prepareStoreForSchemaUpgrade()

        let schema = Schema([
            UserProfile.self,
            AttendedGame.self,
            GamePlayerStat.self,
            GamePhoto.self,
            GameFriend.self
        ])
        // Named store avoids colliding with older prototype default.store files.
        let configuration = ModelConfiguration(
            "IWasThereStore",
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            markStoreSchemaCurrent()
            return container
        } catch {
            wipeStoreFiles(around: configuration.url)
            wipeLegacyStoreFiles()
            do {
                let container = try ModelContainer(for: schema, configurations: [configuration])
                markStoreSchemaCurrent()
                return container
            } catch {
                let memory = ModelConfiguration(
                    "IWasThereMemory",
                    schema: schema,
                    isStoredInMemoryOnly: true
                )
                return (try? ModelContainer(for: schema, configurations: [memory]))
                    ?? emergencyInMemoryContainer(schema: schema)
            }
        }
    }

    /// Wipe only when we know a prior schema was saved and no longer matches.
    private static func prepareStoreForSchemaUpgrade() {
        let savedVersion = UserDefaults.standard.integer(forKey: schemaVersionKey)
        guard savedVersion > 0, savedVersion < storeSchemaVersion else { return }
        wipeLegacyStoreFiles()
    }

    private static func markStoreSchemaCurrent() {
        UserDefaults.standard.set(storeSchemaVersion, forKey: schemaVersionKey)
    }

    private static func emergencyInMemoryContainer(schema: Schema) -> ModelContainer {
        let memory = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [memory])
    }

    private static func wipeStoreFiles(around url: URL) {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        try? fm.removeItem(at: url)
        for ext in ["store", "sqlite", "sqlite-wal", "sqlite-shm"] {
            try? fm.removeItem(at: dir.appendingPathComponent("\(base).\(ext)"))
        }
    }

    private static func wipeLegacyStoreFiles() {
        let fm = FileManager.default
        let dirs = [
            fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            fm.urls(for: .documentDirectory, in: .userDomainMask).first
        ].compactMap { $0 }

        for dir in dirs {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
                continue
            }
            for file in files {
                let name = file.lastPathComponent
                let lower = name.lowercased()
                if lower.contains("iwasthere")
                    || lower == "default.store"
                    || lower.hasSuffix(".store")
                    || lower.hasSuffix(".sqlite")
                    || lower.hasSuffix(".sqlite-wal")
                    || lower.hasSuffix(".sqlite-shm") {
                    try? fm.removeItem(at: file)
                }
            }
        }
    }
}

private struct LaunchLoadingView: View {
    var body: some View {
        ZStack {
            DesignTokens.background.ignoresSafeArea()
            ProgressView()
                .tint(.white)
        }
        .preferredColorScheme(.dark)
    }
}
