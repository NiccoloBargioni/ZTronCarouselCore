import UIKit

public final class IOS15LayoutLimitingView: UIView {
    internal var shouldLayout: Bool = true
    
    override public func layoutSubviews() {
        if #unavailable(iOS 16) {
            guard shouldLayout else { return }
        }
            
        super.layoutSubviews()
    }
}


open class SomeViewController: UIViewController, CountedUIViewController {
    public var pageIndex: Int = .zero
    
    public func dismantle() {
        
    }
    
    
    override public func loadView() {
        view = IOS15LayoutLimitingView(frame: .init(x: 0, y: 0, width: 400, height: 700))
    
        
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }
    
    override open func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        self.view.layoutSubviews()
        if let view = self.view as? IOS15LayoutLimitingView {
            view.shouldLayout = false
        }
        
    }
    
    public final func onRotationCompletion() {
        if let view = self.view as? IOS15LayoutLimitingView {
            view.shouldLayout = true
        }

        self.view.setNeedsLayout()
    }

}
