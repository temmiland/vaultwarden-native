@testable import Data
import Foundation
import Testing

@Suite
struct AutoFillDiagnosticsTests {
    @Test
    func failureMetadataNeverIncludesErrorDescriptionsPathsOrUserInfo() throws {
        let underlying = NSError(
            domain: NSPOSIXErrorDomain,
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "fixture-sensitive-underlying"]
        )
        let error = NSError(domain: NSCocoaErrorDomain, code: 513, userInfo: [
            NSLocalizedDescriptionKey: "fixture-sensitive-description", NSFilePathErrorKey: "/sensitive/vault/path",
            NSUnderlyingErrorKey: underlying, "account": "fixture-sensitive-account",
            "token": "fixture-sensitive-token",
        ])
        let payload = try JSONEncoder().encode(AutoFillDiagnostics.Failure(error))
        let text = String(decoding: payload, as: UTF8.self)
        #expect(!text.contains("sensitive"))
        let result = try JSONSerialization.jsonObject(with: payload) as! [String: Any]
        #expect(result["category"] as? String == "Cocoa")
        #expect(result["code"] as? Int == 513)
        #expect(result["underlyingCategory"] as? String == "POSIX")
        #expect(result["underlyingCode"] as? Int == 1)
    }
}
