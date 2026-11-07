import Domain
import Foundation
@testable import SendPresentation
import Testing

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct SendModelTests {
    @Test
    func unsubmittedSaveRetainsTheDraftButShowsRefreshRecoveryGuidance() async {
        let repository = TestSendRepository(summaries: [], blocksSave: true)
        let model = makeModel(repository: repository)
        var draft = SendDraft(contentKind: .text)
        draft.name = "Fixture Send"; draft.text = "fixture text"
        model.updateDraft(draft)
        let save = Task { await model.saveDraft() }
        await repository.waitForSaveStart()
        await repository.finishAuthorizationFailure()
        await save.value
        #expect(model.state.errorMessage == SessionAuthorizationError.refreshRecoveryRequired.errorDescription)
        #expect(model.state.draft != nil)
        #expect(await repository.saveCallCount() == 1)
    }

    @Test
    func duplicateSaveSubmissionIsIgnoredWhileTheFirstCommitIsInFlight() async {
        let repository = TestSendRepository(summaries: [summary("created")], blocksSave: true)
        let model = makeModel(repository: repository)
        var draft = SendDraft(contentKind: .text)
        draft.name = "A Send"
        draft.text = "secret text"
        model.updateDraft(draft)

        let firstSave = Task { await model.saveDraft() }
        await repository.waitForSaveStart()
        await model.saveDraft()
        #expect(await repository.saveCallCount() == 1)

        await repository.finishSave(with: [summary("created")])
        await firstSave.value
        #expect(model.state.draft == nil)
        #expect(model.state.summaries.map(\.id.rawValue) == ["created"])
    }

    @Test
    func cancelledSheetConsumerStillProjectsAndConfirmsAnAcknowledgedSave() async {
        let repository = TestSendRepository(summaries: [summary("created")], blocksSave: true)
        let model = makeModel(repository: repository)
        var draft = SendDraft(contentKind: .text)
        draft.name = "A Send"
        draft.text = "secret text"
        model.updateDraft(draft)

        let sheetTask = Task { await model.saveDraft() }
        await repository.waitForSaveStart()
        sheetTask.cancel()
        await repository.finishSave(with: [summary("created")])
        await sheetTask.value

        #expect(model.state.summaries.map(\.id.rawValue) == ["created"])
        #expect(model.state.draft == nil)
        #expect(await repository.saveCallCount() == 1)
    }

    @Test
    func deletingTheSelectedSendClearsSelectionAfterRepositorySnapshotChanges() async {
        let first = summary("first")
        let second = summary("second")
        let repository = TestSendRepository(summaries: [first, second])
        let model = makeModel(repository: repository)
        await model.load()
        model.select(first.id)
        model.requestDelete(first.id)
        await model.confirmDelete()

        #expect(model.state.summaries.map(\.id.rawValue) == ["second"])
        #expect(model.state.selectedSendID == nil)
        #expect(model.state.selectedDetails == nil)
    }

    @Test
    func undecryptableSendIsRetainedAsAnExplicitPerItemError() async {
        let repository = TestSendRepository(summaries: [summary("good"), summary("bad", canOpen: false)])
        let model = makeModel(repository: repository)
        await model.load()

        #expect(model.state.summaries.count == 2)
        #expect(model.state.summaries.first(where: { $0.id.rawValue == "good" })?.canOpen == true)
        #expect(model.state.summaries.first(where: { $0.id.rawValue == "bad" })?.canOpen == false)
        model.select(SendID(rawValue: "bad"))
        #expect(model.state.detailErrorMessage != nil)
    }

    @Test
    func acknowledgedFailureClosesTheDraftBeforeACancelledConsumerCanSkipErrorUI() async {
        for error in [SendRepositoryError.fileUploadFailed, .committedButCleanupFailed,
                      .fileUploadAndCleanupFailed, .committedButFollowUpFailed,
                      .mutationOutcomeUnknown, .mutationOutcomeUnknownAndCleanupFailed] {
            let repository = TestSendRepository(summaries: [summary("created")], blocksSave: true)
            let model = makeModel(repository: repository, checkSessionAccess: { try Task.checkCancellation() })
            var draft = SendDraft(contentKind: .text)
            draft.name = "A Send"
            draft.text = "synthetic text"
            model.updateDraft(draft)
            let consumer = Task { await model.saveDraft() }
            await repository.waitForSaveStart()
            consumer.cancel()
            await repository.finishSave(throwing: error)
            await consumer.value
            #expect(model.state.draft == nil)
            #expect(await repository.saveCallCount() == 1)
            #expect(!model.state.isSaving)
        }
    }

    @Test
    func confirmedUploadCleanupErrorOffersLockAndNeverASecondCreate() async {
        let repository = TestSendRepository(summaries: [summary("created")], blocksSave: true)
        let model = makeModel(repository: repository)
        var draft = SendDraft(contentKind: .text)
        draft.name = "A Send"
        draft.text = "synthetic text"
        model.updateDraft(draft)
        let save = Task { await model.saveDraft() }
        await repository.waitForSaveStart()
        await repository.finishSave(throwing: .committedButCleanupFailed)
        await save.value
        #expect(model.state.draft == nil)
        #expect(model.state.summaries.map(\.id.rawValue) == ["created"])
        #expect(model.state.errorMessage?.contains("Lock the app") == true)
        #expect(model.state.errorMessage?.contains("file uploaded") == true)
        await model.saveDraft()
        #expect(await repository.saveCallCount() == 1)
    }

    @Test
    func invalidAccessLimitsNeverReachTheRepository() async {
        let repository = TestSendRepository(summaries: [])
        let model = makeModel(repository: repository)
        for count in [Int.min, 0, Int(UInt32.max) + 1, Int.max] {
            var draft = SendDraft(contentKind: .text)
            draft.name = "A Send"
            draft.text = "synthetic text"
            draft.hasMaxAccessCount = true
            draft.maxAccessCount = count
            model.updateDraft(draft)
            await model.saveDraft()
            #expect(model.state.draft != nil)
            #expect(model.state.errorMessage != nil)
        }
        #expect(await repository.saveCallCount() == 0)
    }

    @Test
    func serverErrorNamesTheActionInsteadOfDisplayingAnInterpolationPlaceholder() async {
        let repository = TestSendRepository(summaries: [], blocksSave: true)
        let model = makeModel(repository: repository)
        var draft = SendDraft(contentKind: .text)
        draft.name = "A Send"
        draft.text = "synthetic text"
        model.updateDraft(draft)
        let save = Task { await model.saveDraft() }
        await repository.waitForSaveStart()
        await repository.finishSave(throwing: .server(statusCode: 503))
        await save.value
        #expect(model.state.errorMessage?.contains("save this Send") == true)
        #expect(model.state.errorMessage?.contains("(action)") == false)
        #expect(model.state.draft != nil)
    }

    @Test
    func lateEditCannotReplaceTheSubmittedDraftWhileItsCommitIsInFlight() async {
        let repository = TestSendRepository(summaries: [], blocksSave: true, blocksEdit: true)
        let model = makeModel(repository: repository)
        var original = SendDraft(contentKind: .text)
        original.name = "Submitted"
        original.text = "synthetic text"
        model.updateDraft(original)
        let edit = Task { await model.editSend(SendID(rawValue: "other")) }
        await repository.waitForEditStart()
        let save = Task { await model.saveDraft() }
        await repository.waitForSaveStart()
        var late = SendDraft(contentKind: .text)
        late.name = "Obsolete edit"
        late.editingID = SendID(rawValue: "other")
        await repository.finishEdit(with: late)
        await edit.value
        #expect(model.state.draft?.name == "Submitted")
        await repository.finishSave(with: [summary("created")])
        await save.value
        #expect(model.state.draft == nil)
    }

    @Test
    func latePickerCannotReopenADraftAfterAnAcknowledgedCreate() async {
        let repository = TestSendRepository(summaries: [], blocksSave: true)
        let importer = GatedSendFileImporter()
        let model = makeModel(repository: repository, fileImportClient: importer)
        var draft = SendDraft(contentKind: .text)
        draft.name = "Submitted"
        draft.text = "synthetic text"
        model.updateDraft(draft)
        let picker = Task { await model.pickFileSend() }
        await importer.waitForStart()
        let save = Task { await model.saveDraft() }
        await repository.waitForSaveStart()
        await repository.finishSave(with: [summary("created")])
        await save.value
        importer.finish()
        await picker.value
        #expect(model.state.draft == nil)
        #expect(model.state.summaries.map(\.id.rawValue) == ["created"])
    }

    @Test
    func dismissOrNewIntentInvalidatesAnOutstandingEditResult() async {
        for startNew in [false, true] {
            let repository = TestSendRepository(summaries: [], blocksEdit: true)
            let model = makeModel(repository: repository)
            let edit = Task { await model.editSend(SendID(rawValue: "old")) }
            await repository.waitForEditStart()
            if startNew { model.beginNewTextSend() }
            else { model.dismissDraft() }
            var late = SendDraft(contentKind: .file)
            late.name = "Obsolete edit"
            late.editingID = SendID(rawValue: "old")
            await repository.finishEdit(with: late)
            await edit.value
            if startNew {
                #expect(model.state.draft?.contentKind == .text)
                #expect(model.state.draft?.editingID == nil)
            } else { #expect(model.state.draft == nil) }
        }
    }

    private func makeModel(
        repository: TestSendRepository,
        checkSessionAccess: @escaping @Sendable () throws -> Void = {},
        fileImportClient: (any FileImportClient)? = nil
    ) -> SendModel {
        SendModel(
            repository: repository,
            fileImportClient: fileImportClient ?? SendMockFileImportClient(),
            pasteboardClient: MockPasteboard(),
            checkSessionAccess: checkSessionAccess,
            sleep: { _ in }
        )
    }

    private func summary(_ id: String, canOpen: Bool = true) -> SendSummary {
        SendSummary(
            id: SendID(rawValue: id), name: id, contentKind: .text, isDisabled: false,
            expirationDate: nil, deletionDate: Date(timeIntervalSince1970: 1_700_000_000), canOpen: canOpen
        )
    }
}

@MainActor
private final class GatedSendFileImporter: FileImportClient {
    private var completion: CheckedContinuation<(any ImportedFile)?, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?

    func pickFile() async throws -> (any ImportedFile)? {
        await withCheckedContinuation { continuation in
            completion = continuation
            startWaiter?.resume()
            startWaiter = nil
        }
    }

    func waitForStart() async {
        if completion != nil { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func finish() {
        completion?.resume(returning: NeverOpenedSendFile())
        completion = nil
    }
}

private struct NeverOpenedSendFile: ImportedFile {
    let fileName = "synthetic.txt"
    func withSecurityScopedAccess<Value: Sendable>(_ operation: @Sendable (URL) async throws -> Value) async throws -> Value {
        throw FileImportClientError.failed // A stale picker result must never reach crypto/access.
    }
}

private actor TestSendRepository: Domain.SendRepository {
    private var summaries: [SendSummary]
    private let blocksSave: Bool
    private let blocksEdit: Bool
    private var saveCalls = 0
    private var saveStarted = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var saveWaiter: CheckedContinuation<[SendSummary], Error>?
    private var editWaiter: CheckedContinuation<SendDraft, Never>?
    private var editStartWaiter: CheckedContinuation<Void, Never>?

    init(summaries: [SendSummary], blocksSave: Bool = false, blocksEdit: Bool = false) {
        self.summaries = summaries
        self.blocksSave = blocksSave
        self.blocksEdit = blocksEdit
    }

    func load() async throws -> [SendSummary] { summaries }

    func details(for id: SendID) async throws -> SendDetails {
        SendDetails(
            id: id, name: id.rawValue, contentKind: .text, notes: nil, fileName: nil,
            textHidden: false, accessCount: 0, maxAccessCount: nil, hasPassword: false,
            hidesEmail: false, isDisabled: false, expirationDate: nil,
            deletionDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func editDraft(for id: SendID) async throws -> SendDraft {
        if blocksEdit {
            return await withCheckedContinuation { continuation in
                editWaiter = continuation
                editStartWaiter?.resume()
                editStartWaiter = nil
            }
        }
        return SendDraft(contentKind: .text)
    }

    func waitForEditStart() async {
        if editWaiter != nil { return }
        await withCheckedContinuation { editStartWaiter = $0 }
    }

    func finishEdit(with draft: SendDraft) {
        editWaiter?.resume(returning: draft)
        editWaiter = nil
    }

    func save(_ draft: SendDraft, file: (any ImportedFile)?) async throws -> [SendSummary] {
        saveCalls += 1
        if blocksSave {
            return try await withCheckedThrowingContinuation { continuation in
                saveWaiter = continuation
                saveStarted = true
                startWaiter?.resume()
                startWaiter = nil
            }
        }
        return summaries
    }

    func delete(id: SendID) async throws -> [SendSummary] {
        summaries.removeAll { $0.id == id }
        return summaries
    }

    func shareLink(for id: SendID) async throws -> URL {
        URL(string: "https://vault.example.com/#/send/\(id.rawValue)")!
    }

    func lock() async { summaries.removeAll() }

    func waitForSaveStart() async {
        guard !saveStarted else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func finishSave(with newSummaries: [SendSummary]) {
        summaries = newSummaries
        saveWaiter?.resume(returning: newSummaries)
        saveWaiter = nil
    }

    func finishSave(throwing error: SendRepositoryError) {
        saveWaiter?.resume(throwing: error)
        saveWaiter = nil
    }

    func finishAuthorizationFailure() {
        saveWaiter?.resume(throwing: SessionAuthorizationError.refreshRecoveryRequired)
        saveWaiter = nil
    }

    func saveCallCount() -> Int { saveCalls }
}
