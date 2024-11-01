import UIKit
import SnapKit

open class UIVideoOverlayView: UIView, UIVideoOverlay {
    public final let progressIndicatorColor: CGColor = CGColor(red: 128.0/255.0, green: 0, blue: 0, alpha: 1.0)
    public final let uiOverlayColor: UIColor = UIColor(cgColor: CGColor(red: 0, green: 0, blue: 0, alpha: 0.4))
    public final let thumbRadius: CGFloat = 15.0
    public final let overlayUpTime: CGFloat = 2.0
    public final let skipTimeAbs: Float = 3.0
    
    open var playButton: UIButton!
    open var settingsButton: UIButton!
    open var progressThumb: UIView!
    open var progressLabel: UILabel!
    open var bottomBar: UIView!
    open var skipArrows: UIVideoOverlaySkipArrows!
    
    public var currentSkipArrowsSide: Side = .right
    
    public final let duration: Float64
    public var currentSpeed: Float = 1.0
    
    private(set) public var isPlaying: Bool = false
    private(set) public var isDragging: Bool = false
    private(set) public var needsRewind: Bool = false
    
    private var hideOverlayWork: DispatchWorkItem!
    
    weak public var delegate: (any UIVideoOverlayViewDelegate)? {
        didSet {
            if self.layer.backgroundColor == self.uiOverlayColor.cgColor {
                self.delegate?.overlayDidFadeIn?()
            } else {
                self.delegate?.overlayDidFadeOut?()
            }
        }
    }

    // MARK: - INIT
    public required init(duration: Float64) {
        self.duration = duration
        self.hideOverlayWork = nil
        
        super.init(frame: .zero)
        
        self.hideOverlayWork = DispatchWorkItem(block: {
            self.hideOverlay()
        })
        
        self.backgroundColor = uiOverlayColor
        self.delegate?.overlayWillFadeIn?()

        // MARK: PROGRESSBAR
        self.progressLabel = UILabel(frame: .zero)
        self.progressLabel.text = "0.0 / 0.0"
        
        // MARK: PLAY BTN
        self.playButton = UIButton(
            type: .custom,
            primaryAction: UIAction(
                image: UIImage(systemName: "play.fill")?
                        .withTintColor(.white)
                        .withRenderingMode(.alwaysOriginal)
                        .withConfiguration(UIImage.SymbolConfiguration(font: .systemFont(ofSize: 32)))
            ) { _ in
                if self.needsRewind {
                    self.delegate?.didTapRewindButton?()
                    self.hideOverlay()
                    self.needsRewind = false
                    
                    self.playButton.setImage(
                        UIImage(systemName: "pause.fill")?
                            .withRenderingMode(.alwaysOriginal)
                            .withTintColor(.white)
                            .withConfiguration(UIImage.SymbolConfiguration(font: .systemFont(ofSize: 32)))
                        , for: .normal
                    )
                } else {
                    if !self.isPlaying {
                        self.delegate?.didTapPlayButton?()
                        self.hideOverlay()
                        
                        self.playButton.setImage(
                            UIImage(systemName: "pause.fill")?
                                .withRenderingMode(.alwaysOriginal)
                                .withTintColor(.white)
                                .withConfiguration(UIImage.SymbolConfiguration(font: .systemFont(ofSize: 32)))
                            , for: .normal
                        )
                    } else {
                        self.resetHideOverlayWork()
                        self.delegate?.didTapPauseButton?()
                        self.playButton.setImage(
                            UIImage(systemName: "play.fill")?
                                .withRenderingMode(.alwaysOriginal)
                                .withTintColor(.white)
                                .withConfiguration(UIImage.SymbolConfiguration(font: .systemFont(ofSize: 32)))
                            , for: .normal
                        )
                    }
                }
                
                self.isPlaying.toggle()
            }
        )
        
        self.addSubview(self.playButton)
        
        playButton.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(60)
            make.height.equalTo(playButton.snp.width)
        }
        
        
        /*
        // MARK: SKIP ARROWS
        let arrows = UIVideoOverlaySkipArrows()
        
        self.addSubview(arrows)
        
        arrows.snp.makeConstraints { make in
            make.left.equalTo(self.playButton.snp.right).offset(20)
            make.centerY.equalToSuperview()
        }
    
        self.skipArrows = arrows
         */
        
        // MARK: SETTINGS BTN
        self.settingsButton = UIButton(
            type: .custom,
            primaryAction: UIAction(
                image: UIImage(systemName: "gearshape")?
                    .withTintColor(.white)
                    .withRenderingMode(.alwaysOriginal)
                    .withConfiguration(UIImage.SymbolConfiguration(font: .systemFont(ofSize: 16)))
            ) { _ in
                
            }
        )
        
        
        self.addSubview(settingsButton)
        
        settingsButton.snp.makeConstraints { make in
            make.top.right.equalToSuperview().inset(8)
            make.width.height.equalTo(33)
        }
        
        settingsButton.layer.backgroundColor = uiOverlayColor.cgColor
        settingsButton.showsMenuAsPrimaryAction = true
        
        settingsButton.menu = self.makeSpeedMultiplierMenu()
        settingsButton.overrideUserInterfaceStyle = .dark
        
        
        playButton.layer.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.4)
        playButton.configuration?.imagePadding = 8
        
        // MARK: TAP GESTURE RECOGNIZER
        let singleTapRecognizer = UIShortTapGestureRecognizer(target: self, action: #selector(self.handleTapOnOverlay(_:)))
        singleTapRecognizer.numberOfTapsRequired = 1
        
        let doubleTapRecognier = UITapGestureRecognizer(target: self, action: #selector(self.handleDoubleTapOnOverlay(_:)))
        doubleTapRecognier.numberOfTapsRequired = 2
                
        self.addGestureRecognizer(singleTapRecognizer)
        self.addGestureRecognizer(doubleTapRecognier)
        self.isExclusiveTouch = true
        
        singleTapRecognizer.require(toFail: doubleTapRecognier)

        
        // MARK: THE BOTTOMBAR
        let bottomBarView = UIView(frame: .zero)
                
        self.addSubview(bottomBarView)
        
        bottomBarView.snp.makeConstraints { make in
            make.left.bottom.right.equalToSuperview()
            make.height.equalTo(44)
        }
        
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [UIColor.black.withAlphaComponent(1.0).cgColor,
                                UIColor.black.withAlphaComponent(0.0).cgColor]

        gradientLayer.frame = bottomBarView.frame
        gradientLayer.startPoint = CGPoint(x: 1.0, y: 0.0)
        gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        bottomBarView.layer.insertSublayer(gradientLayer, at: 0)

        self.bottomBar = bottomBarView
        
        let indicatorGuide = UIView(frame: .zero)
        indicatorGuide.backgroundColor = UIColor.lightGray
        
        bottomBarView.addSubview(indicatorGuide)
        indicatorGuide.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(5)
        }
        
        let progressThumb = UIView(frame: .zero)
        progressThumb.layer.backgroundColor = self.progressIndicatorColor
        
        let progressBar = UIView(frame: .zero)
        progressBar.layer.backgroundColor = self.progressIndicatorColor
        
        indicatorGuide.addSubview(progressBar)
        indicatorGuide.addSubview(progressThumb)
        
        progressThumb.snp.makeConstraints { make in
            make.centerY.left.equalToSuperview()
            make.width.height.equalTo(self.thumbRadius)
        }
        
        // MARK: THE DRAG GESTURE
        let progressThumbGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(self.handleDragOnThumb(_:)))
        bottomBarView.addGestureRecognizer(progressThumbGestureRecognizer)
        
        self.progressThumb = progressThumb
        
        
        progressBar.snp.makeConstraints { make in
            make.left.top.bottom.equalToSuperview()
            make.right.equalTo(self.progressThumb.snp.centerX)
        }
        
        self.progressLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        self.progressLabel.textColor = .white
        self.progressLabel.text = timeInSecondsToString(0) + timeInSecondsToString(Float(self.duration))

        
        bottomBarView.addSubview(progressLabel)
        
        self.progressLabel.snp.makeConstraints { make in
            make.bottom.equalTo(indicatorGuide.snp.top).offset(-15)
            make.left.equalToSuperview().offset(15)
        }
        
        self.progressLabel.setContentHuggingPriority(.defaultHigh, for: .vertical)
        self.progressLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        
        self.delegate?.overlayDidFadeIn?()
        // MARK: END OF INIT
    }
    
    required public init?(coder: NSCoder) {
        fatalError("Cannot init from storyboard")
    }
    
    // MARK: - DID LAYOUT SUBVIEWS
    /// Makes the necessary views circular.
    /// - Note: It is required that the `UIViewController` that hosts this view invokes this explicitly overriding its own `viewDidLayoutSubviews`.
    /// Remember that when this function is invoked all the subviews already computed their bounds.
    open func viewDidLayoutSubviews() {
        self.playButton.layer.cornerRadius = self.playButton.layer.bounds.size.width/2.0
        self.playButton.layer.masksToBounds = true
        
        self.settingsButton.layer.cornerRadius = self.settingsButton.layer.bounds.size.width/2.0
        self.settingsButton.layer.masksToBounds = true

        self.progressThumb.layer.cornerRadius = self.progressThumb.bounds.size.width/2.0
        self.progressThumb.layer.masksToBounds = true
    }
    
    
    // MARK: - DRAG GESTURE HANDLING
    /// Handles the positioning of the progress thumb based on the location of the tap. Resets the cooldown timer for the overlay and notifies the delegate if any is set.
    @objc open func handleDragOnThumb(_ sender: UIPanGestureRecognizer? = nil) {
        guard let sender = sender else { return }
        guard !self.needsRewind else { return }
        
        switch sender.state {
            case .began:
                self.isDragging = true
                self.delegate?.playbackProgressWillStartChanging?()
                self.hideOverlayWork.cancel()
                break
            
            case .changed:
                let completionPerc = (Float(sender.location(in: self.progressThumb.superview).x - thumbRadius/2.0)/Float(self.bounds.size.width)).clamp(0...1)
                self.delegate?.playbackProgressDidChangeTo?(completionPerc: completionPerc)
            
                self.progressThumb.snp.updateConstraints { make in
                    make.left.equalToSuperview().offset(Float(self.bounds.size.width - self.thumbRadius/2.0) * completionPerc)
                }
                break
            
            case .cancelled:
                self.isDragging = false
                self.makeAndScheduleHideOverlayWork()
                self.delegate?.playbackProgressChangeCancelled?()
                break
            
            case .failed:
                self.isDragging = false
                self.makeAndScheduleHideOverlayWork()
                self.delegate?.playbackProgressChangeFailed?()
                break
            
            case .ended:
                self.isDragging = false
                self.makeAndScheduleHideOverlayWork()
                
                self.delegate?.playbackProgressDidEndChanging?(
                    completionPerc: (Float(sender.translation(in: self.progressThumb.superview).x - self.thumbRadius)/Float(self.bounds.size.width)).clamp(0...1)
                )
                break
                
            default:
                break
        }
    }
    
    
    // MARK: - TAP GESTURE HANDLER
    @objc open func handleTapOnOverlay(_ sender: UITapGestureRecognizer? = nil) {
        guard let sender = sender else { return }
        
        switch sender.state {
            case .ended:
                self.delegate?.didTapOnOverlay?(
                    atNormalizedLocation: CGPoint(
                        x: sender.location(in: self).x/self.bounds.size.width,
                        y: sender.location(in: self).y/self.bounds.size.height
                    ),
                    touchesCount: sender.numberOfTouches
                )
                break
                
            default:
                break
        }
    }
    
    // MARK: - DOUBLE TAP GESTURE HANDLER
    @objc open func handleDoubleTapOnOverlay(_ sender: UITapGestureRecognizer? = nil) {
        guard let sender = sender else { return }
        guard !self.needsRewind else { return }
                
        switch sender.state {
            
            case .ended:
                let tapNormalizedLocation = Float(sender.location(in: self.bottomBar).x/self.bottomBar.bounds.size.width).clamp(0...1)
                let currentLocation: Side = (tapNormalizedLocation < 0.5) ? .left : .right
                
                self.delegate?.didTapOnOverlay?(
                    atNormalizedLocation: CGPoint(
                        x: sender.location(in: self).x / self.bounds.size.width,
                        y: sender.location(in: self).y / self.bounds.size.height
                    ),
                    touchesCount: 2
                )
            
                if currentLocation == .left {
                  //   self.pointArrows(to: .left)
                    // self.skipArrows.playAnimation()
                    self.delegate?.overlayRequestedSkip?(of: -self.skipTimeAbs)
                } else {
                  //  self.pointArrows(to: .right)
                    // self.skipArrows.playAnimation()
                    self.delegate?.overlayRequestedSkip?(of: self.skipTimeAbs)
                }
            
                
                break
                
            default:
                break
        }
        
    }
    
    
    /// Hides the overlay and all its subviews. Cancels the timer to autohide the overlay.
    public final func hideOverlay() {
        self.delegate?.overlayWillFadeOut?()
        self.hideOverlayWork.cancel()
        
        UIView.animate(withDuration: 0.25) {
            self.layer.backgroundColor = UIColor.clear.cgColor
            self.playButton.layer.backgroundColor = UIColor.clear.cgColor
            self.playButton.imageView?.tintColor = .clear
            
            self.subviews.forEach { subview in
                subview.isHidden = true
            }
        } completion: { _ in
            self.delegate?.overlayDidFadeOut?()
        }
    }
    
    /// Shows the overlay and all the subviews. Starts the timer to autohide the overlay.
    public final func summonOverlay() {
        self.delegate?.overlayWillFadeIn?()
        
        UIView.animate(withDuration: 0.25) {
            self.layer.backgroundColor = self.uiOverlayColor.cgColor
            self.playButton.layer.backgroundColor = self.uiOverlayColor.cgColor
            
            self.subviews.forEach { subview in
                subview.isHidden = false
            }
        } completion: { _ in
            self.delegate?.overlayDidFadeIn?()
            
            if !self.needsRewind {
                self.makeHideOverlayWork()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + self.overlayUpTime, execute: self.hideOverlayWork)
            }
        }
    }
    
    
    /// A client can use this function to update the progress indicator of the overlay during the playback and the progress text label.
    open func setPlaybackProgress(to completionPerc: Float) {
        assert(completionPerc >= 0 && completionPerc <= 1)
        self.progressThumb.snp.updateConstraints { make in
            make.left.equalToSuperview().offset((self.bounds.size.width - self.thumbRadius) * CGFloat(completionPerc))
            self.progressLabel.text = timeInSecondsToString(completionPerc * Float(self.duration)) + " / " + timeInSecondsToString(Float(self.duration))
        }
    }
    
    /// A client notifies the overlay that the playback finished using this function.
    open func didFinishPlayback() {
        self.playButton.setImage(
            UIImage(systemName: "arrow.counterclockwise")?
                .withRenderingMode(.alwaysOriginal)
                .withTintColor(.white)
                .withConfiguration(UIImage.SymbolConfiguration(font: .systemFont(ofSize: 32))),
            for: .normal
        )
        
        self.needsRewind = true
        self.isPlaying = false
    }
    
    
    /// Creates an uncached menu for the allowed playback rates.
    ///
    /// - Note: for iOS < 16 the maximum supported playback rate is 2.0
    open func makeSpeedMultiplierMenu() -> UIMenu {
        return UIMenu(
            title: "Playback speed",
            children: [
                UIDeferredMenuElement.uncached { [weak self] completion in
                    guard let self = self else { return }
                    
                    let actions = [Float(0.25), Float(0.5), Float(1.0)].map { playbackSpeedMulti in
                        let actionForMultiplier = UIAction(
                            title: "\(playbackSpeedMulti)x",
                            image: self.currentSpeed == playbackSpeedMulti ?
                                UIImage(systemName: "checkmark")?
                                    .withTintColor(.label)
                                    .withRenderingMode(.alwaysOriginal)
                                    .withConfiguration(UIImage.SymbolConfiguration(font: .systemFont(ofSize: 12)))
                            : nil
                        ) { _ in
                            self.currentSpeed = playbackSpeedMulti
                            self.delegate?.didRequestPlaybackSpeedMultiplier?(playbackSpeedMulti)
                        }
                        
                        return actionForMultiplier
                    }
                    
                    completion(actions)
                }]
        )
    }
    
    
    /// Turns a time expressed in seconds to a string expressing that time in minutes and seconds.
    private func timeInSecondsToString(_ seconds: Float) -> String {
        let minutes = Int(seconds/60)
        let seconds = Int(seconds - floor(seconds/60))
        
        return "\(minutes < 10 ? "0":"")\(minutes):\(seconds < 10 ? "0":"")\(seconds)"
    }
    
    
    /// Creates the thread to hide the overlay.
    public final func makeHideOverlayWork() {
        self.hideOverlayWork = DispatchWorkItem(block: {
            self.hideOverlay()
        })
    }
    
    
    /// Creates and schedules the thread to hide the overlay.
    public final func makeAndScheduleHideOverlayWork() {
        self.makeHideOverlayWork()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + self.overlayUpTime, execute: self.hideOverlayWork)
    }
    
    
    public final func resetHideOverlayWork() {
        self.hideOverlayWork.cancel()
        self.makeAndScheduleHideOverlayWork()
    }
    
    open func pause() {
        self.playButton.setImage(UIImage(systemName:
            "play.fill"
        )!.withRenderingMode(.alwaysOriginal)
            .withTintColor(.white)
            .withConfiguration(UIImage.SymbolConfiguration(font: .systemFont(ofSize: 32))), for: .normal
        )
        
        self.isPlaying = false
    }
    
    public final func setPlaying(_ to: Bool) {
        self.isPlaying = to
    }
    
    /*
    private func pointArrows(to side: Side) {
        if side != currentSkipArrowsSide {
            self.skipArrows.snp.removeConstraints()

            if side == .right {
                self.skipArrows.snp.makeConstraints { make in
                    make.left.equalTo(self.playButton.snp.right).offset(20)
                    make.centerY.equalToSuperview()
                }
                
                self.skipArrows.layer.transform = CATransform3DMakeScale(1, 1, 1)
            } else {
                self.skipArrows.snp.makeConstraints { make in
                    make.right.equalTo(self.playButton.snp.left).offset(-20)
                    make.centerY.equalToSuperview()
                }
                
                self.skipArrows.layer.transform = CATransform3DMakeScale(-1, 1, 1)
            }
        }
        
        self.currentSkipArrowsSide = side
    }
     */
}


public enum Side {
    case left
    case right
}
