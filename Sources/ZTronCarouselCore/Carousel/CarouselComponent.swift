import UIKit
import ZTronObservation
import SkeletonView
import os

@MainActor
public class CarouselComponent: UIPageViewController, Sendable, Component {
    public let id: String
    
    private var medias: [any VisualMediaDescriptor]
    private let pageFactory: MediaFactory!
    
    private var pageControls: UIPageControl!
    private var lastSeenPageIndex: Int = -1
    
    private let makeVCLock = DispatchSemaphore(value: 1)
    private static let logger: os.Logger = .init(subsystem: "ZTronCarouselCore", category: "CarouselComponent")
    private(set) public var lastAction: CarouselComponent.LastAction = .ready
    
    nonisolated lazy private var interactionsManager: (any MSAInteractionsManager)? = nil {
        didSet {
            guard let delegate = self.interactionsManager else { return }
            delegate.setup(or: .replace)
        }
        
        willSet {
            guard let delegate = self.interactionsManager else { return }
            delegate.detach(or: .ignore)
        }
    }
    
    public var currentPage: Int {
        return self.pageControls.currentPage
    }
    
    public var currentMediaDescriptor: (any VisualMediaDescriptor)? {
        if self.currentPage >= 0 && self.currentPage < self.medias.count {
            return self.medias[self.currentPage]
        } else {
            return nil
        }
    }
    
    public var numberOfPages: Int {
        return self.medias.count
    }
    
    override public var dataSource: (any UIPageViewControllerDataSource)? {
        didSet {
            if dataSource == nil {
                // TODO: Show skeleton
                self.view.isSkeletonable = true
                self.view.showAnimatedGradientSkeleton()
            } else {
                // TODO: Hide skeleton
                self.view.stopSkeletonAnimation()
                self.view.hideSkeleton()
                
                if self.medias.count > 0 {
                    let firstVC = self.makeViewControllerFor(mediaIndex: 0)
                    self.setViewControllers([firstVC], direction: .forward, animated: false)
                } else {
                    self.setViewControllers([self.makePlaceholder()], direction: .reverse, animated: false)
                }
            }
        }
    }
    
    public init(
        with pageFactory: MediaFactory = BasicMediaFactory(),
        medias: [any VisualMediaDescriptor]
    ) {
        self.id = "carousel"
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
    
    
    private final func makePlaceholder() -> any CountedUIViewController {
        let newVC = BasicMediaFactory().makeImagePage(for: .init(assetName: "placeholder", in: .module))
        newVC.pageIndex = 0
        
        Task(priority: .userInitiated) { @MainActor in
            self.pageControls.currentPage = 0
        }
        
        return newVC
    }
    
    
    private final func _replaceMedia(with other: any VisualMediaDescriptor, at index: Int, shouldReplaceViewController: Bool = true) {
        if index < 0 || index >= self.medias.count {
        #if DEBUG
            Self.logger.warning("Attempted to replace a media at index \(index) when the valid range is [0,\(self.medias.count))")
        #endif
            return
        }
        
        self.medias[index] = other
        
        if shouldReplaceViewController {
            if index == self.currentPage {
                let newVC = self.makeViewControllerFor(mediaIndex: index)
                self.viewControllers?.forEach { currentVC in
                    guard let currentVC = currentVC as? CountedUIViewController else { return }
                    currentVC.dismantle()
                }
                
                self.setViewControllers([newVC], direction: .forward, animated: false)
                self.lastAction = .replacedCurrentMedia
                self.pushNotification()
            }
        } else {
            self.lastAction = .replacedCurrentDescriptor
            self.pushNotification()
        }
    }
    
    public final func replaceMedia(with other: any VisualMediaDescriptor, at index: Int, shouldReplaceViewController: Bool = true) {
        self._replaceMedia(with: other, at: index, shouldReplaceViewController: shouldReplaceViewController)
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
        self.lastAction = .replacedAllMedias
        self.pushNotification()
    }
    
    nonisolated public func getDelegate() -> (any ZTronObservation.InteractionsManager)? {
        return self.interactionsManager
    }
    
    nonisolated public func setDelegate(_ interactionsManager: (any ZTronObservation.InteractionsManager)?) {
        guard let interactionsManager = interactionsManager as? MSAInteractionsManager else {
            if interactionsManager == nil {
                self.interactionsManager = nil
            } else {
                fatalError("Expected interactionsManager of type \(String(describing: MSAInteractionsManager.self)) @ \(#function) in \(#file).")
            }
            
            return
        }
        
        self.interactionsManager = interactionsManager
    }
    
    
    nonisolated private func pushNotification() {
        Task(priority: .userInitiated) {
            self.getDelegate()?.pushNotification(eventArgs: .init(source: self))
        }
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
    
    @MainActor @objc private func pageControlsChanged(_ sender: UIPageControl) {
        let newPageIndex = sender.currentPage
        // assert(newPageIndex >= 0 && newPageIndex <= self.medias.count)
        
        assert(self.viewControllers?.count ?? 0  <= 1)
        
        let newVC = self.makeViewControllerFor(mediaIndex: newPageIndex % self.medias.count)
        
        if let vc = self.viewControllers?.first as? any CountedUIViewController {
            vc.dismantle()
        }
        
        self.setViewControllers(
            [newVC],
            direction: self.lastSeenPageIndex < newPageIndex ? .forward : .reverse,
            animated: true
        )
        
        self.lastAction = .pageChanged
        self.pushNotification()
        
        self.lastSeenPageIndex = newPageIndex
    }
    
    public enum LastAction: Sendable {
        case ready
        case replacedAllMedias
        case replacedCurrentMedia
        case replacedCurrentDescriptor
        case pageChanged
    }
}

extension CarouselComponent: UIPageViewControllerDelegate {
    public func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        
        Task(priority: .userInitiated) { @MainActor in
            self.pageControls.currentPage = (self.viewControllers?.first as? CountedUIViewController)?.pageIndex ?? -1
        }

        
        if let previousVisibleController = previousViewControllers.first as? CountedUIViewController {
            if previousVisibleController.pageIndex != self.pageControls.currentPage {
                previousViewControllers.forEach { controller in
                    guard let controller = (controller as? any CountedUIViewController) else { return }
                    controller.dismantle()
                }
            }
        } else {
            // ViewControllers was empty
            Task(priority: .userInitiated) { @MainActor in
                self.pageControls.currentPage = (self.viewControllers?.first as? CountedUIViewController)?.pageIndex ?? -1
            }
        }
    }
}


