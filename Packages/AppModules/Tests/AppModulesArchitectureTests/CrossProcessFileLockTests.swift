import Foundation
import SecurityStorage
import Testing

/// Pure boundary checks; these paths never open a file or require an entitled container.
@Suite
struct CrossProcessFileLockTests {
    @Test
    func aMissingLiveContainerNeverFallsBackToProcessOnly() {
        var ran = false
        let lock = CrossProcessFileLock(containerURL: nil, filename: ".fixture-token.lock")
        #expect(throws: CrossProcessFileLockError.missingContainer) {
            try lock.withExclusiveLock { ran = true }
        }
        #expect(!ran)
    }

    @Test
    func processOnlyMustBeExplicitAndPropagatesOperationFailure() throws {
        let lock = CrossProcessFileLock(containerURL: nil, filename: ".fixture-token.lock", policy: .processOnly)
        #expect(try lock.withExclusiveLock { 42 } == 42)
        #expect(throws: FixtureFailure.operation) {
            try lock.withExclusiveLock { throw FixtureFailure.operation }
        }
        // Throwing must release the process lock too.
        #expect(try lock.withExclusiveLock { 43 } == 43)
    }

    @Test(arguments: ["", ".", "..", "../escape", "nested/file", "nested\\file", "nul\0name"])
    func filenamesMustBeSingleNonemptyLeaves(_ filename: String) {
        var ran = false
        let lock = CrossProcessFileLock(containerURL: nil, filename: filename, policy: .processOnly)
        #expect(throws: CrossProcessFileLockError.invalidFilename) {
            try lock.withExclusiveLock { ran = true }
        }
        #expect(!ran)
    }

    private enum FixtureFailure: Error, Equatable { case operation }
}
