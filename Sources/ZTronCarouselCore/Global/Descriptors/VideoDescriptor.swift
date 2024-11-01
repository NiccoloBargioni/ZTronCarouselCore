import SwiftUI

open class ZTronVideoDescriptor: VisualMediaDescriptor, CustomStringConvertible {
    public var description: String
    
    private(set) public var type: VisualMedia
    private let assetName: String
    private(set) public var format: String
    
    public init(assetName: String, withExtension: String) {
        self.type = .video
        self.format = withExtension
        self.assetName = assetName
        
        self.description = "video: \(assetName).\(withExtension)"
    }
    
    public final func getAssetName() -> String {
        return self.assetName
    }
    
    public func getExtension() -> String {
        return self.format
    }
}

