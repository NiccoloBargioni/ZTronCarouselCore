import Foundation

public extension ClosedRange<CGFloat> {
    func larp(_ t: CGFloat) -> CGFloat {
        return self.lowerBound + t*(self.upperBound - self.lowerBound)
    }
}
