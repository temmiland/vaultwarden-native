import BitwardenSdk
import Domain
import Foundation

/// Uses the SDK generator, with a system-random fallback that obeys the same selected classes
/// and minimum counts. Invalid options are rejected before either implementation runs.
public struct SDKPasswordGeneratorService: PasswordGenerating {
    private let sessionClient: SDKSessionClient

    public init(client: Client) {
        sessionClient = SDKSessionClient(client: client)
    }

    public init(sessionClient: SDKSessionClient) { self.sessionClient = sessionClient }

    public func generatePassword(options: PasswordGeneratorOptions) throws -> String {
        try options.validate()
        let request = PasswordGeneratorRequest(
            lowercase: options.useLowercase,
            uppercase: options.useUppercase,
            numbers: options.useNumbers,
            special: options.useSpecial,
            length: UInt8(options.length),
            avoidAmbiguous: options.avoidAmbiguous,
            minLowercase: nil,
            minUppercase: nil,
            minNumber: options.useNumbers ? UInt8(options.minNumbers) : nil,
            minSpecial: options.useSpecial ? UInt8(options.minSpecial) : nil,
            customRequiredChars: nil,
            customAllowedChars: nil,
            maxConsecutive: nil
        )
        do {
            return try sessionClient.withClient { try $0.generators().password(settings: request) }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try sessionClient.checkAccess()
            let password = try LocalPasswordGenerator.generate(options: options)
            try sessionClient.checkAccess()
            return password
        }
    }
}

/// Only used if the SDK call fails. Randomness comes from the OS-backed Swift system RNG;
/// no user secrets or generated passwords are persisted or logged here.
enum LocalPasswordGenerator {
    private static let ambiguousCharacters: Set<Character> = ["I", "O", "l", "0", "1"]

    static func generate(options: PasswordGeneratorOptions) throws -> String {
        try options.validate()
        var classes: [(characters: [Character], minimum: Int)] = []
        if options.useLowercase {
            classes.append((filtered("abcdefghijklmnopqrstuvwxyz", options: options), 1))
        }
        if options.useUppercase {
            classes.append((filtered("ABCDEFGHIJKLMNOPQRSTUVWXYZ", options: options), 1))
        }
        if options.useNumbers {
            classes.append((filtered("0123456789", options: options), max(1, options.minNumbers)))
        }
        if options.useSpecial {
            classes.append((filtered("!@#$%^&*", options: options), max(1, options.minSpecial)))
        }

        var generator = SystemRandomNumberGenerator()
        var result: [Character] = []
        result.reserveCapacity(options.length)
        for characterClass in classes {
            for _ in 0 ..< characterClass.minimum {
                guard let character = characterClass.characters.randomElement(using: &generator) else {
                    throw PasswordGenerationError.generationFailed
                }
                result.append(character)
            }
        }
        let allCharacters = classes.flatMap(\.characters)
        while result.count < options.length {
            guard let character = allCharacters.randomElement(using: &generator) else {
                throw PasswordGenerationError.generationFailed
            }
            result.append(character)
        }
        result.shuffle(using: &generator)
        return String(result)
    }

    private static func filtered(_ characters: String, options: PasswordGeneratorOptions) -> [Character] {
        guard options.avoidAmbiguous else { return Array(characters) }
        return characters.filter { !ambiguousCharacters.contains($0) }
    }
}
