import XCTest
@testable import OpenDictation

final class TranscriptionCoordinatorTests: XCTestCase {
    func testTranscriptionAdmissionIsFIFO() async throws {
        let coordinator = TranscriptionCoordinator()
        let order = RecordedOrder()
        let firstEntered = AsyncSignal()
        let finishFirst = AsyncSignal()

        let first = Task {
            try await coordinator.withTranscriptionSlot {
                await order.append(1)
                await firstEntered.signal()
                await finishFirst.wait()
            }
        }
        await firstEntered.wait()

        let second = Task {
            try await coordinator.withTranscriptionSlot {
                await order.append(2)
            }
        }
        try await waitForWaiterCount(1, in: coordinator)

        let third = Task {
            try await coordinator.withTranscriptionSlot {
                await order.append(3)
            }
        }
        try await waitForWaiterCount(2, in: coordinator)

        await finishFirst.signal()
        try await first.value
        try await second.value
        try await third.value

        let recordedOrder = await order.values
        XCTAssertEqual(recordedOrder, [1, 2, 3])
    }

    func testCancelledWaiterDoesNotBlockNextTranscription() async throws {
        let coordinator = TranscriptionCoordinator()
        let order = RecordedOrder()
        let firstEntered = AsyncSignal()
        let finishFirst = AsyncSignal()

        let first = Task {
            try await coordinator.withTranscriptionSlot {
                await order.append(1)
                await firstEntered.signal()
                await finishFirst.wait()
            }
        }
        await firstEntered.wait()

        let cancelled = Task {
            try await coordinator.withTranscriptionSlot {
                await order.append(2)
            }
        }
        try await waitForWaiterCount(1, in: coordinator)

        let next = Task {
            try await coordinator.withTranscriptionSlot {
                await order.append(3)
            }
        }
        try await waitForWaiterCount(2, in: coordinator)

        cancelled.cancel()
        do {
            try await cancelled.value
            XCTFail("Expected the queued transcription to be cancelled")
        } catch is CancellationError {
            // Expected cancellation.
        }

        await finishFirst.signal()
        try await first.value
        try await next.value

        let recordedOrder = await order.values
        XCTAssertEqual(recordedOrder, [1, 3])
    }

    func testCancelledActiveTranscriptionReleasesNextSlot() async throws {
        let coordinator = TranscriptionCoordinator()
        let order = RecordedOrder()
        let firstEntered = AsyncSignal()
        let finishFirst = AsyncSignal()

        let first = Task {
            try await coordinator.withTranscriptionSlot {
                await order.append(1)
                await firstEntered.signal()
                await finishFirst.wait()
                try Task.checkCancellation()
            }
        }
        await firstEntered.wait()

        let next = Task {
            try await coordinator.withTranscriptionSlot {
                await order.append(2)
            }
        }
        try await waitForWaiterCount(1, in: coordinator)

        first.cancel()
        await finishFirst.signal()
        do {
            try await first.value
            XCTFail("Expected the active transcription to be cancelled")
        } catch is CancellationError {
            // Expected cancellation.
        }
        try await next.value

        let recordedOrder = await order.values
        XCTAssertEqual(recordedOrder, [1, 2])
    }

    private func waitForWaiterCount(
        _ expectedCount: Int,
        in coordinator: TranscriptionCoordinator
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))

        while await coordinator.waitingTranscriptionCount != expectedCount {
            guard clock.now < deadline else {
                throw AdmissionTestError.timedOutWaitingForQueue(expectedCount)
            }
            await Task.yield()
        }
    }
}

private actor RecordedOrder {
    private(set) var values: [Int] = []

    func append(_ value: Int) {
        values.append(value)
    }
}

private actor AsyncSignal {
    private var isSignalled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isSignalled else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        guard !isSignalled else { return }
        isSignalled = true
        let pendingWaiters = waiters
        waiters.removeAll()
        for waiter in pendingWaiters {
            waiter.resume()
        }
    }
}

private enum AdmissionTestError: Error {
    case timedOutWaitingForQueue(Int)
}
