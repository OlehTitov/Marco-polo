import AppKit
import QuartzCore

final class HeadingGutterAnimator {
    private var activeOverlays: [Int: CATextLayer] = [:]

    func isAnimating(at paragraphLocation: Int) -> Bool {
        activeOverlays[paragraphLocation] != nil
    }

    func animate(text: String, font: NSFont, color: NSColor,
                 from startFrame: CGRect, to endFrame: CGRect,
                 in layer: CALayer, backingScale: CGFloat,
                 key: Int, completion: @escaping () -> Void) {
        let overlay = CATextLayer()
        overlay.string = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color
        ])
        overlay.frame = startFrame
        overlay.contentsScale = backingScale
        overlay.isWrapped = false
        activeOverlays[key] = overlay
        layer.addSublayer(overlay)

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        CATransaction.setCompletionBlock { [weak self] in
            overlay.removeFromSuperlayer()
            self?.activeOverlays.removeValue(forKey: key)
            completion()
        }
        overlay.frame = endFrame
        CATransaction.commit()
    }

    func cancelAll() {
        for (_, overlay) in activeOverlays {
            overlay.removeFromSuperlayer()
        }
        activeOverlays.removeAll()
    }
}
