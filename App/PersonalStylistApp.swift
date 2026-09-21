import SwiftUI
import SwiftData

@main
struct PersonalStylistApp: App {
    private let container: ModelContainer
    private let store: PersistenceStore

    init() {
        let built: (ModelContainer, PersistenceStore)
        do {
            let container = try AppModelContainer.make(inMemory: false)
            let sd = SwiftDataPersistenceStore(container: container)
            // App.init runs on the main actor before scenes appear.
            MainActor.assumeIsolated {
                sd.seedIfNeededSync()
            }
            built = (container, sd)
        } catch {
            assertionFailure("SwiftData container failed: \(error)")
            let container = try! AppModelContainer.make(inMemory: true)
            built = (container, InMemoryPersistenceStore.shared)
        }
        self.container = built.0
        self.store = built.1
        #if DEBUG
        // D-46 / #168: never seed from Info.plist. Debug may seed Keychain from
        // scheme env DEVICE_TOKEN or enroll via ENROLLMENT_SECRET against HTTPS.
        Task {
            await DeviceTokenStore.bootstrapDebugIfNeeded(baseURL: EngineConfig.baseURL)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .environment(\.persistenceStore, store)
        }
        .modelContainer(container)
    }
}
