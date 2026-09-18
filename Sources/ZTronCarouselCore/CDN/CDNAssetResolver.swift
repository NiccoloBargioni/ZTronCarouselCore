import Foundation

/// The network-involving last resort in the fallback chain: app bundle, then the local CDN cache
/// directory (both synchronous — see `CDNLocalStore.existingLocalURL`), then, only if both of
/// those missed, this.
///
/// A plain `Sendable` value rather than an actor: it holds no mutable state of its own (all the
/// state that actually needs protecting — the cached manifest — already lives behind
/// `CDNLocalStore`'s own synchronization), so there's nothing here an actor would be isolating.
public struct CDNAssetResolver: Sendable {
    /// The one shared configuration point every consumer (`BasicImagePage`, `ZTronSVGView`, and
    /// any future one) reads from, rather than each holding its own separate static property.
    /// Install this once at launch, before constructing any carousel content:
    /// `CDNAssetResolver.installed = CDNAssetResolver(cdn: MyProvider(...))`. Left `nil` by
    /// default, so an app that never sets it sees no behavior change beyond what's already
    /// described for a genuinely missing asset. `nonisolated(unsafe)` for the same reason as other
    /// one-shot launch-time configuration in this package: set once, before any read, never
    /// mutated concurrently with a read after that.
    nonisolated(unsafe) public static var installed: CDNAssetResolver? = nil

    private let cdn: any CDNProviding
    private let localStore: CDNLocalStore

    public init(cdn: any CDNProviding, localStore: CDNLocalStore = .shared) {
        self.cdn = cdn
        self.localStore = localStore
    }

    /// Resolves `identifier` to a local file URL by, in order: consulting an already-cached
    /// manifest entry; if none exists yet, fetching (and caching) the manifest fresh, since this
    /// is likely the first time this launch has needed the network at all; downloading the asset
    /// if found; and returning `nil` if the CDN doesn't have it either, or if anything along the
    /// way fails. Errors are deliberately swallowed into `nil` here — this is a best-effort
    /// fallback for a single piece of UI (e.g. one carousel image), not a context where a caller
    /// is set up to surface a thrown error; call `downloadAsset` directly if that's needed instead.
    public func resolveViaNetwork(identifier: String, candidateExtensions: [String]) async -> URL? {
        var asset = self.localStore.cachedAsset(forIdentifier: identifier)

        if asset == nil {
            guard let manifest = try? await self.cdn.fetchManifest() else { return nil }
            self.localStore.cacheManifest(manifest)
            asset = manifest.first { $0.identifier == identifier }
        }

        guard let asset else { return nil }
        guard candidateExtensions.isEmpty || candidateExtensions.contains(asset.fileExtension) else { return nil }

        // Already present under a path a previous call resolved and stored — no need to
        // re-download. `hasAsset` is synchronous and cheap, so checking here costs nothing.
        if self.localStore.hasAsset(asset) {
            return self.localStore.localURL(for: asset)
        }

        guard let temporaryURL = try? await self.cdn.downloadAsset(asset, progress: { _ in }) else {
            return nil
        }

        guard (try? self.localStore.store(temporaryURL: temporaryURL, for: asset)) != nil else {
            return nil
        }

        return self.localStore.localURL(for: asset)
    }
}
