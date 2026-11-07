import Foundation
import Networking
import Testing

@Suite
struct HTTPStatusErrorPrivacyTests {
    @Test
    func serverBodyKeysAndValuesAreNotRetainedInErrors() {
        let body = Data(
            #"{"synthetic-sensitive-key":123456,"error":"synthetic-secret","status":654321,"nested":{"other":1234}}"#.utf8
        )
        let error = HTTPStatusError(response: HTTPResponse(
            statusCode: 429,
            headers: ["Retry-After": "30", "Set-Cookie": "synthetic-cookie"],
            body: body
        ))
        let reflected = String(reflecting: error)

        #expect(error.statusCode == 429)
        #expect(error.retryAfter == 30)
        #expect(!reflected.contains("synthetic-sensitive-key"))
        #expect(!reflected.contains("synthetic-secret"))
        #expect(!reflected.contains("654321"))
        #expect(!reflected.contains("synthetic-cookie"))
    }
}
