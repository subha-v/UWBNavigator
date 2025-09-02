/*
See LICENSE folder for this sample's licensing information.

Abstract:
Custom arrow view for directional navigation display.
*/

import UIKit

class ArrowView: UIView {
    
    // MARK: - Properties
    private var arrowColor: UIColor = .systemBlue
    private var arrowAngle: CGFloat = 0.0
    private var arrowScale: CGFloat = 1.0
    private var isAnimating = false
    
    // Arrow states based on distance/visibility
    enum ArrowState {
        case closeAndVisible    // Large, bright arrow
        case farAndVisible      // Medium arrow
        case outOfView          // Small, dimmed arrow
        case notTracking        // Hidden
    }
    
    private var currentState: ArrowState = .notTracking {
        didSet {
            updateArrowAppearance()
        }
    }
    
    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        backgroundColor = .clear
        isOpaque = false
    }
    
    // MARK: - Drawing
    override func draw(_ rect: CGRect) {
        guard currentState != .notTracking else { return }
        
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        
        // Calculate center and size
        let center = CGPoint(x: rect.width / 2, y: rect.height / 2)
        let size = min(rect.width, rect.height) * 0.8 * arrowScale
        
        // Apply rotation
        context?.translateBy(x: center.x, y: center.y)
        context?.rotate(by: arrowAngle)
        context?.translateBy(x: -center.x, y: -center.y)
        
        // Create arrow path
        let arrowPath = createArrowPath(center: center, size: size)
        
        // Set color and fill
        arrowColor.setFill()
        arrowPath.fill()
        
        // Add border for better visibility
        UIColor.white.setStroke()
        arrowPath.lineWidth = 2.0
        arrowPath.stroke()
        
        context?.restoreGState()
    }
    
    private func createArrowPath(center: CGPoint, size: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        
        // Arrow points
        let tipY = center.y - size/2
        let baseY = center.y + size/3
        let arrowWidth = size * 0.6
        let stemWidth = size * 0.3
        
        // Arrow tip
        path.move(to: CGPoint(x: center.x, y: tipY))
        
        // Right wing
        path.addLine(to: CGPoint(x: center.x + arrowWidth/2, y: center.y - size/6))
        
        // Right stem
        path.addLine(to: CGPoint(x: center.x + stemWidth/2, y: center.y - size/6))
        
        // Base right
        path.addLine(to: CGPoint(x: center.x + stemWidth/2, y: baseY))
        
        // Base left
        path.addLine(to: CGPoint(x: center.x - stemWidth/2, y: baseY))
        
        // Left stem
        path.addLine(to: CGPoint(x: center.x - stemWidth/2, y: center.y - size/6))
        
        // Left wing
        path.addLine(to: CGPoint(x: center.x - arrowWidth/2, y: center.y - size/6))
        
        // Close path
        path.close()
        
        return path
    }
    
    // MARK: - Public Methods
    func updateDirection(azimuth: Float, animated: Bool = true) {
        let newAngle = CGFloat(azimuth)
        
        if animated && !isAnimating {
            isAnimating = true
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut], animations: { [weak self] in
                self?.arrowAngle = newAngle
                self?.setNeedsDisplay()
            }) { [weak self] _ in
                self?.isAnimating = false
            }
        } else if !animated {
            arrowAngle = newAngle
            setNeedsDisplay()
        }
    }
    
    func setState(_ state: ArrowState, animated: Bool = true) {
        if animated {
            UIView.animate(withDuration: 0.3) { [weak self] in
                self?.currentState = state
            }
        } else {
            currentState = state
        }
    }
    
    func setDistanceState(distance: Float?, isInFOV: Bool) {
        if distance == nil && !isInFOV {
            setState(.notTracking)
        } else if !isInFOV {
            setState(.outOfView)
        } else if let dist = distance, dist < 0.3 {
            setState(.closeAndVisible)
        } else {
            setState(.farAndVisible)
        }
    }
    
    // MARK: - Appearance Updates
    private func updateArrowAppearance() {
        switch currentState {
        case .closeAndVisible:
            arrowColor = .systemGreen
            arrowScale = 1.2
            alpha = 1.0
            pulseAnimation()
        case .farAndVisible:
            arrowColor = .systemBlue
            arrowScale = 1.0
            alpha = 1.0
            removePulseAnimation()
        case .outOfView:
            arrowColor = .systemGray
            arrowScale = 0.8
            alpha = 0.6
            removePulseAnimation()
        case .notTracking:
            alpha = 0.0
            removePulseAnimation()
        }
        
        setNeedsDisplay()
    }
    
    // MARK: - Animations
    private func pulseAnimation() {
        removePulseAnimation()
        
        let pulseAnimation = CABasicAnimation(keyPath: "transform.scale")
        pulseAnimation.fromValue = 0.95
        pulseAnimation.toValue = 1.05
        pulseAnimation.duration = 0.5
        pulseAnimation.autoreverses = true
        pulseAnimation.repeatCount = .infinity
        pulseAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        
        layer.add(pulseAnimation, forKey: "pulse")
    }
    
    private func removePulseAnimation() {
        layer.removeAnimation(forKey: "pulse")
    }
    
    // MARK: - Haptic Feedback
    func triggerHapticFeedback() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
}