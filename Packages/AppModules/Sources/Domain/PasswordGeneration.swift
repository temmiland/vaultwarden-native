import Foundation

public struct PasswordGeneratorOptions: Equatable, Sendable {
    public var length: Int
    public var useUppercase: Bool
    public var useLowercase: Bool
    public var useNumbers: Bool
    public var useSpecial: Bool
    public var avoidAmbiguous: Bool
    public var minNumbers: Int
    public var minSpecial: Int

    public init(
        length: Int = 18,
        useUppercase: Bool = true,
        useLowercase: Bool = true,
        useNumbers: Bool = true,
        useSpecial: Bool = true,
        avoidAmbiguous: Bool = true,
        minNumbers: Int = 1,
        minSpecial: Int = 1
    ) {
        self.length = length
        self.useUppercase = useUppercase
        self.useLowercase = useLowercase
        self.useNumbers = useNumbers
        self.useSpecial = useSpecial
        self.avoidAmbiguous = avoidAmbiguous
        self.minNumbers = minNumbers
        self.minSpecial = minSpecial
    }

    /// Mirrors the existing UI bounds and the SDK's minimum-count semantics: every enabled
    /// class contributes at least one character, even when its requested minimum is zero.
    public func validate() throws {
        guard (5 ... 128).contains(length) else { throw PasswordGenerationError.invalidLength }
        guard useUppercase || useLowercase || useNumbers || useSpecial else {
            throw PasswordGenerationError.noCharacterClasses
        }
        guard !useNumbers || (0 ... 9).contains(minNumbers),
              !useSpecial || (0 ... 9).contains(minSpecial)
        else { throw PasswordGenerationError.invalidMinimumCounts }

        let requiredCount = (useUppercase ? 1 : 0) + (useLowercase ? 1 : 0)
            + (useNumbers ? max(1, minNumbers) : 0) + (useSpecial ? max(1, minSpecial) : 0)
        guard requiredCount <= length else { throw PasswordGenerationError.minimumCountsExceedLength }
    }
}

public protocol PasswordGenerating: Sendable {
    func generatePassword(options: PasswordGeneratorOptions) throws -> String
}

public enum PasswordGenerationError: Error, Equatable, Sendable {
    case invalidLength
    case noCharacterClasses
    case invalidMinimumCounts
    case minimumCountsExceedLength
    case generationFailed
}
