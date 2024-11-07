import Foundation
import UIKit

open class ZTronImageDescriptor: VisualMediaDescriptor {
    private(set) public var type: VisualMedia
    private let assetName: String
    private let bundle: Bundle?
    
    public init(assetName: String, in bundle: Bundle? = nil) {
        self.type = .image
        self.assetName = assetName
        self.bundle = bundle
    }
    
    public func getAssetName() -> String {
        return self.assetName
    }
    
    public func getBundle() -> Bundle? {
        return self.bundle
    }
}
