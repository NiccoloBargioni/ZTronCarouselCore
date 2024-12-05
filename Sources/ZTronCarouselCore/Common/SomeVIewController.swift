import UIKit

public final class IOS15LayoutLimitingView: UIView {
    internal var _shouldLayout: Bool = true
    
    override public func layoutSubviews() {
        if #unavailable(iOS 16) {
            guard _shouldLayout else { return }
        }
            
        super.layoutSubviews()
    }
    
    public final func shouldLayout() -> Bool {
        return self._shouldLayout
    }
}


open class IOS15LayoutLimitingViewController: UIViewController, CountedUIViewController {
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
            view._shouldLayout = false
        }
        
    }
    
    public final func onRotationCompletion() {
        if let view = self.view as? IOS15LayoutLimitingView {
            view._shouldLayout = true
        }

        self.view.setNeedsLayout()
    }

}
