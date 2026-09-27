import SwiftUI
import SwiftData

@main
struct PersonalStylistApp: App {
    private let modelContainer: ModelContainer?
    private let store: PersistenceStore?
    private let blockedMessage: String?

    init() {
        let opened = OpenedStore()
        let launch = AppStorageLaunch.resolve(
            cleanStart: { try BaselineCleanStart.runIfNeeded() },
            openStore: {
                let container = try AppModelContainer.make(inMemory: false)
                let sd = SwiftDataPersistenceStore(container: container)
                // App.init runs on the main actor before scenes appear.
                MainActor.assumeIsolated {
                    sd.seedIfNeededSync()
                }
                opened.container = container
                opened.store = sd
            }
        )
        self.modelContainer = opened.container
        self.store = opened.store
        self.blockedMessage = launch.blockedMessage
        #if DEBUG
        if let sd = opened.store {
            Task {
                await DeviceTokenStore.bootstrapDebugIfNeeded(baseURL: EngineConfig.baseURL)
                await BaselineUpgradeProbe.runIfRequested(store: sd)
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            if let store, let modelContainer, blockedMessage == nil {
                ContentView(store: store)
                    .environment(\.persistenceStore, store)
                    .modelContainer(modelContainer)
            } else {
                StorageFailureView(message: blockedMessage ?? StorageFailureCopy.wardrobeUnopened)
            }
        }
    }
}

private final class OpenedStore {
    var container: ModelContainer?
    var store: PersistenceStore?
}
