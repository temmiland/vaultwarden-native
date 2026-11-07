import BitwardenSdk
import BitwardenSDKAdapter
import Data
import Domain
import Foundation
import Testing

@Suite
struct SDKAutoFillRegistrationIdentityMapperTests {
    @Test
    func selectsOnlyExactSDKDecodedPasskeyUsingTheSharedDescriptorIDMapper() throws {
        let metadata = [1, 2].map { SDKAutoFillPasskeyMetadata(
            legacyView: AutoFillQuerySourceFixture.passkey(id: UInt8($0))
        ) }
        let source = try SDKAutoFillRegistrationIdentityMapper.source(
            cipher: AutoFillQuerySourceFixture.dto("cipher-1"),
            view: SDKAutoFillCredentialView(legacyView: AutoFillQuerySourceFixture.view(hasPasskeys: true)),
            passkeys: metadata,
            credentialID: Foundation.Data([2]),
            relyingPartyIdentifier: "example.com"
        )
        #expect(source.serviceIdentifiers.isEmpty && !source.hasOneTimeCode && source.passkeys.count == 1)
        let identities = CredentialIdentityMapper.makeIdentities(from: [source])
        #expect(identities.count == 1 && identities.first?.kind == .passkey)
        #expect(identities.first?.credentialID == Foundation.Data([2]))
        #expect(identities.first?.id == "cipher-1|passkey|example.com|Ag==")
        #expect(identities.first?.userHandle == Foundation.Data())
    }

    @Test(arguments: ["missing", "duplicate", "rp", "cipher", "protected", "stale"])
    func rejectsUnprovenOrAmbiguousRegistrationMetadata(_ failure: String) throws {
        var dto = AutoFillQuerySourceFixture.dto("cipher-1")
        let view = SDKAutoFillCredentialView(legacyView: AutoFillQuerySourceFixture.view(
            hasPasskeys: true,
            reprompt: failure == "protected" ? .password : .none
        ))
        var passkeys = [AutoFillQuerySourceFixture.passkey()]
        switch failure {
        case "missing": passkeys = []
        case "duplicate": passkeys.append(passkeys[0])
        case "rp": passkeys = [AutoFillQuerySourceFixture.passkey(rp: "other.example.com")]
        case "cipher": passkeys = [Fido2CredentialAutofillView(
                credentialId: Foundation.Data([1]),
                cipherId: "other",
                rpId: "example.com",
                userNameForUi: "user",
                userHandle: Foundation.Data(),
                hasCounter: false
            )]
        case "stale": dto.revisionDate = "2020-01-01T00:00:00.000Z"
        default: break
        }
        #expect(throws: SDKAutoFillRegistrationIdentityError.invalidMetadata) {
            try SDKAutoFillRegistrationIdentityMapper.source(
                cipher: dto,
                view: view,
                passkeys: passkeys.map { SDKAutoFillPasskeyMetadata(legacyView: $0) },
                credentialID: Foundation.Data([1]),
                relyingPartyIdentifier: "example.com"
            )
        }
    }
}
