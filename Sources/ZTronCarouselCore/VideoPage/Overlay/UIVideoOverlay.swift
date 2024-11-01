import UIKit


@MainActor public protocol UIVideoOverlay: UIView {
    var delegate: (any UIVideoOverlayViewDelegate)? { get set }
    var isPlaying: Bool { get }
    var skipTimeAbs: Float { get }
    
    func setPlaybackProgress(to completionPerc: Float) -> Void
    func pause() -> Void
    func summonOverlay() -> Void
    func hideOverlay() -> Void 
    
    func viewDidLayoutSubviews() -> Void
    func didFinishPlayback() -> Void
    
    func setPlaying(_ to: Bool) -> Void
    
    init(duration: Float64)
}
