import XCTest
@testable import ForegroundMaskHarness

final class MockProcessor: MaskProcessing {
    var completion: ((Result<Data, Error>) -> Void)?
    var starts = 0
    var cancellations = 0
    func start(source: Data, insetCrop: Bool, completion: @escaping (Result<Data, Error>) -> Void) {
        starts += 1; self.completion = completion
    }
    func cancel() { cancellations += 1 }
}

final class ProbeTests: XCTestCase {
    @MainActor func deliver(_ result: Result<Data, Error>, mock: MockProcessor, model: ProbeModel) async {
        let completed = expectation(description: "Worker result consumed")
        model.didComplete = { completed.fulfill() }
        mock.completion?(result)
        await fulfillment(of: [completed], timeout: 2)
        model.didComplete = nil
    }

    @MainActor func testSuccessPreservesSourceAndRejectsConcurrentRun() async {
        let original = Data([1]), mock = MockProcessor()
        let model = ProbeModel(source: original, processor: mock)
        model.run(insetCrop: false); model.run(insetCrop: true)
        XCTAssertEqual(mock.starts, 1)
        await deliver(.success(Data([2])), mock: mock, model: model)
        XCTAssertEqual(model.source, original)
        XCTAssertEqual(model.candidate, Data([2])); XCTAssertFalse(model.busy)
    }

    @MainActor func testEmptyAndErrorPreservePreviousPreview() async {
        let mock = MockProcessor()
        let subject = ProbeModel(source: Data([1]), processor: mock)
        subject.run(insetCrop: false)
        await deliver(.success(Data([2])), mock: mock, model: subject)
        for error in [MaskFailure.empty, .ambiguous, .decode, .render] {
            subject.run(insetCrop: false)
            await deliver(.failure(error), mock: mock, model: subject)
            XCTAssertEqual(subject.candidate, Data([2])); XCTAssertEqual(subject.source, Data([1]))
        }
    }

    @MainActor func testEmptySuccessKeepsPreviousPreview() async {
        let mock = MockProcessor()
        let model = ProbeModel(source: Data([1]), processor: mock)
        model.run(insetCrop: false)
        await deliver(.success(Data([2])), mock: mock, model: model)
        model.run(insetCrop: false)
        await deliver(.success(Data()), mock: mock, model: model)
        XCTAssertEqual(model.candidate, Data([2]))
        XCTAssertEqual(model.source, Data([1]))
        XCTAssertFalse(model.busy)
    }

    @MainActor func testCancellationDiscardsSuccessAndWaitsForWorker() async {
        let mock = MockProcessor()
        let subject = ProbeModel(source: Data([1]), processor: mock)
        subject.run(insetCrop: false); subject.cancel(); subject.run(insetCrop: false)
        XCTAssertTrue(subject.busy); XCTAssertEqual(mock.starts, 1); XCTAssertEqual(mock.cancellations, 1)
        await deliver(.success(Data([9])), mock: mock, model: subject)
        XCTAssertNil(subject.candidate); XCTAssertFalse(subject.busy)
        subject.run(insetCrop: false); XCTAssertEqual(mock.starts, 2)
    }

    @MainActor func testChangedSourceRejectsStaleCompletion() async {
        let mock = MockProcessor()
        let model = ProbeModel(source: Data([1]), processor: mock)
        model.run(insetCrop: false); model.setSource(Data([3]))
        await deliver(.success(Data([9])), mock: mock, model: model)
        XCTAssertEqual(model.source, Data([3])); XCTAssertNil(model.candidate)
    }

    func testSelectionPolicyFailsClosed() throws {
        XCTAssertThrowsError(try VisionMaskProcessor.select(IndexSet()))
        XCTAssertThrowsError(try VisionMaskProcessor.select(IndexSet([1, 2])))
        XCTAssertEqual(try VisionMaskProcessor.select(IndexSet(integer: 4)), IndexSet(integer: 4))
    }
}
