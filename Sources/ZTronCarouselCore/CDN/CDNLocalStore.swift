import Foundation
import CryptoKit

/// Owns where CDN-downloaded assets live on disk, and the mapping from a `CDNAsset` (or a bare
/// identifier, before any manifest has ever been fetched) to that location.
///
/// Two lookup paths exist because path-pretty-printing genuinely depends on data only the CDN
/// has. Once at least one manifest has been fetched (by a bulk sync, or by an earlier on-demand
/// fallback), it's cached here as a small JSON file alongside the assets themselves, so later
/// lookups — including on a future launch — can resolve `identifier -> pretty local path` fully
/// offline. Before that's ever happened (a cold on-demand fallback for an asset this launch has
/// never seen a manifest for), there's nothing to consult, so paths are derived mechanically from
/// the identifier's own dot-separated segments instead — uglier, but always computable without a
/// network round trip, and safe to use as a location to *write* to as well as read from.
public final class CDNLocalStore: @unchecked Sendable {
    public static let shared = CDNLocalStore()

    private let baseDirectory: URL
    private let manifestCacheURL: URL
    private let checksumCacheURL: URL

    private let stateQueue = DispatchQueue(label: "CDNLocalStore.state", attributes: .concurrent)
    nonisolated(unsafe) private var cachedManifestByIdentifier: [String: CDNAsset] = [:]
    /// The checksum actually recorded for the file currently on disk at each identifier's
    /// location, as computed by `computeChecksum` at the moment it was written — not necessarily
    /// the same as whatever the current manifest claims, which is exactly what makes a comparison
    /// between the two meaningful. Persisted separately from the manifest cache since its entries
    /// only change when a file is actually written, not on every manifest fetch.
    nonisolated(unsafe) private var localChecksumsByIdentifier: [String: String] = [:]

    /// How to compute a comparable content hash for a downloaded file, used to detect a remote
    /// file that changed without its identifier changing (same name, different bytes). Defaults
    /// to lowercase-hex SHA-256 over the file's contents. Override this if your CDN's `checksum`
    /// field uses a different representation (an MD5, an S3 multipart-upload ETag, a CRC) — the
    /// two sides need to actually be comparable strings for staleness detection to mean anything;
    /// there's no way for this type to guess your CDN's convention on its own.
    private let computeChecksum: @Sendable (URL) throws -> String

    /// Defaults to `Library/Caches/CDNAssets`. These files are re-downloadable by definition, so
    /// `Caches` is the semantically correct place for them: the OS is free to purge them under
    /// storage pressure without asking, they don't bloat the user's iCloud/iTunes backup with
    /// content that can just be fetched again, and none of that costs anything extra here, because
    /// the same three-step fallback chain this whole feature exists for (bundle -> local cache ->
    /// network) already makes the app robust to a purge: the next time a purged asset is needed,
    /// it transparently re-downloads. Pass a `Documents`-rooted URL instead if the assets should
    /// survive backups and be visible in the Files app — that trade-off cuts the other way (they
    /// count against backup size, but never disappear without the user deleting them explicitly).
    public init(
        baseDirectory: URL? = nil,
        computeChecksum: @escaping @Sendable (URL) throws -> String = CDNLocalStore.sha256Hex
    ) {
        let resolvedBase = baseDirectory ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CDNAssets", isDirectory: true)

        self.baseDirectory = resolvedBase
        self.manifestCacheURL = resolvedBase.appendingPathComponent("manifest.json", isDirectory: false)
        self.checksumCacheURL = resolvedBase.appendingPathComponent("local-checksums.json", isDirectory: false)
        self.computeChecksum = computeChecksum

        try? FileManager.default.createDirectory(at: resolvedBase, withIntermediateDirectories: true)
        self.loadCachedManifest()
        self.loadLocalChecksums()
    }

    /// The default `computeChecksum` implementation: lowercase-hex SHA-256 over the whole file.
    /// `.mappedIfSafe` avoids reading a large video fully into memory just to hash it.
    public static func sha256Hex(of fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func loadCachedManifest() {
        guard let data = try? Data(contentsOf: self.manifestCacheURL) else { return }
        guard let assets = try? JSONDecoder().decode([CDNAsset].self, from: data) else { return }

        self.stateQueue.sync(flags: .barrier) {
            self.cachedManifestByIdentifier = Dictionary(uniqueKeysWithValues: assets.map { ($0.identifier, $0) })
        }
    }

    private func loadLocalChecksums() {
        guard let data = try? Data(contentsOf: self.checksumCacheURL) else { return }
        guard let checksums = try? JSONDecoder().decode([String: String].self, from: data) else { return }

        self.stateQueue.sync(flags: .barrier) {
            self.localChecksumsByIdentifier = checksums
        }
    }

    /// Called by `CDNSyncCoordinator` after every successful manifest fetch, and by
    /// `CDNAssetResolver`'s on-demand fallback the first time it has to fetch one itself, so
    /// pretty-path resolution keeps working offline on a future launch without needing the network
    /// again purely to re-learn the same mapping.
    ///
    /// This only replaces the cached manifest — it doesn't move or delete anything on disk. Use
    /// `reconcile(newManifest:)` instead when the new manifest should also be reflected in what's
    /// actually stored locally (a directory reorganization, content removed from the CDN); that
    /// calls this internally once it's done, so there's no need to call both.
    public func cacheManifest(_ assets: [CDNAsset]) {
        self.stateQueue.sync(flags: .barrier) {
            self.cachedManifestByIdentifier = Dictionary(uniqueKeysWithValues: assets.map { ($0.identifier, $0) })
        }

        if let data = try? JSONEncoder().encode(assets) {
            try? data.write(to: self.manifestCacheURL, options: .atomic)
        }
    }

    public func cachedAsset(forIdentifier identifier: String) -> CDNAsset? {
        return self.stateQueue.sync {
            self.cachedManifestByIdentifier[identifier]
        }
    }

    /// The deterministic fallback used whenever no cached manifest entry exists yet for an
    /// identifier: one directory per dot-separated segment. Exposed publicly (rather than kept
    /// private) because `existingLocalURL(identifier:candidateExtensions:)` needs it and so does
    /// anything that wants to predict where a not-yet-manifested asset would land.
    public static func mechanicalPathComponents(for identifier: String) -> [String] {
        return identifier.split(separator: ".").map(String.init)
    }

    /// The full local URL for a manifest entry — the entry's own `localPathComponents` /
    /// `resolvedFileName` when it has an opinion, the mechanical derivation otherwise.
    public func localURL(for asset: CDNAsset) -> URL {
        let directoryComponents: [String]

        if !asset.localPathComponents.isEmpty {
            directoryComponents = asset.localPathComponents
        } else {
            // Drop the last segment: it's treated as the file's own name, not another directory
            // level, matching `resolvedFileName`'s own fallback for the same identifier.
            directoryComponents = Array(Self.mechanicalPathComponents(for: asset.identifier).dropLast())
        }

        let directory = directoryComponents.reduce(self.baseDirectory) {
            $0.appendingPathComponent($1, isDirectory: true)
        }

        return directory.appendingPathComponent("\(asset.resolvedFileName).\(asset.fileExtension)", isDirectory: false)
    }

    /// Synchronous existence check — no network involved — used as the second step of the
    /// fallback chain (after the app bundle, before an on-demand network fetch). Prefers a cached
    /// manifest entry's pretty path when one is known, falling back to checking every candidate
    /// extension at the mechanically-derived location otherwise. `candidateExtensions` mirrors
    /// `BasicImagePage`'s own list for images; pass a single-element array for video or SVG, where
    /// the extension is already fixed by the descriptor.
    ///
    /// Deliberately does not do checksum comparison the way `hasAsset(_:)` does: this only ever
    /// consults whatever manifest was last cached, with no way to know here whether the CDN's
    /// content has since changed without asking the network — which is exactly what the network
    /// step this precedes is for. Staleness detection belongs at the moment something actually
    /// asks the CDN what's current, not at a purely local, offline check.
    public func existingLocalURL(identifier: String, candidateExtensions: [String]) -> URL? {
        if let cached = self.cachedAsset(forIdentifier: identifier) {
            let url = self.localURL(for: cached)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        let mechanicalComponents = Self.mechanicalPathComponents(for: identifier)
        let stem = mechanicalComponents.last ?? identifier
        let directory = mechanicalComponents.dropLast().reduce(self.baseDirectory) {
            $0.appendingPathComponent($1, isDirectory: true)
        }

        for ext in candidateExtensions {
            let candidate = directory.appendingPathComponent("\(stem).\(ext)", isDirectory: false)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    /// Whether `asset` is already present locally *and* current: the file exists, and — when the
    /// manifest reports a `checksum` and a local one was recorded for this identifier — the two
    /// match. A same-named file with different bytes (the CDN replaced content without changing
    /// the identifier) is treated as absent, so callers that already skip on `hasAsset` returning
    /// true (`CDNSyncCoordinator`'s sync loop, `CDNAssetResolver`'s "already have it" check) both
    /// pick up a changed file automatically rather than needing their own separate check.
    ///
    /// If no local checksum was ever recorded for this identifier — a file that predates this
    /// capability, or one placed outside `store(temporaryURL:for:)` — there's nothing to compare
    /// against, so this falls back to trusting existence rather than forcing a redundant
    /// re-download of everything the first time this ships.
    public func hasAsset(_ asset: CDNAsset) -> Bool {
        guard FileManager.default.fileExists(atPath: self.localURL(for: asset).path) else {
            return false
        }

        if let remoteChecksum = asset.checksum {
            let localChecksum = self.stateQueue.sync { self.localChecksumsByIdentifier[asset.identifier] }
            if let localChecksum, localChecksum != remoteChecksum {
                return false
            }
        }

        return true
    }

    /// Atomically moves a just-downloaded temporary file into its final location, creating any
    /// missing intermediate directories first and replacing anything already there. Also computes
    /// and records the file's checksum (best-effort — a hashing failure doesn't fail the store
    /// itself, it just leaves nothing for a future `hasAsset` call to compare against for this
    /// identifier, falling back to existence-only for it as described there).
    public func store(temporaryURL: URL, for asset: CDNAsset) throws {
        let destination = self.localURL(for: asset)

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        // Computed before the move, while `temporaryURL` is still guaranteed to point at the
        // complete downloaded file.
        let checksum = try? self.computeChecksum(temporaryURL)

        try FileManager.default.moveItem(at: temporaryURL, to: destination)

        if let checksum {
            self.recordLocalChecksum(checksum, for: asset.identifier)
        }
    }

    private func recordLocalChecksum(_ checksum: String, for identifier: String) {
        let snapshot: [String: String] = self.stateQueue.sync(flags: .barrier) {
            self.localChecksumsByIdentifier[identifier] = checksum
            return self.localChecksumsByIdentifier
        }

        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: self.checksumCacheURL, options: .atomic)
        }
    }

    private func removeLocalChecksum(for identifier: String) {
        let snapshot: [String: String] = self.stateQueue.sync(flags: .barrier) {
            self.localChecksumsByIdentifier.removeValue(forKey: identifier)
            return self.localChecksumsByIdentifier
        }

        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: self.checksumCacheURL, options: .atomic)
        }
    }

    // MARK: - Reconciliation: directory changes and removed content

    /// Reconciles local storage against a freshly-fetched manifest, then makes it the new cached
    /// one (internally calling `cacheManifest(_:)` — no need to call that separately). Two things
    /// happen, both compared against whatever manifest was cached *before* this call:
    ///
    /// - **Directory changes**: if an identifier's file exists locally but the CDN now reports a
    ///   different `localPathComponents`/`localFileName` for it, the file is moved to its new
    ///   location rather than left behind as an orphan while a fresh copy downloads at the new
    ///   path.
    /// - **Removed content**: if an identifier that previously had a local file no longer appears
    ///   in `newManifest` at all, that file is deleted, along with its recorded checksum.
    ///
    /// Call this from a bulk sync, once `newManifest` is known to represent the CDN's complete,
    /// current state — not from the on-demand per-asset fallback (`CDNAssetResolver`), even though
    /// the manifest it fetches is just as complete. There, the fetch is answering "where's this
    /// one missing thing while someone is mid-browse" — reconciling there would mean a single
    /// missing image, purely incidentally, also deleting unrelated files elsewhere in the catalog
    /// as a side effect nobody asked for at that moment. Pruning and migration should only happen
    /// from something explicitly meant to reconcile everything: a bulk sync, or `verifyAndRepair()`.
    @discardableResult
    public func reconcile(newManifest: [CDNAsset]) -> CDNReconciliationSummary {
        let previousManifest = self.stateQueue.sync { self.cachedManifestByIdentifier }
        let newByIdentifier = Dictionary(uniqueKeysWithValues: newManifest.map { ($0.identifier, $0) })

        var migratedCount = 0
        var migrationFailures: [CDNReconciliationSummary.Failure] = []
        var prunedCount = 0
        var pruneFailures: [CDNReconciliationSummary.Failure] = []

        for (identifier, oldAsset) in previousManifest {
            let oldURL = self.localURL(for: oldAsset)
            guard FileManager.default.fileExists(atPath: oldURL.path) else { continue }

            if let newAsset = newByIdentifier[identifier] {
                let newURL = self.localURL(for: newAsset)
                guard newURL != oldURL else { continue }

                do {
                    try FileManager.default.createDirectory(
                        at: newURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    if FileManager.default.fileExists(atPath: newURL.path) {
                        try FileManager.default.removeItem(at: newURL)
                    }
                    try FileManager.default.moveItem(at: oldURL, to: newURL)
                    migratedCount += 1
                } catch {
                    migrationFailures.append(.init(identifier: identifier, reason: String(describing: error)))
                }
            } else {
                do {
                    try FileManager.default.removeItem(at: oldURL)
                    self.removeLocalChecksum(for: identifier)
                    prunedCount += 1
                } catch {
                    pruneFailures.append(.init(identifier: identifier, reason: String(describing: error)))
                }
            }
        }

        self.cacheManifest(newManifest)

        return CDNReconciliationSummary(
            migratedCount: migratedCount,
            migrationFailures: migrationFailures,
            prunedCount: prunedCount,
            pruneFailures: pruneFailures
        )
    }

    // MARK: - Availability guarantee

    /// Every asset in `manifest` that isn't guaranteed available locally right now — either
    /// missing entirely, or present under a name the CDN currently reports different content for
    /// (`hasAsset(_:)`'s checksum comparison). An empty result means everything in `manifest` is
    /// confirmed present without touching the network: the guarantee an app needs before entering
    /// a flow where a mid-use download isn't acceptable, distinct from "a sync completed
    /// successfully at some point," which says nothing about whether the CDN's content has since
    /// changed underneath it.
    public func missingOrStaleAssets(against manifest: [CDNAsset]) -> [CDNAsset] {
        return manifest.filter { !self.hasAsset($0) }
    }

    public func isFullyAvailable(against manifest: [CDNAsset]) -> Bool {
        return self.missingOrStaleAssets(against: manifest).isEmpty
    }
}

/// What `CDNLocalStore.reconcile(newManifest:)` did. Purely informational — nothing currently
/// requires inspecting it — but useful for logging or surfacing in a debug view, since silent
/// pruning of files off a person's device is the kind of thing worth being able to audit.
public struct CDNReconciliationSummary: Sendable {
    public struct Failure: Sendable {
        public let identifier: String
        public let reason: String
    }

    public let migratedCount: Int
    public let migrationFailures: [Failure]
    public let prunedCount: Int
    public let pruneFailures: [Failure]
}
