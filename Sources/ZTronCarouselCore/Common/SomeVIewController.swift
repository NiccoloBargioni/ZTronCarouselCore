import UIKit

public final class CustomView: UIView {
    internal var shouldLayout: Bool = true
    
    override public func layoutSubviews() {
        guard shouldLayout else { return }
        
        super.layoutSubviews()
    }
}


open class SomeViewController: UIViewController, CountedUIViewController {
    public var pageIndex: Int = .zero
    
    public func dismantle() {
        
    }
    
    
    override public func loadView() {
        view = CustomView(frame: .init(x: 0, y: 0, width: 400, height: 700))
    
        
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }
    
    override open func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        self.view.layoutSubviews()
        if let view = self.view as? CustomView {
            view.shouldLayout = false
        }
        
    }
    
    public final func onRotationCompletion() {
        if let view = self.view as? CustomView {
            view.shouldLayout = true
        }

        self.view.setNeedsLayout()
    }

}
