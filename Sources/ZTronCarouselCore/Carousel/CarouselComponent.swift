import UIKit
import os

@MainActor
public class CarouselComponent: UIPageViewController, Sendable {
    private var medias: [any VisualMediaDescriptor]
    private let pageFactory: MediaFactory!
    
    private var pageControls: UIPageControl!
    private var lastSeenPageIndex: Int = -1
    
    private let makeVCLock = DispatchSemaphore(value: 1)
    private static let logger: os.Logger = .init(subsystem: "ZTronCarouselCore", category: "CarouselComponent")
    
    public var currentPage: Int {
        return self.pageControls.currentPage
    }
    
    public var numberOfPages: Int {
        return self.medias.count
    }
    
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
    
    public init(
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
    
    override public func viewDidLoad() {
        super.viewDidLoad()
                        
        let pageControls = UIPageControl()
        pageControls.numberOfPages = self.medias.count
        pageControls.addTarget(self, action: #selector(self.pageControlsChanged(_:)), for: .valueChanged)

        
        self.view.addSubview(pageControls)
        
        pageControls.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview().inset(10)
        }
        
        self.pageControls = pageControls
    }
    
    
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
    
    
    private final func _replaceMedia(with other: any VisualMediaDescriptor, at index: Int) {
        if index < 0 || index >= self.medias.count {
        #if DEBUG
            Self.logger.warning("Attempted to replace a media at index \(index) when the valid range is [0,\(self.medias.count))")
        #endif
            return
        }
        
        self.medias[index] = other
        
        if index == self.currentPage {
            let newVC = self.makeViewControllerFor(mediaIndex: index)
            self.viewControllers?.forEach { currentVC in
                guard let currentVC = currentVC as? CountedUIViewController else { return }
                currentVC.dismantle()
            }
            
            self.setViewControllers([newVC], direction: .forward, animated: false)
        }
    }
    
    public final func replaceMedia(with other: any VisualMediaDescriptor, at index: Int) {
        self._replaceMedia(with: other, at: index)
    }
    
    
    public final func replaceAllMedias(with other: [any VisualMediaDescriptor]) {
        assert(other.count > 0)
        
        Task(priority: .userInitiated) { @MainActor in
            self.pageControls.numberOfPages = other.count
            self.pageControls.currentPage = 0
        }
        
        self.medias = other
        
        let newVC = self.makeViewControllerFor(mediaIndex: 0)
        
        self.viewControllers?.forEach { currentVC in
            guard let currentVC = currentVC as? CountedUIViewController else { return }
            currentVC.dismantle()
        }
        
        self.setViewControllers(
            [newVC],
            direction: self.lastSeenPageIndex > 0 ? .reverse : .forward,
            animated: self.lastSeenPageIndex > 0
        )
        
        self.lastSeenPageIndex = 0
    }
}

extension CarouselComponent: UIPageViewControllerDataSource {
    
    public func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {

        guard let vc = viewController as? CountedUIViewController else { return nil }
                
        let n = (vc.pageIndex - 1 + medias.count) % medias.count

        
        let newVC = self.makeViewControllerFor(mediaIndex: n)
        newVC.loadViewIfNeeded()
        
        return newVC
    }
    
    public func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {

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
    public func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        
        Task(priority: .userInitiated) { @MainActor in
            self.pageControls.currentPage = (self.viewControllers?.first as? CountedUIViewController)?.pageIndex ?? -1
        }
        
        previousViewControllers.forEach { controller in
            guard let controller = (controller as? any CountedUIVideoPageController) else { return }
            controller.dismantle()
        }
    }
}


