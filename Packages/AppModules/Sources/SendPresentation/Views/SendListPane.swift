import Domain
import SharedUI
import SwiftUI

struct SendListPane: View {
    let model: SendModel

    var body: some View {
        let items = model.state.visibleSummaries
        List(selection: selection) {
            if items.isEmpty, !model.state.isLoading {
                ContentUnavailableView(
                    "No Sends",
                    systemImage: "paperplane",
                    description: Text("Use the toolbar to create a text or file Send.")
                )
            } else {
                ForEach(items) { summary in
                    SendRow(summary: summary)
                        .tag(summary.id)
                        .contextMenu {
                            Button("Edit") { Task { await model.editSend(summary.id) } }
                                .disabled(!summary.canOpen)
                            Button("Copy Link") { Task { await model.copyLink(for: summary.id) } }
                                .disabled(!summary.canOpen)
                            Button("Delete", role: .destructive) { model.requestDelete(summary.id) }
                        }
                }
            }
        }
        .navigationTitle("Send")
        .platformMinSize(width: 280)
    }

    private var selection: Binding<SendID?> {
        Binding(get: { model.state.selectedSendID }, set: { model.select($0) })
    }
}

private struct SendRow: View {
    let summary: SendSummary

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: summary.contentKind == .file ? "doc" : "doc.text")
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.name)
                    .font(.body)
                    .strikethrough(summary.isDisabled)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !summary.canOpen {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("This Send couldn't be decrypted.")
            } else if summary.isDisabled {
                Text("Disabled")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.2), in: Capsule())
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let expirationDate = summary.expirationDate {
            parts.append("Expires \(expirationDate.formatted(date: .abbreviated, time: .shortened))")
        }
        parts.append("Deletes \(summary.deletionDate.formatted(date: .abbreviated, time: .shortened))")
        return parts.joined(separator: " · ")
    }
}
