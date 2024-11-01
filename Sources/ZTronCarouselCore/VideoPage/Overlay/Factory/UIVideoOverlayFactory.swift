import Foundation

@MainActor public protocol UIVideoOverlayFactory: Sendable {
    func makeOverlay(duration: Float64) -> any UIVideoOverlay
}
