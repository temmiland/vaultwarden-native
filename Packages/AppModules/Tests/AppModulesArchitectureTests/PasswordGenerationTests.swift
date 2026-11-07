@testable import BitwardenSDKAdapter
import Domain
import Testing

@Suite
struct PasswordGenerationTests {
    @Test
    func fallbackHonorsAllSelectedClassesAndMinimumCounts() throws {
        let options = PasswordGeneratorOptions(length: 20, minNumbers: 6, minSpecial: 7)
        let lower = Set("abcdefghijklmnopqrstuvwxyz")
        let upper = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let numbers = Set("23456789")
        let special = Set("!@#$%^&*")
        let allowed = lower.union(upper).union(numbers).union(special).subtracting(Set("IOl01"))

        for _ in 0 ..< 16 {
            let password = try LocalPasswordGenerator.generate(options: options)
            #expect(password.count == options.length)
            #expect(password.contains { lower.contains($0) })
            #expect(password.contains { upper.contains($0) })
            #expect(password.filter { numbers.contains($0) }.count >= options.minNumbers)
            #expect(password.filter { special.contains($0) }.count >= options.minSpecial)
            #expect(password.allSatisfy { allowed.contains($0) })
        }
    }

    @Test
    func fallbackFitsExactMinimumCountsWithoutTruncation() throws {
        let options = PasswordGeneratorOptions(
            length: 14, useUppercase: false, useLowercase: false, minNumbers: 6, minSpecial: 8
        )
        let password = try LocalPasswordGenerator.generate(options: options)

        #expect(password.count == 14)
        #expect(password.filter { Set("23456789").contains($0) }.count == 6)
        #expect(password.filter { Set("!@#$%^&*").contains($0) }.count == 8)
    }

    @Test
    func enabledClassesStillContributeWhenTheirRequestedMinimumIsZero() throws {
        let options = PasswordGeneratorOptions(length: 5, minNumbers: 0, minSpecial: 0)
        let password = try LocalPasswordGenerator.generate(options: options)

        #expect(password.count == 5)
        #expect(password.contains { Set("23456789").contains($0) })
        #expect(password.contains { Set("!@#$%^&*").contains($0) })
    }

    @Test
    func inactiveClassesIgnoreTheirMinimumsAndNeverLeakCharacters() throws {
        let options = PasswordGeneratorOptions(
            length: 128, useUppercase: false, useNumbers: false, useSpecial: false,
            minNumbers: Int.max, minSpecial: Int.min
        )
        let password = try LocalPasswordGenerator.generate(options: options)

        #expect(password.count == 128)
        #expect(password.allSatisfy { Set("abcdefghijkmnopqrstuvwxyz").contains($0) })
    }

    @Test
    func invalidOptionsAreRejectedRatherThanClampedOrSilentlyAdjusted() {
        let cases: [(PasswordGeneratorOptions, PasswordGenerationError)] = [
            (.init(length: 4), .invalidLength),
            (.init(length: 129), .invalidLength),
            (.init(length: Int.max), .invalidLength),
            (.init(useUppercase: false, useLowercase: false, useNumbers: false, useSpecial: false), .noCharacterClasses),
            (.init(minNumbers: -1), .invalidMinimumCounts),
            (.init(minSpecial: 10), .invalidMinimumCounts),
            (.init(length: 5, minNumbers: 3, minSpecial: 3), .minimumCountsExceedLength),
        ]
        for (options, error) in cases {
            #expect(throws: error) { try options.validate() }
            #expect(throws: error) { _ = try LocalPasswordGenerator.generate(options: options) }
        }
    }
}
