import Foundation
import Network

/// Watches for network connectivity to become available and re-runs whatever retry closures were
/// registered while a CDN fallback failed — "just in case" that failure was the device having no
/// connectivity at that instant, rather than the CDN genuinely not having the asset. Meant for
/// exactly one thing: giving an on-demand CDN fetch that failed a second chance automatically, once
/// there's a reasonable signal that trying again might actually work, without requiring the person
/// to navigate away and back (which would reconstruct the view and retry anyway, just not on its
/// own).
///
/// Built on `NWPathMonitor` — part of the system `Network` framework, no new dependency — rather
/// than the older `SCNetworkReachability`-based APIs, which `NWPathMonitor` has superseded.
public final class NetworkAvailabilityMonitor: @unchecked Sendable {
    public static let shared = NetworkAvailabilityMonitor(startMonitoring: true)

    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "NetworkAvailabilityMonitor.pathMonitor")

    private let stateQueue = DispatchQueue(label: "NetworkAvailabilityMonitor.state")
    nonisolated(unsafe) private var pendingRetries: [UUID: @Sendable () -> Void] = [:]

    /// `startMonitoring: false` builds an instance whose registry can be driven by hand via
    /// `runPendingRetries()` without a live `NWPathMonitor` racing it — exists for the unit tests,
    /// which is why it's `internal` rather than `private`. Production code only ever uses `shared`.
    internal init(startMonitoring: Bool) {
        guard startMonitoring else { return }

        self.pathMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            self?.runPendingRetries()
        }

        self.pathMonitor.start(queue: self.monitorQueue)
    }

    /// Registers `retry` to run the next time a path update reports connectivity as available,
    /// and returns a token that can be used to cancel it — e.g. from a view's `deinit`, if it's no
    /// longer around by the time connectivity returns. Not a guarantee the retry will succeed
    /// (device-level connectivity says nothing about whether the CDN itself is reachable), only
    /// that it's a reasonable moment to try again. Callers should weakly capture whatever state
    /// `retry` needs and no-op if it's gone.
    @discardableResult
    public func retryWhenAvailable(_ retry: @escaping @Sendable () -> Void) -> UUID {
        let token = UUID()

        self.stateQueue.sync {
            self.pendingRetries[token] = retry
        }

        return token
    }

    /// Cancels a previously registered retry. Safe to call with a token that already ran or was
    /// already cancelled — both are simple dictionary misses.
    public func cancelRetry(_ token: UUID) {
        let _ = self.stateQueue.sync {
            self.pendingRetries.removeValue(forKey: token)
        }
    }

    /// Runs and clears every pending retry. Called by the path monitor on connectivity;
    /// `internal` so tests can drive it deterministically on a non-monitoring instance.
    internal func runPendingRetries() {
        let retries: [@Sendable () -> Void] = self.stateQueue.sync {
            let values = Array(self.pendingRetries.values)
            self.pendingRetries.removeAll()
            return values
        }

        retries.forEach { $0() }
    }
}
