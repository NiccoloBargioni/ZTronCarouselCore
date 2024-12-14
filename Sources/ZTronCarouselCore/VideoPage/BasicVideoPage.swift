import UIKit

import AVFoundation
import CoreMedia

import SnapKit
import ZTronVideoPlayer

// FIXME: Probably seeking needs better accuracy?
// FIXME: Automatically pause the overlay when the app fades to background
public class BasicVideoPage: UIViewController, CountedUIVideoPageController {
    private(set) public var assetDescriptor: (any VisualMediaDescriptor)?
    
    private final let uiOverlayColor: UIColor = UIColor(cgColor: CGColor(red: 0, green: 0, blue: 0, alpha: 0.4))
    
    internal var video: URL
    internal var videoPlayer: TinyVideoPlayer
    internal var videoProjectionView: TinyVideoProjectionView!
    internal var isOverlayShowing: Bool = true
    internal var wasPlayingBeforeDrag: Bool = false
    internal var videoDuration: Float
    internal var videoPlaybackRate: Float = 1.0
    internal var delegate: (any VideoPageDelegate)? = nil {
        didSet {
            if self.isOverlayShowing {
                self.delegate?.overlayDidShow?(videoPage: self)
            } else {
                self.delegate?.overlayDidHide?(videoPage: self)
            }
        }
    }
    
    public var pageIndex: Int = 0
    
    internal var currentSkipArrowsSide: Side = .right

    internal var videoOverlayView: (any UIVideoOverlay)!
    internal var skipArrows: UIVideoOverlaySkipArrows!
    
    
    public init?(
        videoDescriptor: ZTronVideoDescriptor,
        overlayFactory: any UIVideoOverlayFactory = BasicVideoOverlayFactory()
    ) {
        print("\(#function)")
        guard let bundleURL = Bundle.main.url(forResource: videoDescriptor.getAssetName(), withExtension: videoDescriptor.getExtension()) else { return nil }
        
        self.pageIndex = -1
        self.video = bundleURL
        
        self.videoPlayer = TinyVideoPlayer(resourceUrl: bundleURL)
        
        self.videoDuration = 0.0
                
        super.init(nibName: nil, bundle: nil)
        
        videoPlayer.delegate = self
        let theDuration = self.duration()
        
        self.videoOverlayView = overlayFactory.makeOverlay(duration: theDuration)
        self.videoDuration = Float(theDuration)
        
        
        videoOverlayView.delegate = self
        
        self.assetDescriptor = videoDescriptor
    }
    
    required override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        fatalError("init from storyboard unsupported")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init from coder unsupported")
    }
    
    
    override public func viewDidLoad() {
        print("\(#function)")

        super.viewDidLoad()
        
        let videoView = videoPlayer.generateVideoProjectionView()
        self.videoProjectionView = videoView
        
        self.view.addSubview(videoView)
        
        videoView.snp.makeConstraints { make in
            make.left.top.right.bottom.equalToSuperview()
        }
                
        videoView.addSubview(self.videoOverlayView)
        videoOverlayView.snp.makeConstraints { make in
            make.top.right.bottom.left.equalToSuperview()
        }
        
        let arrows = UIVideoOverlaySkipArrows()
        
        self.view.addSubview(arrows)
        
        arrows.snp.makeConstraints { make in
            make.left.equalTo(self.view.snp.centerX).offset(self.view.bounds.size.width / 4.0)
            make.centerY.equalToSuperview()
        }
    
        self.skipArrows = arrows
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.viewDidFadeToBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.viewWillTransitionToForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.videoOverlayView.viewDidLayoutSubviews()
    }
    

    private func duration() -> Float64 {
        let asset = AVAsset(url: self.video)

        let duration = asset.duration
        let durationTime = CMTimeGetSeconds(duration)

        return durationTime
    }
    
    
    // MARK: Foreground and background
    @objc internal func viewDidFadeToBackground() {
        self.videoOverlayView.pause()
    }
    
    @objc internal func viewWillTransitionToForeground() {
        self.videoOverlayView.summonOverlay()
    }
    
    
    internal func pointArrows(to side: Side) {
        if side != currentSkipArrowsSide {
            self.skipArrows.snp.removeConstraints()

            if side == .right {
                self.skipArrows.snp.makeConstraints { make in
                    make.left.equalTo(self.view.snp.centerX).offset(self.view.bounds.size.width / 4.0)
                    make.centerY.equalToSuperview()
                }
                
                self.skipArrows.layer.transform = CATransform3DMakeScale(1, 1, 1)
            } else {
                self.skipArrows.snp.makeConstraints { make in
                    make.right.equalTo(self.view.snp.centerX).offset(-1 * self.view.bounds.size.width / 4.0)
                    make.centerY.equalToSuperview()
                }
                
                self.skipArrows.layer.transform = CATransform3DMakeScale(-1, 1, 1)
            }
        }
        
        self.currentSkipArrowsSide = side
    }
    
    public func dismantle() {
        if self.videoOverlayView.isPlaying {
            self.videoPlayer.pause()
            self.videoOverlayView.pause()
        }
    }
}



@objc public protocol VideoPageDelegate: NSObjectProtocol {
    @objc optional func overlayDidShow(videoPage: BasicVideoPage)
    @objc optional func overlayDidHide(videoPage: BasicVideoPage)
}
