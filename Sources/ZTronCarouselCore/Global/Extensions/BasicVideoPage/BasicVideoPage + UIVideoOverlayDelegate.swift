import Foundation
import QuartzCore

extension BasicVideoPage: UIVideoOverlayViewDelegate {
    public func didTapPlayButton() {
        self.videoPlayer.setRate(self.videoPlaybackRate)
    }
    
    public func didTapPauseButton() {
        self.videoPlayer.pause()
    }
    
    public func didTapOnOverlay(atNormalizedLocation: CGPoint, touchesCount: Int) {
        
        if touchesCount <= 1 {
            if isOverlayShowing {
                self.videoOverlayView.hideOverlay()
            } else {
                self.videoOverlayView.summonOverlay()
            }
        } else {
            if atNormalizedLocation.x < 0.5 {
                self.pointArrows(to: .left)
                self.skipArrows.setSkipTime(-1*Int(self.videoOverlayView.skipTimeAbs))
            } else {
                self.pointArrows(to: .right)
                self.skipArrows.setSkipTime(Int(self.videoOverlayView.skipTimeAbs))
            }
            
            self.skipArrows.playAnimation(forward: atNormalizedLocation.x < 0.5)
        }
    }
    
    public func overlayDidFadeIn() {
        self.isOverlayShowing = true
        self.delegate?.overlayDidShow?(videoPage: self)
    }
    
    public func overlayDidFadeOut() {
        self.isOverlayShowing = false
        self.delegate?.overlayDidHide?(videoPage: self)
    }
    
    public func didRequestPlaybackSpeedMultiplier(_ theMultiplier: Float) {
        self.videoPlayer.setRate(theMultiplier)
        self.videoPlaybackRate = theMultiplier
        
        if !self.videoOverlayView.isPlaying {
            self.videoPlayer.pause()
        }
    }
    
    public func playbackProgressWillStartChanging() {
        self.wasPlayingBeforeDrag = self.videoOverlayView.isPlaying
        
        if self.videoOverlayView.isPlaying {
            self.videoPlayer.pause()
            self.videoOverlayView.setPlaying(false)
        }
    }
    
    public func playbackProgressDidEndChanging(completionPerc: Float) {
        if self.wasPlayingBeforeDrag {
            self.videoPlayer.setRate(self.videoPlaybackRate)
            self.videoOverlayView.setPlaying(true)
        }
    }
    
    public func playbackProgressDidChangeTo(completionPerc: Float) {
        self.videoPlayer.seekTo(position: self.videoDuration * completionPerc)
        self.videoOverlayView.setPlaybackProgress(to: completionPerc)
    }
    
    public func didTapRewindButton() {
        self.videoPlayer.resetPlayback()
        self.videoPlayer.setRate(self.videoPlaybackRate)
    }
    
    
    public func overlayRequestedSkip(of amount: Float) {
        guard let position = self.videoPlayer.playbackPosition else { return }
        self.videoPlayer.pause()
        
        self.videoPlayer.seekTo(position: (position + amount).clamp(0...self.videoDuration)) { notCancelled in
            Task(priority: .userInitiated) { @MainActor in
                if notCancelled && self.videoOverlayView.isPlaying {
                    self.videoPlayer.setRate(self.videoPlaybackRate)
                }
            }
        }
        
    }
    
}

