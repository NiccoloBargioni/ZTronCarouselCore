import Foundation
import Combine

/// Downloads everything a CDN advertises, once per app version, reporting progress as it goes.
///
/// Intended call site is the app's own launch path — e.g. a root view's `.task { await
/// coordinator.syncIfNeeded() }` — and it's safe to call on every single launch: after the first
/// successful run for a given version it's a single `UserDefaults` read and nothing else.
///
/// "Once per version" is tracked by only recording success — the version is marked synced *after*
/// every advertised asset has been confirmed present, never before or during. An interrupted sync
/// (app killed mid-download, connectivity drop) is therefore retried automatically on the next
/// launch rather than being silently treated as done; already-downloaded assets are detected via
/// `CDNLocalStore.hasAsset(_:)` and skipped, so a retry only re-fetches what's actually still
/// missing, not everything from scratch.
///
/// This is the "single large download early on, not smaller downloads while someone is mid-use"
/// half of the availability guarantee this package aims for. The other half —confirming that
/// guarantee actually holds *right now*, rather than trusting that a sync succeeded at some point
/// in the past — is `verifyFullyAvailable()` and `verifyAndRepair()` below, since "once per app
/// version" says nothing about whether the CDN's content has changed since, independent of any
/// app update.
@MainActor public final class CDNSyncCoordinator: ObservableObject {
    @Published public private(set) var progress: CDNSyncProgress = .idle

    private let cdn: any CDNProviding
    private let localStore: CDNLocalStore
    private let defaults: UserDefaults
    private let appVersionProvider: @Sendable () -> String

    private static let syncedVersionDefaultsKey = "ZTronCarouselCore.CDNSyncCoordinator.lastSyncedVersion"

    /// - Parameters:
    ///   - cdn: The single dependency point for the CDN service in use.
    ///   - localStore: Defaults to the shared instance; override only for testing or if the app
    ///     genuinely needs a second, independent asset store.
    ///   - appVersionProvider: What "a new version" means. Defaults to marketing version + build
    ///     number combined, so a TestFlight build bump (which usually changes the build number but
    ///     not the marketing version) still triggers a re-sync — appropriate for content that
    ///     ships alongside app updates. Override with just `CFBundleShortVersionString` if the
    ///     build number shouldn't matter.
    public init(
        cdn: any CDNProviding,
        localStore: CDNLocalStore = .shared,
        defaults: UserDefaults = .standard,
        appVersionProvider: @escaping @Sendable () -> String = CDNSyncCoordinator.defaultAppVersion
    ) {
        self.cdn = cdn
        self.localStore = localStore
        self.defaults = defaults
        self.appVersionProvider = appVersionProvider
    }

    /// `nonisolated` because it's the *default value* of a `@Sendable () -> String` parameter: as a
    /// member of a `@MainActor` class it would otherwise be main-actor-isolated, and a main-actor
    /// function value can't be converted to a `@Sendable` one. It only reads `Bundle.main`, which
    /// is safe from any context.
    nonisolated public static func defaultAppVersion() -> String {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"

        return "\(shortVersion)+\(buildNumber)"
    }

    public func syncIfNeeded() async {
        let currentVersion = self.appVersionProvider()

        guard self.defaults.string(forKey: Self.syncedVersionDefaultsKey) != currentVersion else {
            self.progress = .upToDate
            return
        }

        do {
            let manifest = try await self.cdn.fetchManifest()

            // Reconciling (rather than a plain `cacheManifest`) means a directory reorganization
            // on the CDN moves the already-downloaded file instead of orphaning it while a
            // duplicate downloads at the new path, and content removed from the CDN gets pruned
            // locally — both compared against whatever manifest was cached before this fetch.
            // Doing this *before* the download pass below matters: it's what lets a migrated
            // file's `hasAsset` check find it at its new location instead of triggering a
            // needless re-download.
            self.localStore.reconcile(newManifest: manifest)

            try await self.downloadEverythingMissing(from: manifest)

            self.defaults.set(currentVersion, forKey: Self.syncedVersionDefaultsKey)
            self.progress = .complete
        } catch {
            self.progress = .failed(reason: String(describing: error))
        }
    }

    /// Checks completeness against a freshly-fetched manifest, regardless of whether this app
    /// version was already marked synced. "Marked synced" only records that a sync succeeded at
    /// some point — it says nothing about whether the CDN's content has since changed underneath
    /// it (a hotfix, a correction, content pulled entirely), which is exactly what
    /// `CDNLocalStore.hasAsset(_:)`'s checksum comparison is for. This is the actual guarantee an
    /// app needs before entering a flow where a mid-use download isn't acceptable — "is everything
    /// really here right now," not "did a sync succeed once."
    ///
    /// Throws only if the manifest fetch itself fails (no connectivity, CDN unreachable); a
    /// successful fetch that finds some assets missing or stale returns them rather than throwing,
    /// since that's an ordinary, expected outcome for the caller to act on, not an error.
    public func verifyFullyAvailable() async throws -> [CDNAsset] {
        let manifest = try await self.cdn.fetchManifest()
        return self.localStore.missingOrStaleAssets(against: manifest)
    }

    /// Forces a fresh reconciliation-and-download pass regardless of whether this app version was
    /// already marked synced, updating `progress` the same way `syncIfNeeded()` does. Meant for a
    /// cadence the app decides for itself — before entering a time-critical flow, on foreground,
    /// a manual "sync now" action — distinct from the automatic once-per-version launch sync.
    /// Deliberately does not touch the once-per-version `UserDefaults` flag either way: this is an
    /// explicit, app-initiated check, not the thing that flag is tracking.
    public func verifyAndRepair() async {
        do {
            let manifest = try await self.cdn.fetchManifest()
            self.localStore.reconcile(newManifest: manifest)
            try await self.downloadEverythingMissing(from: manifest)
            self.progress = .complete
        } catch {
            self.progress = .failed(reason: String(describing: error))
        }
    }

    private func downloadEverythingMissing(from manifest: [CDNAsset]) async throws {
        let total = manifest.count

        guard total > 0 else {
            self.progress = .syncing(fraction: 1, completedCount: 0, totalCount: 0)
            return
        }

        self.progress = .syncing(fraction: 0, completedCount: 0, totalCount: total)
        var completedCount = 0

        for asset in manifest {
            if self.localStore.hasAsset(asset) {
                completedCount += 1
                self.progress = .syncing(
                    fraction: Double(completedCount) / Double(total),
                    completedCount: completedCount,
                    totalCount: total
                )
                continue
            }

            let baseline = completedCount

            let temporaryURL = try await self.cdn.downloadAsset(asset) { [weak self] itemFraction in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    // Only overwrite the published value if this is still the item currently being
                    // counted against: a stale progress callback from a superseded/retried
                    // download racing in after the count has already advanced would otherwise
                    // briefly show the fraction moving backwards. The published `progress` is the
                    // authoritative count here — it is only ever written on the main actor, so
                    // reading it from this main-actor task is race-free, unlike capturing the
                    // loop's mutable `completedCount` local into a `@Sendable` closure (which
                    // Swift 6 rightly rejects as a potential data race).
                    guard case .syncing(_, let publishedCompletedCount, _) = self.progress,
                          publishedCompletedCount == baseline
                    else { return }

                    let overallFraction = (Double(baseline) + itemFraction) / Double(total)
                    self.progress = .syncing(fraction: overallFraction, completedCount: baseline, totalCount: total)
                }
            }

            try self.localStore.store(temporaryURL: temporaryURL, for: asset)

            completedCount += 1
            self.progress = .syncing(
                fraction: Double(completedCount) / Double(total),
                completedCount: completedCount,
                totalCount: total
            )
        }
    }
}
