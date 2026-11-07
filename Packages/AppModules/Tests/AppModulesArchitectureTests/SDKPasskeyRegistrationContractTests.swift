import BitwardenSdk
import BitwardenSDKAdapter
import Foundation
import Testing

@Suite
struct SDKPasskeyRegistrationContractTests {
    @Test(arguments: [false, true])
    func creationEnvelopePreservesPlatformFieldsBytesAndAlgorithmDefault(_ defaultAlgorithms: Bool) throws {
        let request = try SDKWebAuthnCreationRequest.make(
            relyingPartyIdentifier: "example.com",
            userName: "üser",
            userHandle: Foundation.Data([251, 255]),
            supportedAlgorithms: defaultAlgorithms ? [] : [-7, -257],
            userVerification: "required"
        )
        let envelope = try #require(JSONSerialization.jsonObject(with: Foundation.Data(request.utf8)) as? [String: Any])
        let key = try #require(envelope["publicKey"] as? [String: Any])
        let rp = try #require(key["rp"] as? [String: String]), user = try #require(key["user"] as? [String: String])
        let params = try #require(key["pubKeyCredParams"] as? [[String: Any]])
        let selection = try #require(key["authenticatorSelection"] as? [String: Any])
        #expect(rp == ["id": "example.com", "name": "example.com"])
        #expect(user == ["id": "-_8", "name": "üser", "displayName": "üser"])
        #expect(params.compactMap { $0["alg"] as? Int } == (defaultAlgorithms ? [-7] : [-7, -257]))
        #expect(params.allSatisfy { $0["type"] as? String == "public-key" })
        #expect(key["challenge"] as? String == "AA" && key["attestation"] as? String == "none")
        #expect(selection["residentKey"] as? String == "required" && selection["requireResidentKey"] as? Bool == true)
        #expect(selection["userVerification"] as? String == "required")
    }

    @Test(arguments: ["rp", "verification"])
    func invalidRequestCannotReachSDK(_ scenario: String) throws {
        #expect(throws: SDKAutoFillFidoError.invalidRequest) {
            try SDKWebAuthnCreationRequest.make(
                relyingPartyIdentifier: scenario == "rp" ? "" : "example.com",
                userName: "user",
                userHandle: Foundation.Data(),
                supportedAlgorithms: [],
                userVerification: scenario == "verification" ? "invented" : "preferred"
            )
        }
    }

    @Test(
        arguments: [
            "create",
            "update",
            "drop",
            "duplicate",
            "unchanged",
            "two-new",
            "empty",
            "foreign-rp",
            "foreign-cipher",
            "changed-target",
            "readonly",
            "missing-passkeys",
        ]
    )
    func mutationMustAddExactlyOneDecodedCredentialToTheSameEligibleTarget(_ scenario: String) throws {
        let id: String? = scenario == "create" ? nil : "cipher-1"
        let target = SDKAutoFillCredentialView(legacyView: .fixture(id: id))
        let encrypted = SDKAutoFillEncryptedCipher(legacyCipher: .fixture(id: id), encryptedFor: "user-1")
        let updated = SDKAutoFillCredentialView(legacyView: .fixture(
            id: scenario == "changed-target" ? "other" : id,
            login: scenario == "missing-passkeys" ? CipherView.fixture().login : AutoFillQuerySourceFixture.view(
                hasPasskeys: true
            ).login,
            edit: scenario != "readonly"
        ))
        let old = Self.metadata(id: Foundation.Data([1]), cipher: id ?? "")
        let new = Self.metadata(
            id: scenario == "empty" ? Foundation.Data() : Foundation.Data([2]),
            cipher: scenario == "foreign-cipher" ? "other" : (id ?? ""),
            rp: scenario == "foreign-rp" ? "other.example.com" : "example.com"
        )
        let previous = scenario == "create" ? [] : [old]
        let current: [SDKAutoFillPasskeyMetadata]
        switch scenario {
        case "create", "drop": current = [new]
        case "duplicate": current = [old, new, new]
        case "unchanged": current = [old]
        case "two-new": current = [old, new, Self.metadata(id: Foundation.Data([3]))]
        default: current = [old, new]
        }
        if ["create", "update"].contains(scenario) {
            let added = try SDKPasskeyRegistrationMutationValidator.addedCredential(
                target: target,
                encrypted: encrypted,
                updated: updated,
                previous: previous,
                current: current,
                relyingPartyIdentifier: "example.com"
            )
            #expect(added.credentialId == Foundation.Data([2]))
        } else {
            #expect(throws: SDKAutoFillFidoError.accessDenied) {
                try SDKPasskeyRegistrationMutationValidator.addedCredential(
                    target: target,
                    encrypted: encrypted,
                    updated: updated,
                    previous: previous,
                    current: current,
                    relyingPartyIdentifier: "example.com"
                )
            }
        }
    }

    static func metadata(id: Foundation.Data, cipher: String = "cipher-1", rp: String = "example.com") -> SDKAutoFillPasskeyMetadata {
        SDKAutoFillPasskeyMetadata(legacyView: Fido2CredentialAutofillView(
            credentialId: id,
            cipherId: cipher,
            rpId: rp,
            userNameForUi: "user",
            userHandle: Foundation.Data([7]),
            hasCounter: false
        ))
    }
}
