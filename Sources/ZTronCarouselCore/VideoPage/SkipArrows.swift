import Foundation
import UIKit
import SnapKit

public final class UIVideoOverlaySkipArrows: UIView, Sendable {
    internal var biggestArrow: UIImageView!
    internal var intermediateArrow: UIImageView!
    internal var smallestArrow: UIImageView!
    internal var skipLabel: UILabel!
    
    internal var arrowsContainer: UIStackView!
    
    public init() {
        self.biggestArrow = UIImageView(
            image: UIImage(systemName: "play.fill")!
                .withRenderingMode(.alwaysOriginal)
                .withTintColor(.white)
                .withConfiguration(UIImage.SymbolConfiguration(font: .systemFont(ofSize: 21)))
        )
        
        self.biggestArrow.layer.opacity = 0.0
        
        self.intermediateArrow = UIImageView(
            image: UIImage(systemName: "play.fill")!
                .withRenderingMode(.alwaysOriginal)
                .withTintColor(.white)
                .withConfiguration(UIImage.SymbolConfiguration(font: .systemFont(ofSize: 14.7)))
        )
        
        self.intermediateArrow.layer.opacity = 0.0
        
        self.smallestArrow = UIImageView(
            image: UIImage(systemName: "play.fill")!
                .withRenderingMode(.alwaysOriginal)
                .withTintColor(.white)
                .withConfiguration(UIImage.SymbolConfiguration(font: .systemFont(ofSize: 10.3)))
        )
        
        self.smallestArrow.layer.opacity = 0.0

        
        self.arrowsContainer = UIStackView(frame: .zero)
        
        super.init(frame: .zero)
        
        
        let skipLabel: UILabel = UILabel(frame: .zero)
        skipLabel.text = "N Seconds"
        skipLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        skipLabel.textColor = .lightGray
        skipLabel.layer.opacity = 0.0
        
        self.skipLabel = skipLabel
        
        self.arrowsContainer.setContentHuggingPriority(.defaultHigh, for: .vertical)
        self.arrowsContainer.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        
        self.arrowsContainer.layer.transform = CATransform3DMakeScale(1, 1, 1)
        
        let superContainer = UIStackView(frame: .zero)
        superContainer.addSubview(arrowsContainer)
        superContainer.addSubview(skipLabel)
        
        skipLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(self.arrowsContainer).offset(15)
        }
        
        skipLabel.setContentHuggingPriority(.defaultHigh, for: .vertical)
        skipLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        
        superContainer.setContentHuggingPriority(.defaultHigh, for: .vertical)
        superContainer.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        self.addSubview(superContainer)
        
        self.arrowsContainer.addSubview(biggestArrow)
        self.arrowsContainer.addSubview(intermediateArrow)
        self.arrowsContainer.addSubview(smallestArrow)
        
        biggestArrow.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.centerY.equalToSuperview()
        }
        
        intermediateArrow.snp.makeConstraints { make in
            make.left.equalTo(biggestArrow.snp.right).offset(10)
            make.centerY.equalToSuperview()
        }
        
        smallestArrow.snp.makeConstraints { make in
            make.left.equalTo(intermediateArrow.snp.right).offset(10)
            make.centerY.equalToSuperview()
        }
        
    }
    
    required public init?(coder: NSCoder) {
        fatalError("Cannot init from storyboard")
    }
    
    
    public func playAnimation(forward: Bool) {
        
        if forward {
            self.skipLabel.layer.transform = CATransform3DMakeScale(-1, 1, 1)
        } else {
            self.skipLabel.layer.transform = CATransform3DMakeScale(1, 1, 1)
        }
        
        self.biggestArrow.layer.opacity = 1.0
        self.skipLabel.layer.opacity = 1.0
        
        UIView.animate(withDuration: 0.75) {
            self.skipLabel.layer.opacity = 0.0
        }
        
        UIView.animate(withDuration: 0.1) {
            self.biggestArrow.layer.opacity = 0.0
            self.intermediateArrow.layer.opacity = 1.0
        } completion: { _ in
            UIView.animate(withDuration: 0.1) {
                self.intermediateArrow.layer.opacity = 0.0
                self.smallestArrow.layer.opacity = 1.0
            } completion: { _ in
                UIView.animate(withDuration: 0.1) {
                    self.smallestArrow.layer.opacity = 0.0
                }
            }
        }
        
    }
    
    public final func setSkipTime(_ theTime: Int) {
        self.skipLabel.text = "\(theTime) Seconds"
    }
}

