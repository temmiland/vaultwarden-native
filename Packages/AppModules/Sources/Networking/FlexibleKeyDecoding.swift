import Foundation

/// Bitwarden's servers mix casing conventions in their JSON responses: the standard OAuth2 token
/// fields are snake_case (`access_token`, `refresh_token`, ...) while Bitwarden-specific fields are
/// PascalCase (`Key`, `PrivateKey`, `Kdf`, ...), and some endpoints answer camelCase. Vaultwarden
/// mirrors this exactly for compatibility. Rather than hand-writing `CodingKeys` per casing,
/// normalize every incoming key to camelCase and declare models with camelCase Swift property names.
///
/// The Foundation-only decoder belongs to Networking; feature/SDK modules use the same strategy.
public enum FlexibleKeyDecoding {
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { codingPath in
            AnyCodingKey(stringValue: camelCase(codingPath.last?.stringValue ?? ""))
        }
        return decoder
    }

    private static func camelCase(_ key: String) -> String {
        if key.contains("_") {
            let parts = key.lowercased().split(separator: "_")
            guard let first = parts.first else { return key }
            let rest = parts.dropFirst().map { $0.capitalized }
            return ([String(first)] + rest).joined()
        }
        guard let first = key.first else { return key }
        return first.lowercased() + key.dropFirst()
    }
}

private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
