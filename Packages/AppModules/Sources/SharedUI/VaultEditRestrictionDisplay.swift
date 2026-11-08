import Domain

public extension VaultEditRestriction {
    var message: String {
        switch self {
        case .unsupportedKind: "This item type is read-only in this client."
        case .inactiveItem: "Deleted or archived items can't be edited in the active vault."
        case .editDenied: "You don't have permission to edit this item."
        case .secretsHidden: "The editor requires permission to view this item's secrets."
        case .repromptRequired: "This item requires master-password verification. Use an official client to access its secrets or make changes."
        case .attachmentDecryptionFailure: "Some attachments couldn't be decrypted. Sync again before editing this item."
        case .collectionReadOnly: "This item's collection is read-only."
        case .unresolvedCollection: "This item's collection permissions couldn't be resolved. Sync before editing."
        case .unsupportedPayload: "This item contains fields this client can't safely preserve. Use an official client to make changes."
        }
    }
}
