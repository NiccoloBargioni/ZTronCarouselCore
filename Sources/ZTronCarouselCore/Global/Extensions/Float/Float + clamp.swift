import Foundation

public extension Float {
    func clamp(_ to: ClosedRange<Float>) -> Float {
        if self < to.lowerBound {
            return to.lowerBound
        } else {
            if self > to.upperBound {
                return to.upperBound
            } else {
                return self
            }
        }
    }
}
