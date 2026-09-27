import XCTest
@testable import PersonalStylist

final class BaselineUpgradeProbeProfileTests: XCTestCase {
    private let higherID = UUID(uuidString: "C3120F0B-517B-4BCC-B719-7F0D4FCC9AC1")!

    func testProbeOnlySelectionHasNoPreservationProblem() {
        let probe = profile(id: BaselineUpgradeProbe.profileID, version: 1)
        let problems = BaselineUpgradeProbe.profilePreservationProblems(
            rows: [probe],
            selected: probe,
            recordedCurrentID: probe.id,
            recordedCurrentVersion: 1
        )
        XCTAssertEqual(problems, [])
    }

    func testCoexistingHigherVersionStaysCurrentAndProbeRowRemains() async throws {
        let store = InMemoryPersistenceStore(garments: [], sets: [])
        let probe = profile(id: BaselineUpgradeProbe.profileID, version: 1)
        let current = profile(
            id: higherID,
            version: 22,
            profession: "Loop checker",
            goals: ["check loops"],
            constraints: "Keep both"
        )
        try await store.saveStyleProfile(probe)
        try await store.saveStyleProfile(current)

        let selected = await store.fetchStyleProfile()
        let rows = await store.fetchAllStyleProfiles()
        XCTAssertEqual(selected?.id, higherID)
        XCTAssertEqual(selected?.version, 22)
        XCTAssertEqual(Set(rows.map(\.id)), [BaselineUpgradeProbe.profileID, higherID])

        let before = rows
        let problems = BaselineUpgradeProbe.profilePreservationProblems(
            rows: rows,
            selected: selected,
            recordedCurrentID: nil,
            recordedCurrentVersion: nil
        )
        XCTAssertEqual(problems, [])
        XCTAssertEqual(rows, before)

        let after = await store.fetchAllStyleProfiles()
        XCTAssertEqual(Set(after.map(\.id)), [BaselineUpgradeProbe.profileID, higherID])
        XCTAssertEqual(after.first { $0.id == BaselineUpgradeProbe.profileID }?.profession, "Architect")
        XCTAssertEqual(after.first { $0.id == BaselineUpgradeProbe.profileID }?.goals, ["fewer repeats"])
        XCTAssertEqual(after.first { $0.id == BaselineUpgradeProbe.profileID }?.constraintsNotes, "No logos")
    }

    func testRecordedProbeRemainsWhenALaterProfileBecomesCurrent() {
        let probe = profile(id: BaselineUpgradeProbe.profileID, version: 1)
        let current = profile(id: higherID, version: 22, profession: "Loop checker", goals: [], constraints: nil)
        let problems = BaselineUpgradeProbe.profilePreservationProblems(
            rows: [current, probe],
            selected: current,
            recordedCurrentID: probe.id,
            recordedCurrentVersion: 1
        )
        XCTAssertEqual(problems, [])
    }

    func testMissingProbeRowReportsProfileAndLeavesRowsUntouched() {
        let current = profile(id: higherID, version: 22, profession: "Loop checker", goals: [], constraints: nil)
        let rows = [current]
        let snapshot = rows
        let problems = BaselineUpgradeProbe.profilePreservationProblems(
            rows: rows,
            selected: current,
            recordedCurrentID: current.id,
            recordedCurrentVersion: 22
        )
        XCTAssertEqual(problems, ["profile"])
        XCTAssertEqual(rows, snapshot)
    }

    func testProbeFieldMismatchReportsProfileWhileBothRowsRemain() async throws {
        let store = InMemoryPersistenceStore(garments: [], sets: [])
        let probe = profile(id: BaselineUpgradeProbe.profileID, version: 1, profession: "Changed")
        let current = profile(id: higherID, version: 22, profession: "Loop checker", goals: [], constraints: nil)
        try await store.saveStyleProfile(probe)
        try await store.saveStyleProfile(current)
        let rows = await store.fetchAllStyleProfiles()
        let problems = BaselineUpgradeProbe.profilePreservationProblems(
            rows: rows,
            selected: current,
            recordedCurrentID: current.id,
            recordedCurrentVersion: 22
        )
        XCTAssertEqual(problems, ["profile"])
        let after = await store.fetchAllStyleProfiles()
        XCTAssertEqual(after.count, 2)
        XCTAssertEqual(after.first { $0.id == BaselineUpgradeProbe.profileID }?.profession, "Changed")
        XCTAssertEqual(after.first { $0.id == higherID }?.version, 22)
    }

    func testSelectingTheLowerProbeWhileAHigherRowExistsReportsCurrent() {
        let probe = profile(id: BaselineUpgradeProbe.profileID, version: 1)
        let current = profile(id: higherID, version: 22, profession: "Loop checker", goals: [], constraints: nil)
        let problems = BaselineUpgradeProbe.profilePreservationProblems(
            rows: [probe, current],
            selected: probe,
            recordedCurrentID: nil,
            recordedCurrentVersion: nil
        )
        XCTAssertEqual(problems, ["profile-current"])
    }

    func testMissingRecordedCurrentRowReportsCurrentWhileProbeRemains() {
        let probe = profile(id: BaselineUpgradeProbe.profileID, version: 1)
        let problems = BaselineUpgradeProbe.profilePreservationProblems(
            rows: [probe],
            selected: probe,
            recordedCurrentID: higherID,
            recordedCurrentVersion: 22
        )
        XCTAssertEqual(problems, ["profile-current"])
        XCTAssertEqual(probe.profession, BaselineUpgradeProbe.profession)
    }

    func testRecordedCurrentVersionDriftReportsCurrent() {
        let probe = profile(id: BaselineUpgradeProbe.profileID, version: 2)
        let problems = BaselineUpgradeProbe.profilePreservationProblems(
            rows: [probe],
            selected: probe,
            recordedCurrentID: probe.id,
            recordedCurrentVersion: 1
        )
        XCTAssertEqual(problems, ["profile-current"])
    }

    private func profile(
        id: UUID,
        version: Int,
        profession: String? = "Architect",
        goals: [String] = ["fewer repeats"],
        constraints: String? = "No logos"
    ) -> StubStyleProfile {
        StubStyleProfile(
            id: id,
            age: nil,
            profession: profession,
            workEnvironment: "studio",
            workEnvironmentLabel: "Studio",
            typicalWeekNotes: nil,
            goals: goals,
            constraintsNotes: constraints,
            experimentationLevel: 2,
            summary: nil,
            summaryUserOwned: false,
            version: version,
            confirmedAt: Date(timeIntervalSince1970: 1_758_000_000),
            seedSource: nil
        )
    }
}
