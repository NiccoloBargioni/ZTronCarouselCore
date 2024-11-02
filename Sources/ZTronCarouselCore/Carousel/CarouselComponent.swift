import UIKit
import ZTronObservation

internal class CarouselComponent: UIPageViewController, Sendable {
    private let medias: [any VisualMediaDescriptor]
    private let pageFactory: MediaFactory!
    
    private var pageControls: UIPageControl!
    private var lastSeenPageIndex: Int = -1
    
    private let makeVCLock = DispatchSemaphore(value: 1)
    
    override public var dataSource: (any UIPageViewControllerDataSource)? {
        willSet {
            guard newValue != nil else { return }
            
            let firstVC = self.makeViewControllerFor(mediaIndex: 0)
            self.setViewControllers([firstVC], direction: .forward, animated: false)
        }
        
        didSet {
            if dataSource == nil {
                // TODO: Show skeleton
            } else {
                // TODO: Hide skeleton
            }
        }
    }
    
    internal init(
        with pageFactory: MediaFactory = BasicMediaFactory(),
        medias: [any VisualMediaDescriptor]
    ) {
        self.medias = medias
        self.pageFactory = pageFactory
        super.init(transitionStyle: .scroll, navigationOrientation: .horizontal, options: nil)
        
        self.delegate = self
        self.dataSource = self
    }
    
    override internal init(
        transitionStyle style: UIPageViewController.TransitionStyle,
        navigationOrientation: UIPageViewController.NavigationOrientation,
        options: [UIPageViewController.OptionsKey : Any]? = nil
    ) {
        fatalError("This initialiser is unavailable for objects of type \(String(describing: Self.self))")
    }
    
    required init?(coder: NSCoder) {
        return nil
    }
    
    override internal func viewDidLoad() {
        super.viewDidLoad()
                        
        let pageControls = UIPageControl()
        pageControls.numberOfPages = 20
        pageControls.addTarget(self, action: #selector(self.pageControlsChanged(_:)), for: .valueChanged)

        
        self.view.addSubview(pageControls)
        
        pageControls.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview().inset(10)
        }
        
        self.pageControls = pageControls
               
        self.dataSource = nil
    }
    
    
    @MainActor
    private final func makeViewControllerFor(mediaIndex: Int) -> any CountedUIViewController {
        assert(mediaIndex >= 0 && mediaIndex < self.medias.count)
        
        var newVC: (any CountedUIViewController)? = nil
        
        switch self.medias[mediaIndex].type {
        case .image:
            newVC = self.pageFactory.makeImagePage(for: self.medias[mediaIndex] as! ZTronImageDescriptor)
        case .video:
            newVC = self.pageFactory.makeVideoPage(for: self.medias[mediaIndex] as! ZTronVideoDescriptor)
        }
        
        
        guard let newVC = newVC else { fatalError("Unable to make page for media \(medias[mediaIndex])") }
        newVC.pageIndex = mediaIndex
        
        return newVC
    }
    
}

extension CarouselComponent: UIPageViewControllerDataSource {
    
    internal func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {

        guard let vc = viewController as? CountedUIViewController else { return nil }
                
        let n = (vc.pageIndex - 1 + medias.count) % medias.count

        
        let newVC = self.makeViewControllerFor(mediaIndex: n)
        newVC.loadViewIfNeeded()
        
        return newVC
    }
    
    internal func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {

        guard let vc = viewController as? (any CountedUIViewController) else { return nil }
                
        let n = (vc.pageIndex + 1) % medias.count
        
        let newVC = self.makeViewControllerFor(mediaIndex: n)
        newVC.loadViewIfNeeded()
                        
        return newVC
    }
    
    @objc private func pageControlsChanged(_ sender: UIPageControl) {
        let newPageIndex = sender.currentPage
        // assert(newPageIndex >= 0 && newPageIndex <= self.medias.count)
        
        assert(self.viewControllers?.count ?? 0  <= 1)
        
        let newVC = self.makeViewControllerFor(mediaIndex: newPageIndex % self.medias.count)
        
        if let vc = self.viewControllers?.first as? any CountedUIVideoPageController {
            vc.dismantle()
        }
        
        self.setViewControllers(
            [newVC],
            direction: self.lastSeenPageIndex < newPageIndex ? .forward : .reverse,
            animated: true
        )
        
        self.lastSeenPageIndex = newPageIndex
    }
}

extension CarouselComponent: UIPageViewControllerDelegate {
    internal func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        
        DispatchQueue.main.async { @MainActor in
            self.pageControls.currentPage = (self.viewControllers?.first as? CountedUIViewController)?.pageIndex ?? -1
        }
        
        previousViewControllers.forEach { controller in
            guard let controller = (controller as? any CountedUIVideoPageController) else { return }
            controller.dismantle()
        }
    }
}


