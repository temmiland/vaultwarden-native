import Domain

extension BiometryKind {
    var systemImageName: String {
        switch self {
        case .touchID: "touchid"
        case .faceID: "faceid"
        case .opticID: "opticid"
        case .unknown: "lock"
        }
    }
}
