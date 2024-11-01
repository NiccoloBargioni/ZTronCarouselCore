import CoreGraphics

extension CGSize {
    static func sizeThatFits(containerSize: CGSize, containedAR: CGFloat) -> CGSize {
        if containedAR.isZero || containedAR.isNaN || containedAR.isInfinite {
            #if DEBUG
                print("Unexpected input parameter `containedAR` value: \(containedAR)")
            #endif
            return .zero
        } else {
            var resultSize = CGSize.zero
            if containerSize.width / containerSize.height >= containedAR {
                resultSize.height = containerSize.height
                resultSize.width = containerSize.height * containedAR
            } else {
                resultSize.width = containerSize.width
                resultSize.height = containerSize.width / containedAR
            }
            
            if resultSize.height > containerSize.height {
                #if DEBUG
                if resultSize.width > containerSize.width || resultSize.height > containerSize.height {
                    print("Computed size \(resultSize) unexpectedly exceeds container size \(containerSize)")
                }
                #endif
            } else {
                #if DEBUG
                if resultSize.width > containerSize.width || resultSize.height > containerSize.height {
                    print("Computed size \(resultSize) unexpectedly exceeds container size \(containerSize)")
                }
                #endif
            }
            
            return resultSize
        }
    }
}
