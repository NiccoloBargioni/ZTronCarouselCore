import Foundation

/// A `CDNProviding` conformance for the common shape of "a manifest JSON file plus the assets
/// themselves at predictable static URLs" — S3 + CloudFront, Cloudflare R2, bunny.net, or honestly
/// any plain web server all fit this shape.
///
/// **This is a template, not a finished integration.** I have no information about which CDN
/// service is actually in use, so the manifest's exact JSON schema and the per-file URL layout
/// below are illustrative placeholders — this file (specifically `fetchManifest`'s decoding, and
/// `downloadAsset`'s URL construction) is exactly the file that should need to change to point
/// this at a real service, and the *only* one: nothing in `CDNSyncCoordinator`, `CDNLocalStore`,
/// or `CDNAssetResolver` needs to know or care.
public struct StaticManifestCDNProvider: CDNProviding {
    private let baseURL: URL
    private let manifestPath: String
    private let urlSession: URLSession

    public init(baseURL: URL, manifestPath: String = "manifest.json", urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.manifestPath = manifestPath
        self.urlSession = urlSession
    }

    public func fetchManifest() async throws -> [CDNAsset] {
        let url = self.baseURL.appendingPathComponent(self.manifestPath)
        let (data, response) = try await self.urlSession.data(from: url)

        try Self.validate(response)

        // Placeholder assumption: the manifest is a JSON array whose objects already match
        // `CDNAsset`'s own `Codable` shape one-to-one. A real CDN's manifest almost certainly
        // looks different (different key names, a wrapper object, snake_case, etc.) — decode into
        // a private DTO type that matches the actual schema and map it to `CDNAsset` here instead;
        // `CDNAsset` itself doesn't need to change either way.
        return try JSONDecoder().decode([CDNAsset].self, from: data)
    }

    public func downloadAsset(_ asset: CDNAsset, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let url = self.baseURL.appendingPathComponent(asset.remotePath)
        return try await Self.download(from: url, progress: progress)
    }

    private static func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw StaticManifestCDNProviderError.badResponse(response)
        }
    }

    /// Delegate-based rather than the newer `URLSession.bytes(for:)` async-sequence API: the
    /// delegate route gives byte-level progress via a well-established, officially-designed
    /// callback (`didWriteData:totalBytesWritten:totalBytesExpectedToWrite:`) and streams straight
    /// to a system-managed temp file. `bytes(for:)`'s `AsyncBytes` is a byte-at-a-time
    /// `AsyncSequence`; iterating it one byte at a time to manually buffer and write is both easy
    /// to get subtly wrong and, for anything video-sized, needlessly slow. Wrapped in
    /// `withCheckedThrowingContinuation` to expose it with the same `async throws` shape as the
    /// rest of this protocol.
    private static func download(from url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadProgressDelegate(onProgress: progress, continuation: continuation)
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            delegate.session = session

            session.downloadTask(with: url).resume()
        }
    }
}

public enum StaticManifestCDNProviderError: Error {
    case badResponse(URLResponse)
}

/// Bridges `URLSessionDownloadDelegate`'s callback shape into a single `async throws -> URL`,
/// reporting progress along the way. One instance per download (each with its own `URLSession`),
/// rather than a single shared delegate demultiplexing many concurrent tasks by `taskIdentifier` —
/// simpler to reason about correctly, at the cost of one extra `URLSession` object per in-flight
/// download, which is immaterial for a background sync downloading a handful of files at a time.
private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private let continuation: CheckedContinuation<URL, Error>

    /// Set immediately after this delegate's `URLSession` is created, so the delegate can
    /// invalidate its own session once the download finishes rather than leaking it — `URLSession`
    /// retains its delegate for the session's lifetime, so something has to explicitly end that.
    var session: URLSession?

    private let resumeLock = NSLock()
    private var didResume = false

    init(onProgress: @escaping @Sendable (Double) -> Void, continuation: CheckedContinuation<URL, Error>) {
        self.onProgress = onProgress
        self.continuation = continuation
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        self.onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // A non-2xx response (e.g. a 404 for a manifest entry pointing at a since-removed file)
        // still reaches this method — the *transfer* succeeded even though the request logically
        // failed — so the status has to be checked here, not just in the completion-with-error path.
        if let httpResponse = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            self.resume(.failure(StaticManifestCDNProviderError.badResponse(downloadTask.response ?? URLResponse())))
            return
        }

        // `location` is only guaranteed to exist until this method returns, so it has to be moved
        // to a stable location synchronously, before doing anything else (including resuming the
        // continuation, which could let the caller race ahead of us).
        let stableURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        do {
            try FileManager.default.moveItem(at: location, to: stableURL)
            self.onProgress(1.0)
            self.resume(.success(stableURL))
        } catch {
            self.resume(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        // Only the failure case needs handling here: success already resumed from
        // `didFinishDownloadingTo` above, and `resume(_:)`'s guard makes a second call harmless
        // even if both fire.
        if let error {
            self.resume(.failure(error))
        }
    }

    private func resume(_ result: Result<URL, Error>) {
        self.resumeLock.lock()
        let alreadyResumed = self.didResume
        self.didResume = true
        self.resumeLock.unlock()

        guard !alreadyResumed else { return }

        switch result {
            case .success(let url):
                self.continuation.resume(returning: url)
            case .failure(let error):
                self.continuation.resume(throwing: error)
        }

        self.session?.finishTasksAndInvalidate()
    }
}
