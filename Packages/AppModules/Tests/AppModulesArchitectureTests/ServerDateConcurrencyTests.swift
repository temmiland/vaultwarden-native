import BitwardenSDKAdapter
import Foundation
import Testing

@Suite
struct ServerDateConcurrencyTests {
    @Test
    func concurrentParsingAndFormattingPreservesTheWirePolicy() async {
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 100 {
                group.addTask {
                    let date = Date(timeIntervalSince1970: 1_704_067_200.125)
                    #expect(ServerDateParsing.format(date) == "2024-01-01T00:00:00.125Z")
                    #expect(ServerDateParsing.parse("2024-01-01T00:00:00.125Z") == date)
                    #expect(
                        ServerDateParsing.parse("2024-01-01T01:00:00+01:00") == Date(
                            timeIntervalSince1970: 1_704_067_200
                        )
                    )
                    #expect(ServerDateParsing.parse("2024-01-01T00:00:00.123garbageZ") == nil)
                }
            }
        }
    }
}
