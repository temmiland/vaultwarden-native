import Domain
import Foundation
import SharedUI

/// Presentation-level filtering for the active vault list. Kept independent of SDK and storage
/// details so the legacy screen can migrate without owning duplicate filter semantics.
public enum VaultFilter: Hashable {
    case allItems
    case favorites
    case folder(FolderID?) // nil == "no folder"
    case type(VaultItemKind)
    case collection(CollectionID)

    public var title: String {
        switch self {
        case .allItems: "All Items"
        case .favorites: "Favorites"
        case let .folder(id): id == nil ? "No Folder" : ""
        case let .type(type): type.displayName + "s"
        case .collection: ""
        }
    }

    public func matches(_ item: VaultItemSummary) -> Bool {
        switch self {
        case .allItems:
            true
        case .favorites:
            item.isFavorite
        case let .folder(id):
            item.folderID == id
        case let .type(type):
            item.kind == type
        case let .collection(id):
            item.collectionIDs.contains(id)
        }
    }
}
