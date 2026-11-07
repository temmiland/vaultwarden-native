import Domain

/// Repository and session-runtime implementations belong here. This target deliberately contains
/// no UI. Repository and auth-flow ports expose Domain values/capabilities; only app composition
/// consumes the concrete session assembly to construct session-bound repositories/adapters.
public enum DataModule {
    public static let name = "Data"
}
