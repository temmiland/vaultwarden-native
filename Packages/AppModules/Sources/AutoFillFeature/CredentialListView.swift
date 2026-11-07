import AutoFillContract
import SwiftUI

/// The picker shown whenever the system needs the user to choose among matches (can't silently
/// autofill when there's more than one, or none). Deliberately minimal - this runs inside the
/// extension's own small window, not the main app.
@MainActor
public struct CredentialListView: View {
    let matches: [AutoFillLoginSummary]
    var warningMessage: String? = nil
    /// Differs per request type - "no password for this site" and "no verification code for this
    /// site" are very different things to tell someone staring at an empty list.
    var emptyMessage: String = "No saved login matches this site."
    var emptyTitle: String = "No Matches"
    let onSelect: (AutoFillLoginSummary) -> Void
    let onCancel: () -> Void

    @State private var searchText = ""

    public init(
        matches: [AutoFillLoginSummary],
        warningMessage: String? = nil,
        emptyMessage: String = "No saved login matches this site.",
        emptyTitle: String = "No Matches",
        onSelect: @escaping (AutoFillLoginSummary) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.matches = matches
        self.warningMessage = warningMessage
        self.emptyMessage = emptyMessage
        self.emptyTitle = emptyTitle
        self.onSelect = onSelect
        self.onCancel = onCancel
    }

    /// Identifier-free manual browsing may contain the whole eligible vault. Concrete sites do
    /// not get a permissive no-match fallback.
    private var visibleMatches: [AutoFillLoginSummary] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return matches }
        return matches.filter { match in
            match.name.lowercased().contains(query)
                || (match.username?.lowercased().contains(query) ?? false)
                || match.uris.contains { $0.value.lowercased().contains(query) }
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Vaultwarden").font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding()

            if let warningMessage {
                Label(warningMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            if !matches.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField("Search", text: $searchText)
                        .textFieldStyle(.plain)
                    #if os(iOS)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    #endif
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            if matches.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "lock.slash",
                    description: Text(warningMessage ?? emptyMessage)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleMatches.isEmpty {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("Nothing in your vault matches “\(searchText)”.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(visibleMatches, id: \.id) { match in
                    Button {
                        onSelect(match)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: match.hasTOTP ? "key.fill" : "lock.fill")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(match.name).font(.body)
                                if let username = match.username, !username.isEmpty {
                                    Text(username).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        #if os(macOS)
        .frame(width: 380, height: 320)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }
}
