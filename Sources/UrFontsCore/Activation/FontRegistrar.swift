import CoreText
import Foundation

/// Where a registration lives.
///
/// `.user` is the default for activation: all processes for this user, and it
/// survives sessions until unregistered. `.session` is for temporary
/// activation: it ends at logout, but we still unregister explicitly on quit.
public enum FontRegistrationScope: String, Sendable, CaseIterable {
    case none
    case process
    case user
    case session

    public var coreText: CTFontManagerScope {
        switch self {
        case .none: .none
        case .process: .process
        case .user: .user
        case .session: .session
        }
    }

    public init(coreText scope: CTFontManagerScope) {
        switch scope {
        case .process: self = .process
        case .user, .persistent: self = .user
        case .session: self = .session
        default: self = .none
        }
    }

    public var isRegistered: Bool { self != .none }
}

public struct RegistrationFailure: Sendable, Equatable {
    public let message: String
    public let urls: [URL]

    public init(message: String, urls: [URL]) {
        self.message = message
        self.urls = urls
    }
}

/// Facts after an operation, not optimism before confirmation.
///
/// `confirmedCount` is measured with `CTFontManagerGetScopeForURL`, because
/// fontd can reject or ignore individual files and because a batch can be
/// partly successful. Callers never have to guess.
public struct RegistrationReport: Sendable, Equatable {
    public let requestedCount: Int
    public let confirmedCount: Int
    public let failures: [RegistrationFailure]

    public init(requestedCount: Int, confirmedCount: Int, failures: [RegistrationFailure]) {
        self.requestedCount = requestedCount
        self.confirmedCount = confirmedCount
        self.failures = failures
    }

    public var succeeded: Bool { failures.isEmpty && confirmedCount == requestedCount }
}

/// Hides fontd. Tests use a fake; the app uses `CoreTextRegistrar`.
public protocol FontRegistrar: Sendable {
    func register(_ urls: [URL], scope: FontRegistrationScope) -> RegistrationReport
    func unregister(_ urls: [URL], scope: FontRegistrationScope) -> RegistrationReport
    func scope(of url: URL) -> FontRegistrationScope
}

/// Real registration. Every call blocks until fontd reports completion or the
/// timeout expires, then reads the resulting scope back.
public struct CoreTextRegistrar: FontRegistrar {
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 60) {
        self.timeout = timeout
    }

    public func register(_ urls: [URL], scope: FontRegistrationScope) -> RegistrationReport {
        guard !urls.isEmpty, scope.isRegistered else {
            return RegistrationReport(requestedCount: 0, confirmedCount: 0, failures: [])
        }
        let failures = perform(urls: urls) { array, handler in
            CTFontManagerRegisterFontURLs(array, scope.coreText, true, handler)
        }
        return report(urls: urls, expected: scope, failures: failures)
    }

    public func unregister(_ urls: [URL], scope: FontRegistrationScope) -> RegistrationReport {
        guard !urls.isEmpty, scope.isRegistered else {
            return RegistrationReport(requestedCount: 0, confirmedCount: 0, failures: [])
        }
        let failures = perform(urls: urls) { array, handler in
            CTFontManagerUnregisterFontURLs(array, scope.coreText, handler)
        }
        return report(urls: urls, expected: .none, failures: failures)
    }

    public func scope(of url: URL) -> FontRegistrationScope {
        FontRegistrationScope(coreText: CTFontManagerGetScopeForURL(url as CFURL))
    }

    private func report(
        urls: [URL],
        expected: FontRegistrationScope,
        failures: [RegistrationFailure]
    ) -> RegistrationReport {
        let confirmed = urls.reduce(into: 0) { count, url in
            if scope(of: url) == expected { count += 1 }
        }
        return RegistrationReport(
            requestedCount: urls.count,
            confirmedCount: confirmed,
            failures: failures
        )
    }

    private func perform(
        urls: [URL],
        call: (CFArray, @escaping (CFArray, Bool) -> Bool) -> Void
    ) -> [RegistrationFailure] {
        let box = FailureBox()
        let finished = DispatchSemaphore(value: 0)

        call(urls as CFArray) { errors, done in
            box.add(errors: errors)
            if done { finished.signal() }
            return true
        }

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            box.add(failure: RegistrationFailure(
                message: "fontd did not confirm within \(Int(timeout)) s",
                urls: []
            ))
        }
        return box.failures
    }
}

/// Thread-safe accumulator for the CoreText completion block, which can fire
/// more than once and never on a queue we control.
private final class FailureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [RegistrationFailure] = []

    var failures: [RegistrationFailure] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func add(errors: CFArray) {
        let count = CFArrayGetCount(errors)
        guard count > 0 else { return }
        for index in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(errors, index) else { continue }
            let error = unsafeBitCast(raw, to: CFError.self)
            let nsError = error as NSError
            let key = kCTFontManagerErrorFontURLsKey as String
            let failedURLs = (nsError.userInfo[key] as? [NSURL] ?? []).map { $0 as URL }
            add(failure: RegistrationFailure(
                message: error.localizedDescription,
                urls: failedURLs
            ))
        }
    }

    func add(failure: RegistrationFailure) {
        lock.lock()
        storage.append(failure)
        lock.unlock()
    }
}
