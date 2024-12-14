import UIKit

public protocol CountedUIViewController: UIViewController {
    var pageIndex: Int { get set }
    var assetDescriptor: (any VisualMediaDescriptor)? { get }
    
    func dismantle() -> Void
}
