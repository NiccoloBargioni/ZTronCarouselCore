import Foundation

@objc public protocol UIVideoOverlayViewDelegate: NSObjectProtocol {
    @MainActor @objc optional func didTapOnOverlay(atNormalizedLocation: CGPoint, touchesCount: Int)    
    @MainActor @objc optional func didTapPlayButton()
    @MainActor @objc optional func didTapPauseButton()
    @MainActor @objc optional func didTapRewindButton()
    @MainActor @objc optional func overlayWillFadeOut()
    @MainActor @objc optional func overlayDidFadeOut()
    @MainActor @objc optional func overlayWillFadeIn()
    @MainActor @objc optional func overlayDidFadeIn()
    @MainActor @objc optional func didRequestPlaybackSpeedMultiplier(_ theMultiplier: Float)
    @MainActor @objc optional func playbackProgressWillStartChanging()
    @MainActor @objc optional func playbackProgressChangeCancelled()
    @MainActor @objc optional func playbackProgressChangeFailed()
    @MainActor @objc optional func playbackProgressDidChangeTo(completionPerc: Float)
    @MainActor @objc optional func playbackProgressDidEndChanging(completionPerc: Float)
    @MainActor @objc optional func overlayRequestedSkip(of amount: Float)
}

