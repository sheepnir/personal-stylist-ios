import Foundation
import UIKit

#if DEBUG
/// Installed-app upgrade probe. Debug builds only. Release archives do not include it.
/// Write on the baseline build, then install a later build over it and verify.
enum BaselineUpgradeProbe {
    static let writeArgument = "-BaselineUpgradeWrite"
    static let verifyArgument = "-BaselineUpgradeVerify"
    static let expectedFileName = "baseline-upgrade-expected.txt"
    static let resultFileName = "baseline-upgrade-result.txt"

    static let garmentID = UUID(uuidString: "B1000001-0000-4000-8000-000000000001")!
    static let profileID = UUID(uuidString: "B1000001-0000-4000-8000-000000000002")!
    static let wearID = UUID(uuidString: "B1000001-0000-4000-8000-000000000003")!
    static let displayName = "Navy baseline coat"
    static let profession = "Architect"
    static let colorName = "Navy"
    static let price = Decimal(string: "120.00")!

    static func runIfRequested(store: PersistenceStore) async {
        let args = ProcessInfo.processInfo.arguments
        if args.contains(writeArgument) {
            await write(store)
        } else if args.contains(verifyArgument) {
            await verify(store)
        }
    }

    private static func write(_ store: PersistenceStore) async {
        do {
            let jpeg = tinyJPEG()
            let path = try UserGarmentPhotoStore.persistJPEG(from: jpeg, garmentId: garmentID)
            let garment = StubGarment(
                id: garmentID,
                displayName: displayName,
                slot: .outerwear,
                readiness: .ready,
                availability: "AVAILABLE",
                colorPrimary: StubColorPrimary(family: "blue", hex: "#1B3A4B", name: colorName),
                pattern: "solid",
                surface: nil,
                imagePath: path,
                formality: 3,
                warmth: 4,
                displayNameSource: "USER",
                purchasePrice: price,
                purchaseCurrency: "USD"
            )
            try await store.saveGarment(garment)
            try await store.saveStyleProfile(
                StubStyleProfile(
                    id: profileID,
                    age: nil,
                    profession: profession,
                    workEnvironment: "studio",
                    workEnvironmentLabel: "Studio",
                    typicalWeekNotes: "Client meetings",
                    goals: ["fewer repeats"],
                    constraintsNotes: "No logos",
                    experimentationLevel: 2,
                    summary: nil,
                    summaryUserOwned: false,
                    version: 1,
                    confirmedAt: Date(timeIntervalSince1970: 1_758_000_000),
                    seedSource: nil
                )
            )
            try await store.saveWearEvent(
                StubWearEvent(
                    id: wearID,
                    garmentIds: [garmentID],
                    wornOn: Date(timeIntervalSince1970: 1_758_086_400)
                )
            )
            let photoURL = try photoFileURL()
            let photoCount = try Data(contentsOf: photoURL).count
            let build = bundleVersion()
            let selected = await store.fetchStyleProfile()
            var expected = "build=\(build)\nphotoBytes=\(photoCount)\n"
            if let selected {
                expected += "currentProfileId=\(selected.id.uuidString)\ncurrentProfileVersion=\(selected.version)\n"
            }
            try writeText(expected, name: expectedFileName)
            try writeText("wrote\n", name: resultFileName)
        } catch {
            try? writeText("write-failed\n", name: resultFileName)
        }
    }

    private static func verify(_ store: PersistenceStore) async {
        var problems: [String] = []
        let expected = (try? readText(name: expectedFileName)) ?? ""
        let fields = Dictionary(uniqueKeysWithValues: expected.split(separator: "\n").compactMap { line -> (String, String)? in
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return (parts[0], parts[1])
        })
        let writtenBuild = fields["build"] ?? ""
        let build = bundleVersion()
        if writtenBuild.isEmpty || build <= writtenBuild {
            problems.append("build")
        }
        let garments = await store.fetchGarments()
        guard let garment = garments.first(where: { $0.id == garmentID }) else {
            problems.append("garment")
            try? writeText(problems.joined(separator: ",") + "\n", name: resultFileName)
            return
        }
        if garment.displayName != displayName { problems.append("name") }
        if garment.colorPrimary?.name != colorName { problems.append("color") }
        if garment.purchasePrice != price { problems.append("price") }
        if garment.purchaseCurrency != "USD" { problems.append("currency") }
        if garment.formality != 3 || garment.warmth != 4 { problems.append("metadata") }
        if garment.displayNameSource != "USER" { problems.append("name-source") }
        if let url = try? photoFileURL(),
           let count = try? Data(contentsOf: url).count,
           String(count) == fields["photoBytes"],
           count > 0 {
            // photo file survived
        } else {
            problems.append("photo")
        }
        let rows = await (store as? BaselineUpgradeProfileListing)?.fetchAllStyleProfiles() ?? []
        if (store as? BaselineUpgradeProfileListing) == nil {
            problems.append("profile")
        }
        let selected = await store.fetchStyleProfile()
        let recordedID = fields["currentProfileId"].flatMap(UUID.init(uuidString:))
        let recordedVersion = fields["currentProfileVersion"].flatMap(Int.init)
        if fields["currentProfileId"] != nil && recordedID == nil {
            problems.append("profile-current")
        }
        problems.append(contentsOf: profilePreservationProblems(
            rows: rows,
            selected: selected,
            recordedCurrentID: recordedID,
            recordedCurrentVersion: recordedVersion
        ))
        let wears = await store.fetchWearEvents()
        if wears.contains(where: { $0.id == wearID && $0.garmentIds == [garmentID] && $0.voidedAt == nil }) == false {
            problems.append("wear")
        }
        if fields["currentProfileVersion"] != nil && recordedVersion == nil {
            problems.append("profile-current")
        }
        let line = problems.isEmpty ? "ok \(build)\n" : uniqueTokens(problems).joined(separator: ",") + "\n"
        try? writeText(line, name: resultFileName)
    }

    /// Probe row by fixed id, and the selected row as the highest version. Does not add, change, or delete rows.
    static func profilePreservationProblems(
        rows: [StubStyleProfile],
        selected: StubStyleProfile?,
        recordedCurrentID: UUID?,
        recordedCurrentVersion: Int?
    ) -> [String] {
        var problems: [String] = []
        let probe = rows.first { $0.id == profileID }
        if probe?.profession != profession
            || probe?.goals != ["fewer repeats"]
            || probe?.constraintsNotes != "No logos" {
            problems.append("profile")
        }
        let maxVersion = rows.map(\.version).max()
        let selectedIsCurrent = selected.map { chosen in
            chosen.version == maxVersion && rows.contains { $0.id == chosen.id && $0.version == chosen.version }
        } ?? false
        if !selectedIsCurrent {
            problems.append("profile-current")
        }
        if let recordedCurrentID {
            if let recorded = rows.first(where: { $0.id == recordedCurrentID }) {
                if let recordedCurrentVersion, recorded.version != recordedCurrentVersion {
                    problems.append("profile-current")
                }
                if let selected, selected.id != recorded.id, selected.version <= recorded.version {
                    problems.append("profile-current")
                }
            } else {
                problems.append("profile-current")
            }
        }
        return uniqueTokens(problems)
    }

    private static func uniqueTokens(_ tokens: [String]) -> [String] {
        var seen = Set<String>()
        return tokens.filter { seen.insert($0).inserted }
    }

    private static func bundleVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    private static func tinyJPEG() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        let image = renderer.image { context in
            UIColor(red: 0.11, green: 0.23, blue: 0.29, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        return image.jpegData(compressionQuality: 0.8) ?? Data()
    }

    private static func photoFileURL() throws -> URL {
        try documents()
            .appendingPathComponent(UserGarmentPhotoStore.directoryName, isDirectory: true)
            .appendingPathComponent("\(garmentID.uuidString).jpg")
    }

    private static func documents() throws -> URL {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return docs
    }

    private static func writeText(_ text: String, name: String) throws {
        let url = try documents().appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func readText(name: String) throws -> String {
        try String(contentsOf: try documents().appendingPathComponent(name), encoding: .utf8)
    }
}

protocol BaselineUpgradeProfileListing: AnyObject {
    func fetchAllStyleProfiles() async -> [StubStyleProfile]
}

extension InMemoryPersistenceStore: BaselineUpgradeProfileListing {}
extension SwiftDataPersistenceStore: BaselineUpgradeProfileListing {}
#endif
