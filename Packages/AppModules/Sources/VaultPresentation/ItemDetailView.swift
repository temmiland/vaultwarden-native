import Domain
import QuickLook
import SharedUI
import SwiftUI

struct ItemDetailView: View {
    let model: VaultModel

    var body: some View {
        if let item = model.state.selectedItem {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(for: item)
                    if item.kind.supportsEditing, let restriction = item.permissions.editRestriction {
                        Label(restriction.message, systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    switch item.payload {
                    case let .login(login):
                        LoginDetailView(model: model, item: item, login: login)
                            .id(item.context)
                    case let .card(card):
                        CardDetailView(card: card)
                    case let .identity(identity):
                        IdentityDetailView(identity: identity)
                    case .secureNote:
                        DetailField(label: "Note", value: item.notes ?? "", isMultiline: true)
                    case let .sshKey(key):
                        SshKeyDetailView(key: key)
                    case .unsupported:
                        Text(
                            item.permissions.editRestriction?.message ?? "This item type is read-only in this client."
                        )
                        .foregroundStyle(.secondary)
                    }
                    if let notes = item.notes, !notes.isEmpty, item.kind != .secureNote {
                        DetailField(label: "Notes", value: notes, isMultiline: true)
                    }
                    Divider()
                    AttachmentsSection(model: model, item: item)
                }
                .padding(24)
            }
            .navigationTitle(item.name)
            .toolbar {
                ToolbarItemGroup {
                    if item.permissions.canEdit {
                        Button("Edit") { model.send(.editItemTapped(item.id)) }
                    }
                    if item.permissions.canDelete {
                        Button("Delete", role: .destructive) { model.send(.deleteItemTapped(item.id)) }
                    }
                }
            }
            .quickLookPreview(model.binding(get: \.previewURL, send: { _ in .previewDismissed }))
            .alert(
                "Delete this attachment?",
                isPresented: Binding(
                    get: { model.state.pendingAttachmentDelete != nil },
                    set: { if !$0 { model.send(.deleteAttachmentCancelled) } }
                )
            ) {
                Button("Cancel", role: .cancel) { model.send(.deleteAttachmentCancelled) }
                Button("Delete", role: .destructive) {
                    Task { await model.perform(.confirmDeleteAttachment) }
                }
            } message: {
                Text("This can't be undone.")
            }
        } else {
            ContentUnavailableView(
                "No Item Selected", systemImage: "lock.doc",
                description: Text("Select an item from the list to see its details.")
            )
        }
    }

    private func header(for item: VaultItemDetail) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind.symbolName)
                .accessibilityHidden(true)
                .font(.title)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text(item.name).font(.title2.bold())
                if let organizationName = item.organizationName {
                    Label(organizationName, systemImage: "person.2.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if item.isFavorite {
                    Label("Favorite", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }
            Spacer()
        }
    }
}

private struct LoginDetailView: View {
    let model: VaultModel
    let item: VaultItemDetail
    let login: VaultLoginDetail
    @State private var isPasswordRevealed = false
    @Environment(\.pasteboardClient) private var pasteboardClient

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let username = login.username, !username.isEmpty {
                DetailField(label: "Username", value: username, copyAction: { pasteboardClient?.copySecret(username) })
            }
            if login.hasPassword {
                HStack {
                    DetailField(
                        label: "Password",
                        value: isPasswordRevealed ? (login.password ?? "••••••••••••") : "••••••••••••",
                        copyAction: login.password.map { password in { pasteboardClient?.copySecret(password) } }
                    )
                    if login.password != nil {
                        Button { isPasswordRevealed.toggle() } label: {
                            Image(systemName: isPasswordRevealed ? "eye.slash" : "eye")
                                .accessibilityLabel(isPasswordRevealed ? "Hide password" : "Show password")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if login.hasTotp { totpField }
            ForEach(Array(login.uris.enumerated()), id: \.offset) { _, uri in
                DetailField(label: "URI", value: uri, copyAction: { pasteboardClient?.copySecret(uri) })
            }
            if login.hasPasskeys { passkeySection }
        }
        .task(id: login.hasTotp ? item.context : nil) {
            guard login.hasTotp else { return }
            while !Task.isCancelled {
                await model.perform(.refreshTotp(item.context))
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
            }
        }
        .task(id: login.hasPasskeys ? item.context : nil) {
            guard login.hasPasskeys else { return }
            await model.perform(.loadPasskeys(item.context))
        }
        .onChange(of: item.permissions.canViewSecrets) { _, _ in isPasswordRevealed = false }
    }

    private var passkeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Passkeys").font(.caption).foregroundStyle(.secondary)
            ForEach(model.state.passkeys(for: item.context)) { passkey in
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.key.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(passkey.relyingPartyName).font(.body)
                        if let userName = passkey.userName, !userName.isEmpty {
                            Text(userName).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    private var totpField: some View {
        let code = model.state.totp(for: item.context)?.code
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Verification Code (TOTP)").font(.caption).foregroundStyle(.secondary)
                Text(formattedTotp(code)).font(.system(.body, design: .monospaced))
            }
            Spacer()
            Button { if let code { pasteboardClient?.copySecret(code) } } label: {
                Image(systemName: "doc.on.doc").accessibilityLabel("Copy verification code")
            }
            .buttonStyle(.plain)
            .disabled(code == nil)
        }
    }

    private func formattedTotp(_ code: String?) -> String {
        guard let code else { return "------" }
        let midpoint = code.index(code.startIndex, offsetBy: code.count / 2)
        return "\(code[..<midpoint]) \(code[midpoint...])"
    }
}

private struct CardDetailView: View {
    let card: VaultCardDetail
    @Environment(\.pasteboardClient) private var pasteboardClient

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let name = card.cardholderName, !name.isEmpty { DetailField(label: "Cardholder Name", value: name) }
            if let number = card.number, !number.isEmpty {
                DetailField(label: "Number", value: number, copyAction: { pasteboardClient?.copySecret(number) })
            }
            if !card.expiration.isEmpty { DetailField(label: "Expiration", value: card.expiration) }
            if let code = card.securityCode, !code.isEmpty {
                DetailField(label: "Security Code", value: code, copyAction: { pasteboardClient?.copySecret(code) })
            }
        }
    }
}

private struct IdentityDetailView: View {
    let identity: VaultIdentityDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !identity.fullName.isEmpty { DetailField(label: "Name", value: identity.fullName) }
            if let username = identity.username, !username.isEmpty { DetailField(label: "Username", value: username) }
            if let email = identity.email, !email.isEmpty { DetailField(label: "Email", value: email) }
            if let phone = identity.phone, !phone.isEmpty { DetailField(label: "Phone", value: phone) }
        }
    }
}

private struct SshKeyDetailView: View {
    let key: VaultSSHKeyDetail
    @Environment(\.pasteboardClient) private var pasteboardClient

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let publicKey = key.publicKey, !publicKey.isEmpty {
                DetailField(
                    label: "Public Key",
                    value: publicKey,
                    isMultiline: true,
                    copyAction: { pasteboardClient?.copySecret(publicKey) }
                )
            }
            DetailField(
                label: "Private Key", value: "•••••••• (hidden)",
                copyAction: key.privateKey.map { privateKey in { pasteboardClient?.copySecret(privateKey) } }
            )
            if let fingerprint = key.fingerprint, !fingerprint.isEmpty { DetailField(
                label: "Fingerprint",
                value: fingerprint
            ) }
        }
    }
}

private struct AttachmentsSection: View {
    let model: VaultModel
    let item: VaultItemDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Attachments").font(.headline)
                Spacer()
                if model.state.isAttachmentBusy { ProgressView().controlSize(.small) }
                if item.permissions.canEdit {
                    Button {
                        Task { await model.perform(.pickAttachment(cipherID: item.id)) }
                    } label: {
                        Label("Add Attachment", systemImage: "paperclip")
                    }
                    .disabled(model.state.isAttachmentBusy)
                }
            }
            if item.attachments.isEmpty {
                Text("No attachments").font(.caption).foregroundStyle(.secondary)
            } else {
                // Missing/duplicate attachment ids remain visible but get no actionable reference.
                ForEach(Array(item.attachments.enumerated()), id: \.offset) { _, attachment in
                    AttachmentRow(model: model, attachment: attachment, canEdit: item.permissions.canEdit)
                }
            }
        }
    }
}

private struct AttachmentRow: View {
    let model: VaultModel
    let attachment: VaultAttachmentSummary
    let canEdit: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "paperclip").accessibilityHidden(true).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName)
                if let sizeName = attachment.sizeName { Text(sizeName).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Button {
                guard let reference = attachment.reference else { return }
                Task { await model.perform(.downloadAttachment(reference)) }
            } label: {
                Image(systemName: "arrow.down.circle").accessibilityLabel("Download attachment")
            }
            .buttonStyle(.plain)
            .disabled(model.state.isAttachmentBusy || !attachment.canDownload)
            .help("Download and preview")
            if canEdit {
                Button {
                    guard let reference = attachment.reference else { return }
                    model.send(.deleteAttachmentTapped(reference))
                } label: {
                    Image(systemName: "trash").accessibilityLabel("Delete attachment")
                }
                .buttonStyle(.plain)
                .disabled(model.state.isAttachmentBusy || attachment.reference == nil)
            }
        }
        .padding(.vertical, 2)
    }
}

struct DetailField: View {
    let label: String
    let value: String
    var isMultiline = false
    var copyAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).textSelection(.enabled).lineLimit(isMultiline ? nil : 1)
            }
            Spacer()
            if let copyAction {
                Button(action: copyAction) {
                    Image(systemName: "doc.on.doc").accessibilityLabel("Copy \(label)")
                }
                .buttonStyle(.plain)
            }
        }
    }
}
