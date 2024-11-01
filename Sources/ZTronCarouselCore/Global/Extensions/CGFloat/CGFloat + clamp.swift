import Foundation

public extension CGFloat {
    func clamp(_ to: ClosedRange<CGFloat>) -> CGFloat {
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
