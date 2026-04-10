import UIKit
import SnapKit
import ISVImageScrollView


open class BasicImagePage: IOS15LayoutLimitingViewController, Sendable {
    public let imageView: UIImageView!
    
    public let scrollView: ISVImageScrollView = {
        let scrollView = ISVImageScrollView()
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 20.0
        scrollView.zoomScale = 1.0
        scrollView.contentOffset = .zero
        scrollView.bouncesZoom = true
        

        return scrollView
    }()
        
    private static let supportedImageFormats: [String] = [ "heic", "png", "jpg", "jpeg"]
    private var isCurrentlyZoomed: Bool = false
    public var onZoomStateChanged: ((Bool) -> Void)?


    public init(imageDescriptor: ZTronImageDescriptor) {
        guard let image = Self.attemptFetchingImage(imageDescriptor) else {
            fatalError("Unable to fetch image \(imageDescriptor.getAssetName()) in \(String(describing: imageDescriptor.getBundle())). Make sure the image either exists in assets catalog or bundle resources with .png/.jpg/.jpeg/.heic format.")
        }
        let imageView = UIImageView(image: image)

        self.imageView = imageView

        super.init(nibName: nil, bundle: nil)
        self.scrollView.delegate = self

        scrollView.imageView = imageView
        self.view.addSubview(scrollView)

        self.scrollView.snp.makeConstraints { make in
            make.left.top.right.bottom.equalToSuperview()
        }

        super.assetDescriptor = imageDescriptor
    }
        
    required public init?(coder: NSCoder) {
        fatalError("Cannot init from storyboard")
    }

    override open func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        coordinator.animate { _ in

        } completion: { _ in
            super.onRotationCompletion()
        }
    }

    
    private static func attemptFetchingImage(_ descriptor: ZTronImageDescriptor) -> UIImage? {
        if let imageInAssetsCatalog = UIImage(named: descriptor.getAssetName(), in: descriptor.getBundle(), with: nil) {
            return imageInAssetsCatalog
        } else {
            for format in Self.supportedImageFormats {
                if let imageWithFormatInBundle = UIImage(named: descriptor.getAssetName().appending(".".appending(format)), in: descriptor.getBundle(), with: nil) {
                    return imageWithFormatInBundle
                }
            }
            return nil
        }
    }
}


extension BasicImagePage: UIScrollViewDelegate {
    public func scrollViewDidZoom(_ scrollView: UIScrollView) {
        let isZoomed = scrollView.zoomScale > 1.0
        if isZoomed != self.isCurrentlyZoomed {
            self.isCurrentlyZoomed = isZoomed
            self.onZoomStateChanged?(isZoomed)
        }
    }
    
    
    public func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        let isZoomed = scrollView.zoomScale > 1.0
        if isZoomed != self.isCurrentlyZoomed {
            self.isCurrentlyZoomed = isZoomed
            self.onZoomStateChanged?(isZoomed)
        }
    }
    
    
    public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return self.imageView
    }
}
