import Foundation

/// Serialization boundary for the encrypted AutoFill projection. Implementations may bridge the
/// current contract to a versioned on-disk format while keeping SDK wire types out of callers.
public protocol AutoFillProjectionEncoding: Sendable {
    func encode(_ envelope: AutoFillCacheEnvelope) throws -> Foundation.Data
    func decode(_ data: Foundation.Data) throws -> AutoFillCacheEnvelope
}
