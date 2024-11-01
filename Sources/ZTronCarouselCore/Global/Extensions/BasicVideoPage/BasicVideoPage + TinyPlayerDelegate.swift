import Foundation
import ZTronVideoPlayer

extension BasicVideoPage: TinyPlayerDelegate {
    public func player(_ player: TinyPlayer, didUpdatePlaybackPosition position: Float, playbackProgress: Float) {
        self.videoOverlayView.setPlaybackProgress(to: playbackProgress)
    }
    
    public func playerHasFinishedPlayingVideo(_ player: any TinyPlayer) {
        if !self.isOverlayShowing {
            self.videoOverlayView.summonOverlay()
        }
        self.videoOverlayView.didFinishPlayback()
    }
}
