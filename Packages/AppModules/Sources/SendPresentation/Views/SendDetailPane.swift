import Domain
import SwiftUI

struct SendDetailPane: View {
    let model: SendModel

    var body: some View {
        if let id = model.state.selectedSendID,
           let details = model.state.selectedDetails,
           details.id == id {
            detail(for: details)
        } else if model.state.selectedSendID != nil {
            ProgressView("Opening Send…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView("Select a Send", systemImage: "paperplane")
        }
    }

    private func detail(for details: SendDetails) -> some View {
        Form {
            Section("Details") {
                LabeledContent("Name", value: details.name)
                LabeledContent("Type", value: details.contentKind == .file ? "File" : "Text")
                if let notes = details.notes, !notes.isEmpty {
                    LabeledContent("Notes", value: notes)
                }
                if details.contentKind == .file, let fileName = details.fileName {
                    LabeledContent("File", value: fileName)
                }
                if details.contentKind == .text, details.textHidden {
                    LabeledContent("Text", value: "Hidden by default")
                }
            }

            Section("Access") {
                LabeledContent("Accessed") {
                    if let maxAccessCount = details.maxAccessCount {
                        Text("\(details.accessCount) / \(maxAccessCount)")
                    } else {
                        Text("\(details.accessCount)")
                    }
                }
                LabeledContent("Password Protected", value: details.hasPassword ? "Yes" : "No")
                LabeledContent("Hide My Email", value: details.hidesEmail ? "Yes" : "No")
                LabeledContent("Status", value: details.isDisabled ? "Disabled" : "Active")
            }

            Section("Dates") {
                LabeledContent("Deletes", value: details.deletionDate.formatted(date: .abbreviated, time: .shortened))
                if let expirationDate = details.expirationDate {
                    LabeledContent("Expires", value: expirationDate.formatted(date: .abbreviated, time: .shortened))
                }
            }

            Section {
                Button { Task { await model.copyLink(for: details.id) } } label: {
                    Label("Copy Link", systemImage: "link")
                }
                Button { Task { await model.editSend(details.id) } } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) { model.requestDelete(details.id) } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(details.name)
        .overlay(alignment: .bottom) {
            if model.state.copyFeedbackID != nil {
                Text("Link copied")
                    .font(.caption)
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
    }
}
