import Domain
import Foundation

struct SendState {
    var isLoading = false
    var isSaving = false
    var isUploadingFile = false
    var isDeleting = false
    var errorMessage: String?
    var detailErrorMessage: String?
    var linkErrorMessage: String?
    var summaries: [SendSummary] = []
    var selectedSendID: SendID?
    var selectedDetails: SendDetails?
    var draft: SendDraft?
    var pendingDeleteID: SendID?
    var copyFeedbackID: UUID?

    var visibleSummaries: [SendSummary] {
        summaries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
