import UIKit

extension UIPageViewController {
    
    func configureZoomHandling(for imagePage: BasicImagePage) {
        imagePage.onZoomStateChanged = { [weak self] isZoomed in
            guard let self = self else { return }
            for view in self.view.subviews {
                if let scrollView = view as? UIScrollView {
                    scrollView.isScrollEnabled = !isZoomed
                }
            }
        }
    }
    
    func removeZoomHandling(for imagePage: BasicImagePage) {
        imagePage.onZoomStateChanged = nil
        
        for view in self.view.subviews {
            if let scrollView = view as? UIScrollView {
                scrollView.isScrollEnabled = true
            }
        }
    }
}
