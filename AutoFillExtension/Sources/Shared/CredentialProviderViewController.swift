import AuthenticationServices
import AutoFillContract
import AutoFillData
import AutoFillFeature
import Foundation
import SwiftUI
#if os(iOS)
    import UIKit
    private typealias PlatformHostingController<Content: View> = UIHostingController<Content>
#else
    import AppKit
    private typealias PlatformHostingController<Content: View> = NSHostingController<Content>
#endif

/// Password AutoFill credential provider, shared verbatim between the macOS and iOS/iPadOS
/// extension targets (see `project.yml` - both point their sources at this file). Offline for
/// everything it reads: the decrypted user key, account metadata and the still-encrypted vault
/// cache were all written by the main app - see `AutoFillVaultStore`. Covers password + TOTP display
/// (interactive list) and passkey assertion (via the SDK's Fido2 engine,
/// `AutoFillFido2Bridge.swift`).
///
/// Saving a *new* passkey is the one thing that writes: it needs the tokens the app mirrors into
/// the shared Keychain group. All reads AND writes stop after shared capability revocation, even
/// with a retained SDK client. See `AutoFillPasskeyRegistration`. Saving new *passwords*
/// still isn't implemented - the system has no equivalent registration entry point for them.
final class CredentialProviderViewController: ASCredentialProviderViewController {
    /// Production always uses the validated shared store. Tests inject a synthetic loader rather
    /// than accessing the owner's Keychain/App Group or invoking a system completion callback.
    var sessionLoader: @Sendable () async throws -> ExtensionVaultSession = {
        try await AutoFillVaultStore.makeUnlockedSession()
    }

    private var currentMatches: [AutoFillLoginSummary] = []
    private var listFailureMessage: String?
    private var listWarningMessage: String?
    private let lifecycle = ExtensionRequestLifecycle()
    private lazy var completion = AutoFillRequestCompletion(lifecycle: lifecycle)
    private var activeSession: ExtensionVaultSession?
    private var requestTask: Task<Void, Never>?
    private var sessionMonitor: Task<Void, Never>?

    deinit { requestTask?.cancel(); sessionMonitor?.cancel(); activeSession?.revoke() }

    private func beginInvocation() -> UUID {
        requestTask?.cancel()
        sessionMonitor?.cancel()
        activeSession?.revoke()
        activeSession = nil
        currentMatches = []
        listFailureMessage = nil
        listWarningMessage = nil
        removeHostedContent()
        return lifecycle.begin()
    }

    private func startInvocation(
        _ operation: @escaping @MainActor (CredentialProviderViewController, UUID) async -> Void
    ) {
        let id = beginInvocation()
        requestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await operation(self, id)
        }
    }

    private func runAction(
        _ id: UUID,
        _ operation: @escaping @MainActor (CredentialProviderViewController) async -> Void
    ) {
        guard lifecycle.beginAction(id) else { return }
        requestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await operation(self)
            lifecycle.endAction(id)
        }
    }

    private func requireInvocation(_ id: UUID) throws {
        try Task.checkCancellation()
        guard lifecycle.isActive(id) else { throw CancellationError() }
    }

    private func session(for id: UUID) async throws -> ExtensionVaultSession {
        try requireInvocation(id)
        if let activeSession {
            try activeSession.checkAccess()
            return activeSession
        }
        let built = try await sessionLoader()
        do { try requireInvocation(id) }
        catch { built.revoke(); throw error }
        activeSession = built
        sessionMonitor = Task { @MainActor [weak self, built] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
                guard let self, lifecycle.isActive(id) else { return }
                do { try built.checkAccess() }
                catch { cancel(.userInteractionRequired, invocationID: id); return }
            }
        }
        return built
    }

    private func removeHostedContent() {
        for child in children {
            #if os(iOS)
                child.willMove(toParent: nil)
            #endif
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
    }

    private func retireInvocation(cancelTask: Bool) {
        activeSession?.revoke()
        activeSession = nil
        currentMatches = []
        listFailureMessage = nil
        listWarningMessage = nil
        sessionMonitor?.cancel()
        sessionMonitor = nil
        if cancelTask { requestTask?.cancel() }
        requestTask = nil
        removeHostedContent()
    }

    private func finish(
        _ credential: AutoFillCompletion,
        session: ExtensionVaultSession,
        invocationID: UUID,
        requireOriginalCache: Bool = true
    ) throws {
        try completion.complete(
            credential,
            invocationID: invocationID,
            checkAccess: {
                if requireOriginalCache { _ = try session.readCache() }
                else { try session.checkAccess() } // confirmed registration advances its own cache
            },
            context: SystemAutoFillExtensionContext(extensionContext),
            retire: { self.retireInvocation(cancelTask: false) }
        )
    }

    // MARK: - Password autofill

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        startInvocation { provider, id in await provider.loadAndShowMatches(for: serviceIdentifiers, invocationID: id) }
    }

    @MainActor
    private func loadAndShowMatches(for serviceIdentifiers: [ASCredentialServiceIdentifier], invocationID: UUID) async {
        guard lifecycle.isActive(invocationID) else { return }
        listFailureMessage = nil
        listWarningMessage = nil
        AutoFillLog.logger.debug(
            "prepareCredentialList(password): \(serviceIdentifiers.count, privacy: .public) identifiers"
        )
        do {
            let session = try await session(for: invocationID)
            let result = try await session.credentials.logins(matching: serviceIdentifiers.map(\.identifier))
            try requireInvocation(invocationID)
            currentMatches = result.items
            listWarningMessage = result.warningMessage
            AutoFillLog.logger.debug(
                "prepareCredentialList(password): showing \(self.currentMatches.count, privacy: .public)"
            )
        } catch {
            AutoFillLog.logger.debug("prepareCredentialList(password) FAILED: [redacted error]")
            guard lifecycle.isActive(invocationID), !Task.isCancelled else { return }
            currentMatches = []
            listFailureMessage = AutoFillRequestErrorPolicy.listMessage(for: error)
        }
        showList(invocationID: invocationID)
    }

    private func showList(invocationID: UUID) {
        guard lifecycle.isActive(invocationID) else { return }
        embed(PlatformHostingController(rootView: CredentialListView(
            matches: currentMatches,
            warningMessage: listWarningMessage,
            emptyMessage: listFailureMessage ?? "No saved login matches this site.",
            emptyTitle: listFailureMessage == nil && listWarningMessage == nil ? "No Matches" : "Vault Unavailable",
            onSelect: { [weak self] match in self?.runAction(invocationID) { await $0.complete(
                with: match,
                invocationID: invocationID
            ) } },
            onCancel: { [weak self] in self?.cancel(.userCanceled, invocationID: invocationID) }
        )))
    }

    /// Adds a hosting controller's view as a full-bleed child, pinned via Auto Layout (identical
    /// anchor API on `NSView`/`UIView`, unlike the `frame`/`autoresizingMask` route which diverges
    /// - `NSView.AutoresizingMask` and `UIView.AutoresizingMask` don't share case names).
    private func embed<Content: View>(_ hosting: PlatformHostingController<Content>) {
        // Replace, don't stack. Several paths swap the visible content more than once in a single
        // invocation (the passkey save flow re-rendering with an error), and each `addChild`
        // without a matching removal leaves the previous view
        // sitting underneath - visible around the edges, and still eating hit tests.
        removeHostedContent()

        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        #if os(iOS)
            hosting.didMove(toParent: self)
        #endif
    }

    @MainActor
    private func complete(with match: AutoFillLoginSummary, invocationID: UUID) async {
        do {
            // Never fulfil from a retained picker snapshot after the cache changed permissions.
            let session = try await session(for: invocationID)
            let current = try await session.credentials.password(cipherId: match.cipherId)
            try finish(.password(current), session: session, invocationID: invocationID)
        } catch {
            cancel(
                AutoFillRequestErrorPolicy.cancellation(for: error, route: .identifiedCredential),
                invocationID: invocationID
            )
        }
    }

    // MARK: - No-interaction fast path (Quick Type Bar)

    override func provideCredentialWithoutUserInteraction(for credentialRequest: ASCredentialRequest) {
        if #available(macOS 14.0, iOS 17.0, *), credentialRequest is ASPasskeyCredentialRequest {
            // Asserting a passkey runs `checkUser`, which puts up a Face ID / Touch ID prompt - and
            // this method is documented as running with no view controller on screen ("Do not
            // attempt or expect to show any user interface in this method"). Asking for UI here
            // sends the request back to us via `prepareInterfaceToProvideCredential(for:)`, where
            // the biometric prompt actually has somewhere to appear.
            AutoFillLog.logger.debug("provideWithoutInteraction: passkey needs UI for user verification")
            cancel(
                credentialRequest.type == .passkeyAssertion ? .userInteractionRequired : .failed,
                invocationID: beginInvocation()
            )
            return
        }
        // Legacy identities may remain in the OS index after an app update. They carry no
        // trustworthy requesting URL, so do not fulfil them; a scoped picker can still be used.
        cancel(.credentialIdentityNotFound, invocationID: beginInvocation())
    }

    // MARK: - Fulfilling one specific, already-chosen credential

    /// Called when the user taps a QuickType suggestion (or any pre-identified credential) and we
    /// previously answered `provideCredentialWithoutUserInteraction` with `.userInteractionRequired`.
    /// The system relaunches us *with* UI and expects us to finish the job for that one item.
    ///
    /// Not overriding this is a silent blank screen - the base implementation does nothing at all,
    /// so the extension just sits there showing an empty view.
    override func prepareInterfaceToProvideCredential(for credentialRequest: ASCredentialRequest) {
        startInvocation { provider, id in await provider.fulfil(credentialRequest, invocationID: id) }
    }

    @MainActor
    private func fulfil(_ credentialRequest: ASCredentialRequest, invocationID: UUID) async {
        if #available(macOS 14.0, iOS 17.0, *), let passkeyRequest = credentialRequest as? ASPasskeyCredentialRequest {
            guard credentialRequest.type == .passkeyAssertion else { cancel(.failed, invocationID: invocationID); return }
            await handlePasskeyRequest(passkeyRequest, invocationID: invocationID)
            return
        }
        // The identity can predate the safe publication policy and lacks the actual request URL.
        cancel(.credentialIdentityNotFound, invocationID: invocationID)
    }

    // MARK: - One-time codes (TOTP)

    @available(macOS 15.0, iOS 18.0, *)
    override func prepareOneTimeCodeCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        startInvocation { provider, id in await provider.loadAndShowOneTimeCodes(
            for: serviceIdentifiers,
            invocationID: id
        ) }
    }

    @available(macOS 15.0, iOS 18.0, *)
    @MainActor
    private func loadAndShowOneTimeCodes(for serviceIdentifiers: [ASCredentialServiceIdentifier], invocationID: UUID) async {
        guard lifecycle.isActive(invocationID) else { return }
        listFailureMessage = nil
        listWarningMessage = nil
        AutoFillLog.logger.debug(
            "prepareOneTimeCodeCredentialList: \(serviceIdentifiers.count, privacy: .public) identifiers"
        )
        do {
            let session = try await session(for: invocationID)
            let result = try await session.credentials.logins(
                matching: serviceIdentifiers.map(\.identifier),
                requiringTOTP: true
            )
            try requireInvocation(invocationID)
            currentMatches = result.items
            listWarningMessage = result.warningMessage
            AutoFillLog.logger.debug(
                "prepareOneTimeCodeCredentialList: showing \(self.currentMatches.count, privacy: .public)"
            )
        } catch {
            AutoFillLog.logger.debug("prepareOneTimeCodeCredentialList failed: [redacted error]")
            guard lifecycle.isActive(invocationID), !Task.isCancelled else { return }
            currentMatches = []
            listFailureMessage = AutoFillRequestErrorPolicy.listMessage(for: error)
        }
        guard lifecycle.isActive(invocationID) else { return }
        embed(PlatformHostingController(rootView: CredentialListView(
            matches: currentMatches,
            warningMessage: listWarningMessage,
            emptyMessage: listFailureMessage ?? "No matching item has a verification code.",
            emptyTitle: listFailureMessage == nil && listWarningMessage == nil ? "No Matches" : "Vault Unavailable",
            onSelect: { [weak self] match in self?.runAction(invocationID) { await $0.completeOneTimeCode(
                with: match,
                invocationID: invocationID
            ) } },
            onCancel: { [weak self] in self?.cancel(.userCanceled, invocationID: invocationID) }
        )))
    }

    /// Generates the code at selection time rather than when the list was built - a TOTP shown a
    /// minute ago would already be stale by the time the user taps it.
    @available(macOS 15.0, iOS 18.0, *)
    @MainActor
    private func completeOneTimeCode(with match: AutoFillLoginSummary, invocationID: UUID) async {
        do {
            let session = try await session(for: invocationID)
            let code = try await session.credentials.oneTimeCode(cipherId: match.cipherId)
            try finish(.oneTimeCode(code), session: session, invocationID: invocationID)
        } catch {
            cancel(
                AutoFillRequestErrorPolicy.cancellation(for: error, route: .identifiedCredential),
                invocationID: invocationID
            )
        }
    }

    // MARK: - Passkeys

    @available(macOS 14.0, iOS 17.0, *)
    override func prepareCredentialList(
        for serviceIdentifiers: [ASCredentialServiceIdentifier],
        requestParameters: ASPasskeyCredentialRequestParameters
    ) {
        startInvocation { provider, id in await provider.preparePasskeyList(
            rpId: requestParameters.relyingPartyIdentifier,
            requestParameters: requestParameters,
            invocationID: id
        ) }
    }

    @available(macOS 14.0, iOS 17.0, *)
    @MainActor
    private func preparePasskeyList(
        rpId: String,
        requestParameters: ASPasskeyCredentialRequestParameters,
        invocationID: UUID
    ) async {
        guard lifecycle.isActive(invocationID) else { return }
        listFailureMessage = nil
        listWarningMessage = nil
        do {
            let session = try await session(for: invocationID)
            let result = try await session.passkeys.matching(
                relyingPartyIdentifier: rpId,
                allowedCredentials: requestParameters.allowedCredentials
            )
            try requireInvocation(invocationID)
            currentMatches = result.items
            listWarningMessage = result.warningMessage
        } catch {
            guard lifecycle.isActive(invocationID), !Task.isCancelled else { return }
            currentMatches = []
            listFailureMessage = AutoFillRequestErrorPolicy.listMessage(for: error)
        }
        showPasskeyList(requestParameters: requestParameters, invocationID: invocationID)
    }

    @available(macOS 14.0, iOS 17.0, *)
    private func showPasskeyList(requestParameters: ASPasskeyCredentialRequestParameters, invocationID: UUID) {
        guard lifecycle.isActive(invocationID) else { return }
        embed(PlatformHostingController(rootView: CredentialListView(
            matches: currentMatches,
            warningMessage: listWarningMessage,
            emptyMessage: listFailureMessage ?? "No saved passkey matches this site.",
            emptyTitle: listFailureMessage == nil && listWarningMessage == nil ? "No Matches" : "Vault Unavailable",
            onSelect: { [weak self] match in
                self?.runAction(invocationID) { provider in
                    await provider.assertPasskey(
                        for: match,
                        clientDataHash: requestParameters.clientDataHash,
                        relyingPartyIdentifier: requestParameters.relyingPartyIdentifier,
                        allowedCredentials: requestParameters.allowedCredentials,
                        userVerification: requestParameters.userVerificationPreference.rawValue,
                        invocationID: invocationID
                    )
                }
            },
            onCancel: { [weak self] in self?.cancel(.userCanceled, invocationID: invocationID) }
        )))
    }

    // MARK: - Saving a new passkey

    /// Saving a *new* passkey into the vault.
    ///
    /// This override has to exist even when it can't proceed: `ProvidesPasskeys` in the extension's
    /// `ASCredentialProviderExtensionCapabilities` is a single flag covering both using and
    /// creating passkeys, so the system offers Vaultwarden as a place to save one regardless.
    /// Without an override, the base class does nothing at all and the user gets an empty sheet
    /// with a spinner that never finishes.
    @available(macOS 14.0, iOS 17.0, *)
    override func prepareInterface(forPasskeyRegistration registrationRequest: ASCredentialRequest) {
        let id = beginInvocation()
        guard let request = registrationRequest as? ASPasskeyCredentialRequest,
              let identity = request.credentialIdentity as? ASPasskeyCredentialIdentity
        else {
            AutoFillLog.logger.debug("prepareInterface(forPasskeyRegistration:): unexpected request shape")
            cancel(.failed, invocationID: id)
            return
        }
        requestTask = Task { await startPasskeyRegistration(request: request, identity: identity, invocationID: id) }
    }

    @available(macOS 14.0, iOS 17.0, *)
    @MainActor
    private func startPasskeyRegistration(
        request: ASPasskeyCredentialRequest,
        identity: ASPasskeyCredentialIdentity,
        invocationID: UUID
    ) async {
        AutoFillLog.logger.debug("passkey registration: rpId \(identity.relyingPartyIdentifier)")

        do {
            let session = try await session(for: invocationID)
            let result = try await session.credentials.logins(matching: [identity.relyingPartyIdentifier])
            try requireInvocation(invocationID)
            listWarningMessage = result.warningMessage
            showPasskeyRegistration(
                request: request,
                identity: identity,
                existing: result.items,
                error: nil,
                invocationID: invocationID
            )
        } catch {
            cancel(
                AutoFillRequestErrorPolicy.cancellation(for: error, route: .registrationStartup),
                invocationID: invocationID
            )
        }
    }

    @available(macOS 14.0, iOS 17.0, *)
    @MainActor
    private func showPasskeyRegistration(
        request: ASPasskeyCredentialRequest,
        identity: ASPasskeyCredentialIdentity,
        existing: [AutoFillLoginSummary],
        error: String?,
        isSaving: Bool = false,
        canSave: Bool = true,
        invocationID: UUID
    ) {
        guard lifecycle.isActive(invocationID) else { return }
        embed(PlatformHostingController(rootView: PasskeyRegistrationView(
            relyingPartyIdentifier: identity.relyingPartyIdentifier,
            userName: identity.userName,
            existingItems: existing,
            warningMessage: listWarningMessage,
            isSaving: isSaving,
            canSave: canSave,
            errorMessage: error,
            onSaveToExisting: { [weak self] match in
                let cipherId = match.cipherId
                self?.runAction(invocationID) { provider in
                    await provider.completePasskeyRegistration(
                        request: request, identity: identity, existing: existing, targetCipherId: cipherId,
                        invocationID: invocationID
                    )
                }
            },
            onSaveAsNewItem: { [weak self] in
                self?.runAction(invocationID) { provider in
                    await provider.completePasskeyRegistration(
                        request: request, identity: identity, existing: existing, targetCipherId: nil,
                        invocationID: invocationID
                    )
                }
            },
            onCancel: { [weak self] in self?.cancel(.userCanceled, invocationID: invocationID) }
        )))
    }

    /// `targetCipherId == nil` means "save into a new item".
    @available(macOS 14.0, iOS 17.0, *)
    @MainActor
    private func completePasskeyRegistration(
        request: ASPasskeyCredentialRequest,
        identity: ASPasskeyCredentialIdentity,
        existing: [AutoFillLoginSummary],
        targetCipherId: String?,
        invocationID: UUID
    ) async {
        showPasskeyRegistration(
            request: request,
            identity: identity,
            existing: existing,
            error: nil,
            isSaving: true,
            invocationID: invocationID
        )

        do {
            let session = try await session(for: invocationID)
            let target = try await resolveRegistrationTarget(
                cipherId: targetCipherId,
                identity: identity,
                session: session
            )
            let credential = try await AutoFillPasskeyRegistration.register(
                request: request, identity: identity, target: target, session: session
            )
            try finish(credential, session: session, invocationID: invocationID, requireOriginalCache: false)
        } catch {
            guard lifecycle.isActive(invocationID), !Task.isCancelled else { return }
            if AutoFillRequestErrorPolicy.cancellation(for: error, route: .passkeyAssertion) == .userCanceled {
                cancel(.userCanceled, invocationID: invocationID)
                return
            }
            guard let activeSession, (try? activeSession.checkAccess()) != nil else {
                cancel(.userInteractionRequired, invocationID: invocationID)
                return
            }
            // Never complete a registration whose vault write failed: the site would record a
            // passkey whose private half exists nowhere, locking the user out of their own account.
            AutoFillLog.logger.debug("passkey registration FAILED: [redacted error]")
            showPasskeyRegistration(
                request: request,
                identity: identity,
                existing: existing,
                error: AutoFillRequestErrorPolicy.registrationMessage(for: error),
                canSave: AutoFillRequestErrorPolicy.registrationCanRetry(error),
                invocationID: invocationID
            )
        }
    }

    @available(macOS 14.0, iOS 17.0, *)
    private func resolveRegistrationTarget(
        cipherId: String?,
        identity: ASPasskeyCredentialIdentity,
        session: ExtensionVaultSession
    ) async throws -> AutoFillPasskeyRegistration.Target {
        guard let cipherId else {
            return .newItem(relyingPartyIdentifier: identity.relyingPartyIdentifier, userName: identity.userName)
        }
        // The picker stores metadata only; re-read the SDK view for this existing registration path.
        guard let cipher = try await session.credentials.cipherView(cipherId: cipherId) else {
            throw AutoFillOperationError.decryptFailed
        }
        return .existing(cipher)
    }

    @available(macOS 14.0, iOS 17.0, *)
    private func handlePasskeyRequest(_ request: ASPasskeyCredentialRequest, invocationID: UUID) async {
        guard let identity = request.credentialIdentity as? ASPasskeyCredentialIdentity,
              let cipherId = identity.recordIdentifier
        else {
            AutoFillLog.logger.debug("handlePasskeyRequest: no ASPasskeyCredentialIdentity / recordIdentifier")
            cancel(.credentialIdentityNotFound, invocationID: invocationID)
            return
        }
        AutoFillLog.logger.debug("handlePasskeyRequest: rpId \(identity.relyingPartyIdentifier)")
        do {
            let session = try await session(for: invocationID)
            let match = try await session.passkeys.match(
                cipherId: cipherId,
                credentialID: identity.credentialID,
                relyingPartyIdentifier: identity.relyingPartyIdentifier
            )
            await assertPasskey(
                for: match,
                clientDataHash: request.clientDataHash,
                relyingPartyIdentifier: identity.relyingPartyIdentifier,
                allowedCredentials: [identity.credentialID],
                userVerification: request.userVerificationPreference.rawValue,
                invocationID: invocationID
            )
        } catch {
            cancel(
                AutoFillRequestErrorPolicy.cancellation(for: error, route: .passkeyAssertion),
                invocationID: invocationID
            )
        }
    }

    @available(macOS 14.0, iOS 17.0, *)
    private func assertPasskey(
        for match: AutoFillLoginSummary,
        clientDataHash: Data,
        relyingPartyIdentifier: String,
        allowedCredentials: [Data],
        userVerification: String,
        invocationID: UUID
    ) async {
        do {
            let session = try await session(for: invocationID)
            let assertion = try await AutoFillPasskeyAssertion.make(
                for: match,
                clientDataHash: clientDataHash,
                relyingPartyIdentifier: relyingPartyIdentifier,
                allowedCredentials: allowedCredentials,
                userVerification: userVerification,
                session: session
            )
            AutoFillLog.logger.debug("assertPasskey: assertion produced, completing")
            try finish(assertion, session: session, invocationID: invocationID)
        } catch {
            AutoFillLog.logger.debug("assertPasskey FAILED: [redacted error]")
            cancel(
                AutoFillRequestErrorPolicy.cancellation(for: error, route: .passkeyAssertion),
                invocationID: invocationID
            )
        }
    }

    private func cancel(_ reason: AutoFillCancellationReason, invocationID: UUID) {
        completion.cancel(
            reason,
            invocationID: invocationID,
            context: SystemAutoFillExtensionContext(extensionContext),
            retire: { self.retireInvocation(cancelTask: true) }
        )
    }
}
