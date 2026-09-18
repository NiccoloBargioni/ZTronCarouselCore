import Foundation

/// The single point of change for which CDN service backs this app. Everything else in this
/// subsystem — `CDNSyncCoordinator`, `CDNAssetResolver`, `CDNLocalStore` — depends only on this
/// protocol, never on a specific provider's request shape, response schema, or SDK. Swapping
/// providers means writing one new conformance; nothing else in the sync/resolve/storage pipeline
/// needs to change.
public protocol CDNProviding: Sendable {
    /// Everything the CDN currently advertises. Called once per bulk sync (`CDNSyncCoordinator`),
    /// and again by `CDNAssetResolver`'s on-demand fallback the first time it needs an asset with
    /// no locally cached manifest entry yet.
    func fetchManifest() async throws -> [CDNAsset]

    /// Downloads one asset's bytes to a temporary local file, reporting fractional progress in
    /// `0...1` as bytes arrive whenever the underlying transport can report it — if it can't,
    /// callers should still expect at least one call with `1.0` on completion. The returned URL is
    /// a temporary location; the caller (`CDNLocalStore.store(temporaryURL:for:)`) is responsible
    /// for moving it into its final, permanent place.
    func downloadAsset(_ asset: CDNAsset, progress: @escaping @Sendable (Double) -> Void) async throws -> URL
}
