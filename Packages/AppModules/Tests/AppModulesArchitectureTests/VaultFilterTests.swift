import Domain
@testable import VaultPresentation
import XCTest

final class VaultFilterTests: XCTestCase {
    func testFiltersByFavoriteFolderTypeAndCollection() {
        let collection = CollectionID(rawValue: "work")
        let folder = FolderID(rawValue: "personal")
        let login = VaultItemSummary(
            id: CipherID(rawValue: "login"), kind: .login, name: "Mail", subtitle: nil,
            isFavorite: true, isEditable: true, folderID: folder, collectionIDs: [collection]
        )
        let note = VaultItemSummary(
            id: CipherID(rawValue: "note"), kind: .secureNote, name: "Note", subtitle: nil,
            isFavorite: false, isEditable: true
        )

        XCTAssertTrue(VaultFilter.favorites.matches(login))
        XCTAssertFalse(VaultFilter.favorites.matches(note))
        XCTAssertTrue(VaultFilter.folder(folder).matches(login))
        XCTAssertTrue(VaultFilter.folder(nil).matches(note))
        XCTAssertTrue(VaultFilter.type(.login).matches(login))
        XCTAssertTrue(VaultFilter.collection(collection).matches(login))
        XCTAssertFalse(VaultFilter.collection(collection).matches(note))
        XCTAssertTrue(VaultFilter.allItems.matches(note))
    }

    func testTitlesRemainStableForNamedFilters() {
        XCTAssertEqual(VaultFilter.allItems.title, "All Items")
        XCTAssertEqual(VaultFilter.favorites.title, "Favorites")
        XCTAssertEqual(VaultFilter.folder(nil).title, "No Folder")
        XCTAssertEqual(VaultFilter.type(.login).title, "Logins")
    }
}
