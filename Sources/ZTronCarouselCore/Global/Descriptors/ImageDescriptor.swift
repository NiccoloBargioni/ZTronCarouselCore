import Foundation

open class ZTronImageDescriptor: VisualMediaDescriptor {
    private(set) public var type: VisualMedia
    private let assetName: String
    
    public init(assetName: String) {
        self.type = .image
        self.assetName = assetName
    }
    
    public func getAssetName() -> String {
        return self.assetName
    }
}
