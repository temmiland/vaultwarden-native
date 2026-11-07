import AutoFillContract
import BitwardenSdk

public extension AutoFillURIMatchMode {
    init(sdkMode: UriMatchType) {
        switch sdkMode {
        case .domain: self = .domain
        case .host: self = .host
        case .startsWith: self = .startsWith
        case .exact: self = .exact
        case .regularExpression: self = .regularExpression
        case .never: self = .never
        }
    }
}
