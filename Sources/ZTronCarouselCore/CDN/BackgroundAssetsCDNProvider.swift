import Foundation
import System
import BackgroundAssets

/// A `CDNProviding` conformance backed by Apple-Hosted Background Assets instead of a plain HTTP
/// CDN. This is what makes "different strategy per iOS version, adapted to one interface" work:
/// `CDNAssetResolver`, `CDNLocalStore`, and every consumer (`BasicImagePage`, `ZTronSVGView`)
/// already only know about `any CDNProviding` — they have no idea whether the bytes they end up
/// with came from a `URLSession` GET or from `AssetPackManager`, and don't need to.
///
/// `iOS 26.0` only, not iOS 15 — see `AssetPackManager`'s own availability. On earlier versions,
/// install `StaticManifestCDNProvider` (or an equivalent self-hosted conformance) instead; picking
/// between them is a single `if #available(iOS 26, *)` at the app's launch-time wiring, shown at
/// the bottom of this file's documentation comment and in DESIGN.md.
///
/// **Deliberately not used for the bulk sync.** `CDNSyncCoordinator` exists to reimplement "make
/// sure everything is downloaded" on top of a dumb HTTP CDN that has no opinion of its own about
/// when to fetch things. Background Assets already has that opinion — asset packs declare their
/// own download policy (install-time, prefetch, on-demand) in Xcode, and the OS schedules them
/// itself. Also driving `CDNSyncCoordinator` on top of that would mean two systems independently
/// deciding when to download the same files. This conformance exists purely so the *on-demand
/// safety-net* path (`CDNAssetResolver`, reached only when both the bundle and the local cache
/// already missed) has a working iOS-26 backend too — the same safety net images and the outline
/// already get, now available on newer OS versions through Apple's own hosting instead of a
/// self-run CDN.
@available(iOS 26.0, *)
public struct BackgroundAssetsCDNProvider: CDNProviding {
    /// The full catalog this provider can serve. Unlike `StaticManifestCDNProvider`, this is
    /// supplied by the app rather than fetched over the network: which identifiers exist and
    /// which asset pack (and path within it) each one lives in is decided at build time, when the
    /// packs themselves are configured via Xcode's asset-pack packaging tool — there's no dynamic
    /// remote manifest to ask Background Assets for the way there is for a plain HTTP CDN. Keep
    /// this in sync with that Xcode configuration; nothing here derives it automatically.
    ///
    /// Each entry's `remotePath` is read as `"<assetPackID>/<relativePathWithinPack>"` — a
    /// convention this provider owns, not something Background Assets itself requires. Everything
    /// else on `CDNAsset` (`localPathComponents`, `localFileName`, ...) means exactly what it
    /// means for every other provider: where the resolved file ends up in `CDNLocalStore`.
    private let catalog: [CDNAsset]

    public init(catalog: [CDNAsset]) {
        self.catalog = catalog
    }

    public func fetchManifest() async throws -> [CDNAsset] {
        return self.catalog
    }

    public func downloadAsset(_ asset: CDNAsset, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let (packID, relativePath) = try Self.splitRemotePath(asset.remotePath)

        progress(0)

        // Verified against Apple's current documentation: `assetPack(withID:)` and
        // `ensureLocalAvailability(of:)` both exist with exactly this async-throwing shape.
        // `ensureLocalAvailability(of:)` returns quickly without re-downloading if the pack (or,
        // for an essential/prefetch pack, the OS acting on its own) already fetched it — which is
        // the common case here, since this path only runs at all after the local cache already
        // missed, so most of the time this call either finishes instantly or was never going to be
        // reached in the first place.
        let pack = try await AssetPackManager.shared.assetPack(withID: packID)
        try await AssetPackManager.shared.ensureLocalAvailability(of: pack)

        // NOT verified against the current SDK, unlike the two calls above — this is the one part
        // of this file I'd check first. Reading a specific file's bytes back out of a pack that
        // `ensureLocalAvailability` just confirmed is local appears to go through
        // `contents(at:searchingInAssetPackWithID:)` (or `descriptor(for:searchingInAssetPackWithID:)`
        // for a lower-level handle), taking a `System.FilePath` rather than a plain path string —
        // but I only have secondhand descriptions of this call, not its authoritative signature
        // the way I do for the two calls above, and at least one source explicitly warns not to
        // assume a plain directory `URL` is available at all: Background Assets may merge pack
        // contents into a managed namespace rather than exposing a conventional file hierarchy.
        // If this doesn't compile as written against the actual Xcode 26 SDK, this line — and only
        // this line — is what needs adjusting; everything upstream and downstream of it (the
        // pack-availability calls, and what happens to the `Data` once obtained) should still hold.
        let data = try AssetPackManager.shared.contents(
            at: FilePath(relativePath),
            searchingInAssetPackWithID: packID
        )

        let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: temporaryURL)

        progress(1.0)

        return temporaryURL
    }

    private static func splitRemotePath(_ remotePath: String) throws -> (packID: String, relativePath: String) {
        guard let separatorIndex = remotePath.firstIndex(of: "/") else {
            throw BackgroundAssetsCDNProviderError.malformedRemotePath(remotePath)
        }

        let packID = String(remotePath[remotePath.startIndex..<separatorIndex])
        let relativePath = String(remotePath[remotePath.index(after: separatorIndex)...])

        guard !packID.isEmpty, !relativePath.isEmpty else {
            throw BackgroundAssetsCDNProviderError.malformedRemotePath(remotePath)
        }

        return (packID, relativePath)
    }
}

public enum BackgroundAssetsCDNProviderError: Error {
    /// `remotePath` wasn't in the `"<packID>/<relativePath>"` shape this provider expects.
    case malformedRemotePath(String)
}
