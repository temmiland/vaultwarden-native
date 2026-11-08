import AppFeature
import AuthenticationServices
import AutoFillContract
import AutoFillData
import AutoFillFeature
import Foundation
import SecurityStorage
import SwiftUI
import XCTest
#if os(iOS)
    import UIKit
    private typealias TestHost<Content: View> = UIHostingController<Content>
    private typealias PlatformViewController = UIViewController
    private typealias PlatformView = UIView
#else
    import AppKit
    private typealias TestHost<Content: View> = NSHostingController<Content>
    private typealias PlatformViewController = NSViewController
    private typealias PlatformView = NSView
#endif

/// Hostless bundles expose no reliable accessibility tree, so these smokes prove appearance through
/// observable lifecycle effects (model start, composed sync request) plus real window layout.
@MainActor
final class PlatformHostingTests: XCTestCase {
    func testSharedClockSessionIsAvailableAndStableInTheNativeTestHost() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let initial = try SharedClockSession.currentID(containerURL: directory)
        XCTAssertEqual(try SharedClockSession.currentID(containerURL: directory), initial)
    }

    func testConfigurationRecoveryHostsOnNativePlatform() {
        let host = TestHost(rootView: AppStartupRootView(startup: .unavailable(.sharedContainerUnavailable)))
        let window = TestWindow(host)
        defer { window.close() }
        window.layout()
        assertLaidOut(host.view)
        #if os(iOS)
            let size = host.sizeThatFits(in: window.contentSize)
        #else
            let size = host.view.fittingSize
        #endif
        // SwiftUI may render directly into the hosting view. Counting private native subviews is
        // not a content assertion; ask the actual layout engine for the content's required size.
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
    }

    func testRealRootDrivesLifecycleThroughFirstRunUnlockedRecoveryAndLockedStates() async throws {
        let files = IntegrationFileLifecycle()
        let fixture = try IntegrationAssembly(files: files)
        defer { fixture.cleanUp() }
        let model = fixture.composition.makeModel()
        let host = TestHost(rootView: RootView(appModel: model, composition: fixture.composition))
        let window = TestWindow(host)
        defer { window.close() }

        // Only an actual appearance runs RootView's `.task`, which starts repository observation.
        for _ in 0 ..< 500 where !model.state.isSignedOut { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.state.isSignedOut, "Hosted RootView started the app model")
        window.layout()
        assertLaidOut(host.view)

        let session = try fixture.session()
        await fixture.composition.accept(session, into: model)
        XCTAssertEqual(model.session?.id, session.id)
        window.layout()
        // The unlocked tab tree appeared and loaded through the composed repository/transport.
        var observedSync = false
        for _ in 0 ..< 500 {
            if await fixture.http.requests.contains(where: { $0.url.path.hasSuffix("/api/sync") }) {
                observedSync = true
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(observedSync, "Hosted unlocked view started a vault sync")
        assertLaidOut(host.view)

        files.failCleanup(true)
        await model.lockNow()
        XCTAssertEqual(model.state.recoveryAction, .lock)
        let requestsAtRecovery = await fixture.http.requests.count
        window.layout()
        assertLaidOut(host.view)
        XCTAssertThrowsError(try session.checkAccess())

        files.failCleanup(false)
        await model.retrySecurityAction()
        XCTAssertEqual(model.state.lockedAccount, session.account)
        window.layout()
        assertLaidOut(host.view)
        let requestsAfterRecovery = await fixture.http.requests.count
        XCTAssertEqual(requestsAfterRecovery, requestsAtRecovery, "Retired vault UI must not sync again")
        await model.logOut()
    }

    func testRecoveryViewLaysOutRevokedStateStandalone() async throws {
        let files = IntegrationFileLifecycle()
        let fixture = try IntegrationAssembly(files: files)
        defer { fixture.cleanUp() }
        let model = fixture.composition.makeModel()
        let session = try fixture.session()
        await fixture.composition.accept(session, into: model)
        files.failCleanup(true)
        await model.logOut()
        XCTAssertEqual(model.state.recoveryAction, .logout)
        XCTAssertNil(try fixture.store.loadSession())
        let host = TestHost(rootView: SessionSecurityRecoveryView(appModel: model))
        let window = TestWindow(host)
        defer { window.close() }
        window.layout()
        assertLaidOut(host.view)
        #if os(iOS)
            let size = host.sizeThatFits(in: window.contentSize)
        #else
            let size = host.view.fittingSize
        #endif
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
        XCTAssertEqual(
            model.securityErrorMessage,
            "Sensitive attachment files couldn't be removed. Retry secure cleanup before unlocking again."
        )
        XCTAssertThrowsError(try session.checkAccess())
    }

    // MARK: - Apple credential provider controller

    #if os(iOS)
        func testApplePasswordSaveHostsFailureWithoutSharedOwnerStorage() async throws {
            guard #available(iOS 26.2, *) else { throw XCTSkip("Password saving requires iOS 26.2") }
            let controller = CredentialProviderViewController()
            controller.sessionLoader = { throw AutoFillOperationError.noSharedKey }
            let window = TestWindow(controller)
            defer { window.close() }
            let request = ASSavePasswordRequest(
                serviceIdentifier: ASCredentialServiceIdentifier(identifier: "https://example.com", type: .URL),
                credential: ASPasswordCredential(user: "synthetic-user", password: "synthetic-password"),
                sessionID: UUID().uuidString, event: .userInitiated
            )
            controller.prepareInterface(for: request)
            try await waitForContent(controller)
            XCTAssertTrue(controller.children.first is TestHost<PasswordSaveView>)
            window.layout()
            assertLaidOut(controller.view)
        }
    #endif

    func testAppleCredentialProviderHostsFailureAndReplacesInvocationContent() async throws {
        let controller = CredentialProviderViewController()
        controller.sessionLoader = { throw AutoFillOperationError.noCache }
        let window = TestWindow(controller)
        defer { window.close() }
        controller.prepareCredentialList(for: [])
        try await waitForContent(controller)
        let previous = try XCTUnwrap(controller.children.first)
        XCTAssertTrue(previous.parent === controller)
        XCTAssertTrue(previous.view.superview === controller.view)
        XCTAssertTrue(previous is TestHost<CredentialListView>)
        assertPinnedToEdges(previous.view, of: controller.view)
        window.layout()
        assertLaidOut(controller.view)
        XCTAssertEqual(previous.view.frame, controller.view.bounds)

        controller.prepareCredentialList(for: [])
        // Replacement is synchronous at invocation start; no stale picker stays interactive.
        XCTAssertTrue(controller.children.isEmpty)
        XCTAssertNil(previous.parent)
        XCTAssertNil(previous.view.superview)
        XCTAssertTrue(constraints(of: controller.view, involving: previous.view).isEmpty)
        try await waitForContent(controller)
        XCTAssertEqual(controller.children.count, 1)
        XCTAssertFalse(controller.children.first === previous)
        let replacement = try XCTUnwrap(controller.children.first)
        assertPinnedToEdges(replacement.view, of: controller.view)
        window.layout()
        XCTAssertEqual(replacement.view.frame, controller.view.bounds)
    }

    func testNewInvocationRetiresPreviousSessionBeforeLoadingAgain() async throws {
        let first = try syntheticExtensionSession()
        let controller = CredentialProviderViewController()
        controller.sessionLoader = { first }
        let window = TestWindow(controller)
        defer { window.close() }
        controller.prepareCredentialList(for: [])
        try await waitForContent(controller)
        let listed = try XCTUnwrap(controller.children.first)
        XCTAssertNoThrow(try first.checkAccess(), "The displayed invocation owns its session")

        controller.sessionLoader = { throw AutoFillOperationError.noCache }
        controller.prepareCredentialList(for: [])
        XCTAssertThrowsError(try first.checkAccess(), "A new invocation must revoke the previous session")
        XCTAssertTrue(controller.children.isEmpty)
        XCTAssertNil(listed.parent)
        try await waitForContent(controller)
        XCTAssertFalse(controller.children.first === listed)
        window.layout()
        assertLaidOut(controller.view)
    }

    func testLateLoaderFromRetiredInvocationCannotPublishContentOrKeepSession() async throws {
        let gate = IntegrationGate()
        defer { gate.open() }
        let late = try syntheticExtensionSession()
        let controller = CredentialProviderViewController()
        controller.sessionLoader = {
            await gate.pass()
            return late
        }
        let window = TestWindow(controller)
        defer { window.close() }
        controller.prepareCredentialList(for: [])
        await fulfillment(of: [gate.entered], timeout: 5)
        XCTAssertTrue(controller.children.isEmpty)

        controller.sessionLoader = { throw AutoFillOperationError.noCache }
        controller.prepareCredentialList(for: [])
        try await waitForContent(controller)
        let current = try XCTUnwrap(controller.children.first)

        gate.open()
        await waitForRevocation(of: late)
        // Give the retired task every chance to (incorrectly) embed its view after revocation.
        for _ in 0 ..< 20 { await Task.yield() }
        XCTAssertEqual(controller.children.count, 1)
        XCTAssertTrue(controller.children.first === current)
        window.layout()
        XCTAssertEqual(current.view.frame, controller.view.bounds)
    }

    // MARK: - Helpers

    private func waitForContent(_ controller: CredentialProviderViewController) async throws {
        // Bounded native-controller smoke, not an assumed App Group/OS extension-context run.
        for _ in 0 ..< 200 {
            if controller.children.count == 1 { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Credential provider did not install hosted content")
    }

    private func waitForRevocation(of session: ExtensionVaultSession) async {
        for _ in 0 ..< 200 {
            if (try? session.checkAccess()) == nil { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("A retired invocation kept its late session")
    }

    /// Structurally valid, empty and owner-bound: listing needs no decryption and no App Group.
    private func syntheticExtensionSession() throws -> ExtensionVaultSession {
        let server = URL(string: "https://vault.example.invalid")!
        let owner = AutoFillAccountIdentity(userID: "synthetic-account", serverBaseURL: server)
        let proof = ExtensionUnlockProof(account: owner)
        let revision = UUID()
        let cache = SharedVaultCacheData(
            ciphers: [], organizationKeys: [:], updatedAt: Date(), owner: owner, revision: revision
        )
        return try ExtensionVaultSession(
            accountInfo: SharedAccountInfo(
                userId: owner.userID, email: "synthetic@example.invalid", kdfType: 0, kdfIterations: 600_000,
                kdfMemory: nil, kdfParallelism: nil, encryptedPrivateKey: "synthetic-wrapped-private-key",
                serverBaseURL: server
            ),
            proof: proof, cacheRevision: revision, applicationVersion: "integration",
            currentProof: { proof }, readCache: { cache }
        )
    }

    private func constraints(of container: PlatformView, involving child: PlatformView) -> [NSLayoutConstraint] {
        container.constraints.filter { $0.firstItem === child || $0.secondItem === child }
    }

    private func assertPinnedToEdges(
        _ child: PlatformView,
        of container: PlatformView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(child.translatesAutoresizingMaskIntoConstraints, file: file, line: line)
        let pinned = Set(constraints(of: container, involving: child).filter(\.isActive).map(\.firstAttribute))
        XCTAssertEqual(pinned, [.leading, .trailing, .top, .bottom], file: file, line: line)
    }

    private func assertLaidOut(_ view: PlatformView, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(view.frame.width, 0, file: file, line: line)
        XCTAssertGreaterThan(view.frame.height, 0, file: file, line: line)
    }
}

/// A real window, so SwiftUI/UIKit/AppKit perform appearance and layout rather than a detached
/// view merely being constructed.
@MainActor
private final class TestWindow {
    #if os(iOS)
        private let window: UIWindow
    #else
        private let window: NSWindow
    #endif
    #if os(iOS)
        let contentSize = CGSize(width: 390, height: 700)
    #else
        // Accommodate the desktop navigation sidebar and detail view simultaneously.
        let contentSize = CGSize(width: 1000, height: 700)
    #endif

    init(_ controller: PlatformViewController) {
        #if os(iOS)
            window = UIWindow(frame: CGRect(origin: .zero, size: contentSize))
            window.rootViewController = controller
            window.makeKeyAndVisible()
        #else
            _ = NSApplication.shared
            window = NSWindow(
                contentRect: NSRect(origin: .zero, size: contentSize),
                styleMask: [.titled, .resizable], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            // Host the tested controller as content rather than the window's root. Otherwise
            // SwiftUI's toolbar bridge resizes the window during session-state layout,
            // re-entering AppKit layout while retiring the previous hosting hierarchy.
            let container = NSViewController()
            container.view = NSView(frame: NSRect(origin: .zero, size: contentSize))
            container.addChild(controller)
            controller.view.frame = container.view.bounds
            controller.view.autoresizingMask = [.width, .height]
            container.view.addSubview(controller.view)
            window.contentViewController = container
            window.setContentSize(contentSize)
            window.orderFront(nil)
        #endif
        layout()
    }

    func layout() {
        #if os(iOS)
            window.layoutIfNeeded()
            window.rootViewController?.view.layoutIfNeeded()
        #else
            // Let the window coordinate its content layout rather than forcing the
            // NSHostingView subtree independently of the window's layout pass.
            window.layoutIfNeeded()
        #endif
    }

    func close() {
        #if os(iOS)
            window.isHidden = true
            window.rootViewController = nil
        #else
            window.orderOut(nil)
            // Closing tears down the AppKit/SwiftUI hosting hierarchy. Clearing the controller
            // immediately beforehand makes NSHostingController deallocate while the window is
            // still unwinding its content-view lifecycle on older macOS/Xcode runners.
            window.close()
        #endif
    }
}
