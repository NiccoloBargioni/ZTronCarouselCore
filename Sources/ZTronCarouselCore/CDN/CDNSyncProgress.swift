import Foundation

/// Progress of a bulk CDN sync. `fraction` inside `.syncing` is always in `0...1` and always at
/// least as granular as `completedCount / totalCount` — satisfying "0, 1/N, 2/N, ..., 1" even for a
/// `CDNProviding` conformance that can't report per-file progress, since `downloadAsset` is still
/// required to call back with `1.0` on completion at minimum. A provider that *can* report
/// intermediate per-byte progress makes `fraction` correspondingly smoother, blending the
/// in-flight item's own fractional progress into the overall number rather than jumping only on
/// whole-file completions.
public enum CDNSyncProgress: Sendable {
    /// Nothing has happened yet this launch.
    case idle
    /// `syncIfNeeded()` ran and found this app version already fully synced; no network activity
    /// occurred.
    case upToDate
    /// A sync is in progress.
    case syncing(fraction: Double, completedCount: Int, totalCount: Int)
    /// Every advertised asset was confirmed present (already local, or freshly downloaded).
    case complete
    /// The sync did not finish. `reason` is the failing error's description, kept as a `String`
    /// rather than the error itself so this type can stay simply `Sendable` — a case meant for
    /// progress UI, not programmatic error handling. The app version is deliberately *not* marked
    /// synced when this happens, so the next launch retries automatically.
    case failed(reason: String)
}

extension CDNSyncProgress: Equatable {
    public static func == (lhs: CDNSyncProgress, rhs: CDNSyncProgress) -> Bool {
        switch (lhs, rhs) {
            case (.idle, .idle), (.upToDate, .upToDate), (.complete, .complete):
                return true
            case (.syncing(let lFraction, let lCompleted, let lTotal), .syncing(let rFraction, let rCompleted, let rTotal)):
                return lFraction == rFraction && lCompleted == rCompleted && lTotal == rTotal
            case (.failed(let lReason), .failed(let rReason)):
                return lReason == rReason
            default:
                return false
        }
    }
}
