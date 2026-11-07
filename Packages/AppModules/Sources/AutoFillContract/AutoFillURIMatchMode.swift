/// The existing per-URI match modes, independent of the SDK's representation.
public enum AutoFillURIMatchMode: Sendable {
    case domain
    case host
    case startsWith
    case exact
    case regularExpression
    case never
}
