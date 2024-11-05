import UIKit
import SnapKit
import ISVImageScrollView


open class BasicImagePage: UIViewController, UIScrollViewDelegate, CountedUIViewController, Sendable {
    public var pageIndex: Int = 0
    
    public let imageView: UIImageView!
    private var pauseLayoutSubviews: Bool = false
    
    public let scrollView: ISVImageScrollView = {
        let scrollView = ISVImageScrollView()
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 20.0
        scrollView.zoomScale = 1.0
        scrollView.contentOffset = .zero
        scrollView.bouncesZoom = true
        

        return scrollView
    }()
    
    override open func viewDidLayoutSubviews() {
        if !self.pauseLayoutSubviews {
            super.viewDidLayoutSubviews()
            print("\(#function) @ \(String(describing: Self.self))(\(self.pageIndex))")
        }
    }
        

    public init(imageDescriptor: ZTronImageDescriptor) {
        print(#function)
                
        let image = UIImage(named: imageDescriptor.getAssetName())!
        let imageView = UIImageView(image: image)

        self.imageView = imageView

        super.init(nibName: nil, bundle: nil)
        scrollView.delegate = self

        scrollView.imageView = imageView
        self.view.addSubview(scrollView)
        self.view.backgroundColor = UIColor.black

        self.scrollView.snp.makeConstraints { make in
            make.left.top.right.bottom.equalToSuperview()
        }

    }
        
    required public init?(coder: NSCoder) {
        fatalError("Cannot init from storyboard")
    }
    
    public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return self.imageView
    }
    
    override open func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        self.view.layoutIfNeeded()
        self.pauseLayoutSubviews = true
        
        coordinator.animate { _ in
            
        } completion: { _ in
            self.pauseLayoutSubviews = false
            self.view.layoutIfNeeded()
        }
    }
    
}
