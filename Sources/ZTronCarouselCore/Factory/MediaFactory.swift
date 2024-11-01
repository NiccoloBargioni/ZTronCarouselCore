@MainActor public protocol MediaFactory: Sendable {
    func makeVideoPage(for videoDescriptor: ZTronVideoDescriptor) -> (any CountedUIViewController)?
    func makeImagePage(for imageDescriptor: ZTronImageDescriptor) -> CountedUIViewController
}
