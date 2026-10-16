import AppKit
import QuartzCore

/// Capture transition: a borderless, click-through overlay window (one per capture, covering the screen) shows the
/// captured window image at its original position, flashes white once, then shrinks and flies to the screen's
/// bottom-right corner like the macOS screenshot thumbnail. ~0.5s. Always played AFTER the screenshot was taken.
///
/// Guard rails (Codex has had bugs where a transition overlay got stuck on screen, openai/codex#33914):
/// at most one overlay at a time, a new capture cancels the old one, and a hard timeout closes it regardless.
final class CaptureAnimator {
    static let duration: CFTimeInterval = 0.5
    private var overlay: NSWindow?
    private var watchdog: DispatchWorkItem?

    func cancel() {
        watchdog?.cancel()
        watchdog = nil
        overlay?.orderOut(nil)
        overlay?.close()
        overlay = nil
    }

    /// `windowFrame` is in global top-left-origin points (CG / ScreenCaptureKit coordinates).
    /// Returns once the animation has finished (or was skipped).
    @MainActor
    func play(image: CGImage, windowFrame: CGRect) async {
        cancel()
        guard let primary = NSScreen.screens.first, windowFrame.width > 8, windowFrame.height > 8 else { return }

        // CG (top-left origin, primary display) -> AppKit (bottom-left origin).
        let start = CGRect(x: windowFrame.minX, y: primary.frame.height - windowFrame.maxY,
                           width: windowFrame.width, height: windowFrame.height)
        let screen = NSScreen.screens.first { $0.frame.intersects(start) } ?? primary

        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let content = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        content.wantsLayer = true
        window.contentView = content

        // Layer geometry is relative to the overlay window (== screen frame).
        let local = start.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)

        let card = CALayer()   // carries the shadow
        card.bounds = CGRect(origin: .zero, size: local.size)
        card.position = CGPoint(x: local.midX, y: local.midY)
        card.shadowColor = NSColor.black.cgColor
        card.shadowOpacity = 0.45
        card.shadowRadius = 18
        card.shadowOffset = CGSize(width: 0, height: -6)

        let picture = CALayer()
        picture.frame = card.bounds
        picture.contents = image
        picture.contentsGravity = .resize
        picture.cornerRadius = 8
        picture.masksToBounds = true
        card.addSublayer(picture)

        let flash = CALayer()
        flash.frame = card.bounds
        flash.backgroundColor = NSColor.white.cgColor
        flash.cornerRadius = 8
        flash.opacity = 0
        card.addSublayer(flash)
        content.layer?.addSublayer(card)

        // Destination: bottom-right of the visible area, thumbnail ~180pt wide.
        let thumbW = min(180, local.width)
        let scale = thumbW / local.width
        let thumbH = local.height * scale
        let vis = screen.visibleFrame
        let dest = CGPoint(x: vis.maxX - 24 - thumbW / 2 - screen.frame.minX,
                           y: vis.minY + 24 + thumbH / 2 - screen.frame.minY)

        window.orderFrontRegardless()
        overlay = window

        let total = Self.duration
        let flyStart: CFTimeInterval = 0.10

        let fly = CAAnimationGroup()
        fly.beginTime = CACurrentMediaTime() + flyStart
        fly.duration = total - flyStart
        fly.fillMode = .both
        fly.isRemovedOnCompletion = false
        let ease = CAMediaTimingFunction(name: .easeInEaseOut)
        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = NSValue(point: card.position)
        move.toValue = NSValue(point: dest)
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1.0
        shrink.toValue = scale
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1.0, 1.0, 0.0]
        fade.keyTimes = [0, 0.85, 1]
        for a in [move, shrink, fade] { a.duration = fly.duration }
        for a in [move, shrink] { a.timingFunction = ease }
        fly.animations = [move, shrink, fade]
        card.add(fly, forKey: "fly")

        let pulse = CAKeyframeAnimation(keyPath: "opacity")
        pulse.values = [0.0, 0.75, 0.0]
        pulse.keyTimes = [0, 0.2, 1]
        pulse.duration = 0.22
        pulse.beginTime = CACurrentMediaTime()
        flash.add(pulse, forKey: "flash")

        // Hard cleanup: the overlay can never outlive the animation by more than a moment.
        let work = DispatchWorkItem { [weak self] in self?.cancel() }
        watchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + total + 0.3, execute: work)
        try? await Task.sleep(nanoseconds: UInt64((total + 0.05) * 1_000_000_000))
        if overlay === window { cancel() }
    }
}
