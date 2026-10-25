import AppKit

private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class RegionPicker {
    private(set) var windows: [NSPanel] = []
    private var completion: ((RecordingTarget?) -> Void)?
    var isSelecting: Bool { !windows.isEmpty }

    func select(completion: @escaping (RecordingTarget?) -> Void) {
        guard windows.isEmpty else { return }
        self.completion = completion
        NSApp.activate(ignoringOtherApps: true)
        for screen in NSScreen.screens {
            let window = SelectionPanel(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.title = "Select Recording Area"
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.onFinish = { [weak self] rect in
                guard let rect else { self?.finish(nil); return }
                let global = rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
                self?.finish(RecordingTarget(displayID: screen.displayID,
                    rect: RecordingTarget.localRect(global, screen: screen.frame), scale: screen.backingScaleFactor,
                    name: "\(Int(rect.width)) × \(Int(rect.height)) on \(screen.localizedName)"))
            }
            window.contentView = view
            windows.append(window)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
        }
        NSCursor.crosshair.push()
    }

    func cancel() { if isSelecting { finish(nil) } }

    private func finish(_ target: RecordingTarget?) {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        NSCursor.pop()
        let callback = completion
        completion = nil
        // Finish mouse handling before the picker views are released.
        DispatchQueue.main.async { callback?(target) }
    }
}

private final class SelectionView: NSView {
    var onFinish: ((CGRect?) -> Void)?
    private var anchor: NSPoint?
    private var selected: CGRect?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let shade = NSBezierPath(rect: bounds)
        if let selected { shade.appendRect(selected) }
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.4).setFill()
        shade.fill()
        if let selected {
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selected.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
        }
        let message = selected.map { "\(Int($0.width)) × \(Int($0.height)) · Release to select · Esc to cancel" }
            ?? "Drag to select a recording area · Esc to cancel"
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 18, weight: .medium), .foregroundColor: NSColor.white]
        let size = (message as NSString).size(withAttributes: attributes)
        (message as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: bounds.height - 80), withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        anchor = convert(event.locationInWindow, from: nil)
        window?.makeFirstResponder(self)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let anchor else { return }
        let point = convert(event.locationInWindow, from: nil)
        selected = CGRect(x: min(anchor.x, point.x), y: min(anchor.y, point.y),
                          width: abs(point.x - anchor.x), height: abs(point.y - anchor.y)).intersection(bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        guard let selected, selected.width >= 40, selected.height >= 40 else { return }
        onFinish?(selected)
    }
    override func cancelOperation(_ sender: Any?) { onFinish?(nil) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish?(nil) } else { super.keyDown(with: event) }
    }
}
