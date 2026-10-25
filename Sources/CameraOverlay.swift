import AppKit
import AVFoundation

@MainActor
final class CameraPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        title = "YouCam"
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        animationBehavior = .none
    }
}

@MainActor
final class CameraPreviewView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()
    private let clippingLayer = CALayer()
    private let placeholder = NSView()
    private let icon = NSImageView()
    private let heading = NSTextField(labelWithString: "Starting camera…")
    private let detail = NSTextField(wrappingLabelWithString: "Your camera will appear here.")
    private var tracking: NSTrackingArea?

    var shape: CameraShape = .circle { didSet { needsLayout = true } }
    var mirrored = true { didSet { updateMirroring() } }
    var onResize: ((CGFloat) -> Void)?
    var makeMenu: (() -> NSMenu)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        clippingLayer.masksToBounds = true
        clippingLayer.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 1).cgColor
        layer?.addSublayer(clippingLayer)
        previewLayer.videoGravity = .resizeAspectFill
        clippingLayer.addSublayer(previewLayer)

        placeholder.wantsLayer = true
        addSubview(placeholder)
        icon.image = NSImage(systemSymbolName: "video", accessibilityDescription: nil)
        icon.contentTintColor = NSColor.white.withAlphaComponent(0.7)
        icon.imageScaling = .scaleProportionallyUpOrDown
        heading.textColor = .white
        heading.font = .systemFont(ofSize: 15, weight: .semibold)
        heading.alignment = .center
        detail.textColor = NSColor.white.withAlphaComponent(0.65)
        detail.font = .systemFont(ofSize: 12)
        detail.alignment = .center
        detail.maximumNumberOfLines = 3
        for view in [icon, heading, detail] { placeholder.addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Camera overlay")
        setAccessibilityHelp("Drag to move. Scroll to resize. Right-click for camera controls.")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clippingLayer.frame = bounds
        clippingLayer.cornerRadius = shape == .circle ? bounds.width / 2 : 14
        previewLayer.frame = clippingLayer.bounds
        placeholder.frame = bounds
        let width = bounds.width * (shape == .circle ? 0.72 : 0.86)
        let left = (bounds.width - width) / 2
        let center = bounds.midY
        let compact = bounds.height < 160 || bounds.width < 200
        icon.isHidden = compact
        detail.isHidden = compact
        icon.frame = NSRect(x: bounds.midX - 17, y: center + 24, width: 34, height: 26)
        heading.font = .systemFont(ofSize: compact ? 11 : 15, weight: .semibold)
        heading.frame = NSRect(x: left, y: compact ? center - 10 : center - 5, width: width, height: 22)
        detail.frame = NSRect(x: left, y: center - 62, width: width, height: 48)
        CATransaction.commit()
    }

    func display(_ state: CameraState) {
        if let message = state.message {
            heading.stringValue = message.title
            detail.stringValue = message.detail
            placeholder.isHidden = false
            previewLayer.isHidden = true
        } else {
            placeholder.isHidden = true
            previewLayer.isHidden = false
        }
        setAccessibilityValue(state.menuTitle)
        updateMirroring()
    }

    func updateMirroring() {
        guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = mirrored
    }

    private func containsVideo(_ point: NSPoint) -> Bool {
        if shape == .circle {
            let dx = point.x - bounds.midX
            let dy = point.y - bounds.midY
            return dx * dx + dy * dy <= pow(bounds.width / 2, 2)
        }
        return NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).contains(point)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        containsVideo(convert(point, from: superview)) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        if containsVideo(convert(event.locationInWindow, from: nil)) { NSCursor.openHand.set() }
        else { NSCursor.arrow.set() }
    }

    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if event.modifierFlags.contains(.control) {
            rightMouseDown(with: event)
            return
        }
        window.performDrag(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = makeMenu?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.momentumPhase.isEmpty else { return }
        let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 8)
        onResize?(delta)
    }
}
