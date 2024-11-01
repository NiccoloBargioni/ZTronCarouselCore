public final class BasicMediaFactory: MediaFactory, Sendable {
    public func makeVideoPage(for videoDescriptor: ZTronVideoDescriptor) -> (any CountedUIViewController)? {
        return BasicVideoPage(videoDescriptor: videoDescriptor)
    }
    
    public func makeImagePage(for imageDescriptor: ZTronImageDescriptor) -> any CountedUIViewController {
        return BasicImagePage(imageDescriptor: imageDescriptor)
    }
    
    public init() { }
}
