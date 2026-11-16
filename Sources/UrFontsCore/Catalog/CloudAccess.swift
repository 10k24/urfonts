import Darwin
import Foundation

/// Cloud/file-provider access failures that should not be treated as a damaged
/// font. These are transient and worth retrying once the provider is reachable.
public enum CloudAccess {
    public static let message =
        "Cloud folder unavailable. Check your connection and rescan."

    public static func isUnavailable(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            let code = URLError.Code(rawValue: nsError.code)
            switch code {
            case .timedOut, .notConnectedToInternet, .networkConnectionLost,
                 .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return true
            default:
                break
            }
        }
        if nsError.domain == NSPOSIXErrorDomain {
            let code = Int32(nsError.code)
            switch code {
            case ETIMEDOUT, ENETUNREACH, ENETDOWN, EHOSTUNREACH,
                 ECONNREFUSED, ECONNRESET, EAGAIN, EBUSY:
                return true
            default:
                break
            }
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isUnavailable(underlying)
        }
        return false
    }
}
