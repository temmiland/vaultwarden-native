import AuthenticationServices
import Domain
import Foundation

public enum SystemCredentialIdentityStoreError: Error, Sendable, Equatable {
    case disabled, incrementalUpdatesUnavailable, invalidPasskeyIdentity, invalidPasswordIdentity
}

/// The sole AuthenticationServices adapter for the target architecture. Domain/Data hand it
/// metadata-only descriptors; this type is responsible for turning those into system objects and
/// never receives a password, TOTP seed, vault key or passkey private key.
public struct SystemCredentialIdentityStore: CredentialIdentityPublishing, PasskeyIdentityUpdating {
    public init() {}

    public func addPasswordIdentity(_ identity: CredentialIdentityDescriptor) async throws {
        let values = try Self.passwordIdentities(identity)
        let store = ASCredentialIdentityStore.shared
        let state = await store.state()
        try Self.requireIncrementalStore(
            isEnabled: state.isEnabled,
            supportsIncrementalUpdates: state.supportsIncrementalUpdates
        )
        try await store.saveCredentialIdentities(values)
    }

    public func removePasswordIdentity(_ identity: CredentialIdentityDescriptor) async throws {
        let values = try Self.passwordIdentities(identity)
        try await ASCredentialIdentityStore.shared.removeCredentialIdentities(values)
    }

    private static func passwordIdentities(_ identity: CredentialIdentityDescriptor) throws -> [ASCredentialIdentity] {
        guard identity.kind == .password, !identity.recordIdentifier.rawValue.isEmpty,
              !identity.serviceIdentifier.isEmpty, identity.user?.isEmpty == false else {
            throw SystemCredentialIdentityStoreError.invalidPasswordIdentity
        }
        let values = makeSystemIdentities(from: [identity])
        guard values.count == 1 else { throw SystemCredentialIdentityStoreError.invalidPasswordIdentity }
        return values
    }

    public func addPasskeyIdentity(_ identity: CredentialIdentityDescriptor) async throws {
        let identities = try Self.makeIncrementalPasskeyIdentities(from: identity)
        let store = ASCredentialIdentityStore.shared
        let state = await store.state()
        try Self.requireIncrementalStore(
            isEnabled: state.isEnabled,
            supportsIncrementalUpdates: state.supportsIncrementalUpdates
        )
        try await store.saveCredentialIdentities(identities)
    }

    public func removePasskeyIdentity(_ identity: CredentialIdentityDescriptor) async throws {
        let identities = try Self.makeIncrementalPasskeyIdentities(from: identity)
        let store = ASCredentialIdentityStore.shared
        let state = await store.state()
        try Self.requireIncrementalStore(
            isEnabled: state.isEnabled,
            supportsIncrementalUpdates: state.supportsIncrementalUpdates
        )
        try await store.removeCredentialIdentities(identities)
    }

    static func requireIncrementalStore(isEnabled: Bool, supportsIncrementalUpdates: Bool) throws {
        guard isEnabled else { throw SystemCredentialIdentityStoreError.disabled }
        guard supportsIncrementalUpdates else { throw SystemCredentialIdentityStoreError.incrementalUpdatesUnavailable }
    }

    static func makeIncrementalPasskeyIdentities(from identity: CredentialIdentityDescriptor) throws -> [
        ASCredentialIdentity
    ] {
        guard identity.kind == .passkey, !identity.id.isEmpty, !identity.serviceIdentifier.isEmpty,
              !identity.recordIdentifier.rawValue.isEmpty, let credentialID = identity.credentialID,
              !credentialID.isEmpty, identity.userHandle != nil,
              let userName = identity.user ?? identity.label, !userName.isEmpty else {
            throw SystemCredentialIdentityStoreError.invalidPasskeyIdentity
        }
        let identities = makeSystemIdentities(from: [identity])
        guard identities.count == 1 else { throw SystemCredentialIdentityStoreError.invalidPasskeyIdentity }
        return identities
    }

    public func replaceCredentialIdentities(
        _ identities: [CredentialIdentityDescriptor],
        revision _: UInt64
    ) async throws {
        let store = ASCredentialIdentityStore.shared
        guard await store.state().isEnabled else { throw SystemCredentialIdentityStoreError.disabled }

        let systemIdentities = Self.makeSystemIdentities(from: identities)
        if systemIdentities.isEmpty {
            try await store.removeAllCredentialIdentities()
        } else {
            try await store.replaceCredentialIdentities(systemIdentities)
        }
    }

    public func removeAllCredentialIdentities() async throws {
        let store = ASCredentialIdentityStore.shared
        guard await store.state().isEnabled else { throw SystemCredentialIdentityStoreError.disabled }
        try await store.removeAllCredentialIdentities()
    }

    /// Isolated from the OS store call so the cross-platform descriptor contract can be verified
    /// without an enabled extension or a signed App Group entitlement.
    static func makeSystemIdentities(from descriptors: [CredentialIdentityDescriptor]) -> [ASCredentialIdentity] {
        descriptors.compactMap { descriptor in
            switch descriptor.kind {
            case .password:
                guard let user = descriptor.user, !user.isEmpty else { return nil }
                return ASPasswordCredentialIdentity(
                    serviceIdentifier: serviceIdentifier(for: descriptor),
                    user: user,
                    recordIdentifier: descriptor.recordIdentifier.rawValue
                )

            case .oneTimeCode:
                guard #available(iOS 18.0, macOS 15.0, *),
                      let label = descriptor.label, !label.isEmpty
                else { return nil }
                return ASOneTimeCodeCredentialIdentity(
                    serviceIdentifier: serviceIdentifier(for: descriptor),
                    label: label,
                    recordIdentifier: descriptor.recordIdentifier.rawValue
                )

            case .passkey:
                guard let credentialID = descriptor.credentialID,
                      let userHandle = descriptor.userHandle,
                      let userName = descriptor.user ?? descriptor.label,
                      !userName.isEmpty
                else { return nil }
                return ASPasskeyCredentialIdentity(
                    relyingPartyIdentifier: descriptor.serviceIdentifier,
                    userName: userName,
                    credentialID: credentialID,
                    userHandle: userHandle,
                    recordIdentifier: descriptor.recordIdentifier.rawValue
                )
            }
        }
    }

    private static func serviceIdentifier(for descriptor: CredentialIdentityDescriptor) -> ASCredentialServiceIdentifier {
        ASCredentialServiceIdentifier(
            identifier: descriptor.serviceIdentifier,
            type: descriptor.serviceIdentifier.contains("://") ? .URL : .domain
        )
    }
}
