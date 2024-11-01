import Foundation
import UIKit

class UIShortTapGestureRecognizer: UITapGestureRecognizer {
    let tapMaxDelay: Double = 0.05
    
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        Self.delay(delay: tapMaxDelay) {
            // Enough time has passed and the gesture was not recognized -> It has failed.
            if  self.state != UIGestureRecognizer.State.ended {
                self.state = UIGestureRecognizer.State.failed
            }
        }
    }
    
    class func delay(delay:Double, closure: @MainActor @Sendable @escaping ()->()) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay * Double(NSEC_PER_SEC), execute: closure)
    }
}
