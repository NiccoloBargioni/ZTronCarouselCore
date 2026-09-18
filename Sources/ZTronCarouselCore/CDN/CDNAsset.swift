import Foundation

/// One entry in a CDN's manifest: everything needed to find, download, verify, and place a single
/// downloadable resource. Every other type in this subsystem — the sync coordinator, the local
/// store, the resolver — operates on this model rather than on any particular CDN's wire format,
/// so a `CDNProviding` conformance's only job is translating its provider's actual response shape
/// into `[CDNAsset]`.
public struct CDNAsset: Sendable, Hashable, Codable {
    /// Stable identifier matching the descriptor API already in use elsewhere in this package —
    /// `VisualMediaDescriptor.getAssetName()` for images and video, or
    /// `PlaceableOutlineDescriptor.getOutlineAssetName()` for an outline's SVG. e.g.
    /// `"bo7.ri.easter.egg.vehytherion.temple.icon"`.
    public let identifier: String

    /// The file extension, without a leading dot — e.g. `"heic"`, `"mp4"`, `"wav"`, `"svg"`.
    public let fileExtension: String

    /// Where this asset's bytes live, relative to the provider's own base URL. Left for the
    /// provider to interpret; `StaticManifestCDNProvider` treats it as a URL path component.
    public let remotePath: String

    /// Human-readable local directory hierarchy — e.g. `["Black Ops 7", "Rex Infernus",
    /// "Vehytherion Temple"]`. Supplied by the CDN because the *server* is the only place that
    /// actually knows what an abbreviated identifier segment like "ri" stands for; deriving that
    /// mapping on the client would mean inventing data I don't have. An empty array means "no
    /// opinion" — `CDNLocalStore` then derives a directory per dot-separated segment of
    /// `identifier` instead, which is uglier but always computable with no CDN round-trip.
    public let localPathComponents: [String]

    /// The file name actually used on disk, without extension. `nil` means "derive one" — the
    /// last dot-separated segment of `identifier` (e.g. `"icon"`), which is often already a
    /// reasonable leaf name even when it isn't spelled out explicitly.
    public let localFileName: String?

    /// Size in bytes, if the CDN can report it — used to weight progress across multiple
    /// downloads by relative size instead of treating every file as equally sized, and as a cheap
    /// (if imperfect) signal for "this looks like the same file" alongside `checksum`.
    public let byteSize: Int?

    /// An opaque content hash or ETag, if available — compared against what was recorded for the
    /// locally stored copy to decide whether re-downloading across an app update is actually
    /// necessary. See `CDNLocalStore.hasAsset(_:)` for the current, intentionally-conservative
    /// state of that comparison.
    public let checksum: String?

    public init(
        identifier: String,
        fileExtension: String,
        remotePath: String,
        localPathComponents: [String] = [],
        localFileName: String? = nil,
        byteSize: Int? = nil,
        checksum: String? = nil
    ) {
        self.identifier = identifier
        self.fileExtension = fileExtension
        self.remotePath = remotePath
        self.localPathComponents = localPathComponents
        self.localFileName = localFileName
        self.byteSize = byteSize
        self.checksum = checksum
    }

    /// The name actually used for the file on disk, without extension: `localFileName` if the
    /// manifest supplied one, else the last dot-separated segment of `identifier`.
    public var resolvedFileName: String {
        if let localFileName {
            return localFileName
        }

        return identifier.split(separator: ".").last.map(String.init) ?? identifier
    }
}
