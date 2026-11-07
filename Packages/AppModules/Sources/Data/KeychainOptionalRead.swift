import Foundation
import SecurityStorage

/// Data-internal read convenience: only an absent item maps to nil. Interaction, entitlement,
/// decoding and OS failures retain their classified errors; presentation cannot use this helper.
extension SecurityStorage.KeychainStoring {
    func get(_ account: String) throws -> Data? {
        do {
            return try read(account)
        } catch SecurityStorage.KeychainStoreError.notFound {
            return nil
        }
    }
}
