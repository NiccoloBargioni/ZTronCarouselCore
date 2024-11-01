import Foundation

public final class BasicVideoOverlayFactory: UIVideoOverlayFactory, Sendable {
    public init() { }
    
    public final func makeOverlay(duration: Float64) -> any UIVideoOverlay {
        return UIVideoOverlayView(duration: duration)
    }
}
