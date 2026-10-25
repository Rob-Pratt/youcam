import AppKit

@MainActor
func runRecordingAreaTests(_ delegate: AppDelegate, defaults: UserDefaults) -> Int {
    var checks = 0
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError("FAIL: \(message)") }
    }

    let cases: [(RecordingAreaCorner, CGPoint, CGRect, RecordingAreaCorner)] = [
        (.topLeft, CGPoint(x: 80, y: 350), CGRect(x: 80, y: 120, width: 340, height: 230), .bottomRight),
        (.topRight, CGPoint(x: 500, y: 350), CGRect(x: 100, y: 120, width: 400, height: 230), .bottomLeft),
        (.bottomLeft, CGPoint(x: 80, y: 90), CGRect(x: 80, y: 90, width: 340, height: 210), .topRight),
        (.bottomRight, CGPoint(x: 500, y: 90), CGRect(x: 100, y: 90, width: 400, height: 210), .topLeft)
    ]
    for origin in [CGPoint.zero, CGPoint(x: -1920, y: -400), CGPoint(x: 200, y: 1080)] {
        let display = CGRect(origin: origin, size: CGSize(width: 1440, height: 900))
        let rect = CGRect(x: origin.x + 100, y: origin.y + 120, width: 320, height: 180)
        for (corner, destination, expected, opposite) in cases {
            let point = CGPoint(x: origin.x + destination.x, y: origin.y + destination.y)
            expect(corner.resized(rect, to: point, within: display, scale: 2)
                == expected.offsetBy(dx: origin.x, dy: origin.y), "\(corner) adjusts width and height independently on offset displays")
            let anchor = opposite.point(in: rect)
            let cornerPoint = corner.point(in: rect)
            let outward = CGPoint(x: cornerPoint.x + (cornerPoint.x < anchor.x ? -10_000 : 10_000),
                                  y: cornerPoint.y + (cornerPoint.y < anchor.y ? -10_000 : 10_000))
            let expanded = corner.resized(rect, to: outward, within: display, scale: 1)
            expect(display.contains(expanded), "Dragging beyond the display keeps the region on that display")
            expect(opposite.point(in: expanded) == anchor, "Clamping keeps the opposite corner fixed")
            let crossing = CGPoint(x: anchor.x + (cornerPoint.x < anchor.x ? 100 : -100),
                                   y: anchor.y + (cornerPoint.y < anchor.y ? 100 : -100))
            let minimum = corner.resized(rect, to: crossing, within: display, scale: 2)
            expect(minimum.size == CGSize(width: 40, height: 40), "Dragging across the opposite corner retains a usable minimum")
            expect(opposite.point(in: minimum) == anchor, "Shrinking keeps the opposite corner fixed")
            let fractional = CGPoint(x: point.x + 0.26, y: point.y + 0.26)
            let aligned = corner.resized(rect, to: fractional, within: display, scale: 2)
            expect(corner.point(in: aligned) == CGPoint(x: point.x + 0.5, y: point.y + 0.5),
                   "Retina dragging aligns to physical pixels")
        }
    }

    guard case .region(let initialTarget) = delegate.recordingArea,
          let screen = NSScreen.screens.first(where: { $0.displayID == initialTarget.displayID }) else {
        fatalError("A selected region is required for handle interaction tests")
    }
    let overlay = delegate.areaOverlay
    func event(_ type: NSEvent.EventType, at global: CGPoint, in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: window.convertPoint(fromScreen: global), modifierFlags: [],
                          timestamp: 0, windowNumber: window.windowNumber, context: nil,
                          eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    let original = CGRect(x: screen.frame.minX + initialTarget.rect.minX,
                          y: screen.frame.maxY - initialTarget.rect.maxY,
                          width: initialTarget.rect.width, height: initialTarget.rect.height)
    expect(overlay.handles.count == 4, "A selected area has four corner handles")
    for (corner, _, _, opposite) in cases {
        delegate.setRecordingArea(.region(initialTarget))
        let handle = overlay.handles[corner]!
        let view = handle.contentView!
        let point = corner.point(in: original)
        let anchor = opposite.point(in: original)
        expect(handle.isVisible && !handle.ignoresMouseEvents, "Corner handles are visible and interactive before recording")
        expect(!handle.canBecomeKey && !handle.canBecomeMain, "Dragging handles does not take keyboard focus")
        expect(handle.styleMask.contains(.nonactivatingPanel), "Corner handles work without activating YouCam")
        expect(handle.level > .statusBar, "Handles remain accessible over the menu bar and Dock at screen edges")
        expect(CGPoint(x: handle.frame.midX, y: handle.frame.midY) == point, "Dots are centered on the exact capture corners")
        // Grab off center, then send several drags as the small window moves.
        let grab = CGPoint(x: point.x + 3, y: point.y - 2)
        view.mouseDown(with: event(.leftMouseDown, at: grab, in: handle))
        view.mouseDragged(with: event(.leftMouseDragged, at: grab, in: handle))
        expect(delegate.selectedRecordingTarget == initialTarget, "An off-center grab does not make the area jump")
        let dx: CGFloat = point.x < anchor.x ? -37 : 37
        let dy: CGFloat = point.y < anchor.y ? -23 : 23
        let intermediate = CGPoint(x: grab.x + dx / 2, y: grab.y + dy / 2)
        view.mouseDragged(with: event(.leftMouseDragged, at: intermediate, in: handle))
        let end = CGPoint(x: grab.x + dx, y: grab.y + dy)
        view.mouseDragged(with: event(.leftMouseDragged, at: end, in: handle))
        let target = delegate.selectedRecordingTarget!
        let expected = CGRect(x: original.minX + min(dx, 0), y: original.minY + min(dy, 0),
                              width: original.width + 37, height: original.height + 23)
        expect(target.rect == RecordingTarget.localRect(expected, screen: screen.frame),
               "Dragging updates the actual recording crop live, without accumulated movement")
        expect(target.displayID == initialTarget.displayID && target.scale == screen.backingScaleFactor,
               "Resizing preserves the selected display and its pixel density")
        expect((overlay.window?.contentView as? RecordingAreaShadeView)?.selection
            == expected.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY),
               "The clear area follows the resized recording crop")
        expect(delegate.recordingPanel.controls.areaButton.title.contains("357 × 203"),
               "Recording controls show the new area dimensions during dragging")
        expect(overlay.window?.ignoresMouseEvents == true, "The rest of the screen remains click-through while resizing")
        view.mouseUp(with: event(.leftMouseUp, at: end, in: handle))
        expect(delegate.selectedRecordingTarget == target, "Releasing the handle retains the resized area")
        guard case .region(let savedTarget) = RecordingAreaPreferences.load(from: defaults) else {
            fatalError("The corner adjustment was not saved")
        }
        expect(savedTarget.rect == target.rect && savedTarget.displayID == target.displayID,
               "Corner adjustments survive reloading preferences")
        view.mouseDragged(with: event(.leftMouseDragged, at: grab, in: handle))
        expect(delegate.selectedRecordingTarget == target, "Further movement after release does not resize the area")
    }

    let handle = overlay.handles[.topRight]!
    let view = handle.contentView!
    let grab = CGPoint(x: handle.frame.midX, y: handle.frame.midY)
    view.mouseDown(with: event(.leftMouseDown, at: grab, in: handle))
    let lockedTarget = delegate.selectedRecordingTarget
    overlay.isEditable = false
    expect(overlay.handles.values.allSatisfy { !$0.isVisible }, "All corner handles disappear when editing is locked")
    expect(overlay.window?.isVisible == true, "The recording guide stays visible while editing is locked")
    let next = CGPoint(x: grab.x + 50, y: grab.y + 50)
    view.mouseDragged(with: event(.leftMouseDragged, at: next, in: handle))
    expect(delegate.selectedRecordingTarget == lockedTarget, "Locking the area cancels a drag already in progress")
    overlay.isEditable = true
    expect(overlay.handles.values.allSatisfy(\.isVisible), "The handles return when editing is unlocked")
    view.mouseDragged(with: event(.leftMouseDragged, at: next, in: handle))
    expect(delegate.selectedRecordingTarget == lockedTarget, "Unlocking does not resume a stale drag")

    delegate.setRecordingArea(.region(.fullScreen(screen)))
    for (corner, panel) in overlay.handles {
        expect(CGPoint(x: panel.frame.midX, y: panel.frame.midY) == corner.point(in: screen.frame),
               "Corners at display edges are not pushed inward by window constraints")
    }
    let oldHandles = Array(overlay.handles.values)
    delegate.selectWholeScreen()
    expect(overlay.handles.isEmpty && oldHandles.allSatisfy { !$0.isVisible },
           "Whole Screen removes every corner control")
    view.mouseDown(with: event(.leftMouseDown, at: grab, in: handle))
    view.mouseDragged(with: event(.leftMouseDragged, at: next, in: handle))
    expect(delegate.recordingArea == .wholeScreen, "A removed handle cannot recreate a cleared recording area")
    delegate.setRecordingArea(.region(initialTarget))

    // Render just our UI over a neutral backdrop, without capturing the desktop.
    let shade = RecordingAreaShadeView(frame: CGRect(x: 0, y: 0, width: 800, height: 500))
    shade.selection = CGRect(x: 170, y: 120, width: 460, height: 260)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 500,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    shade.draw(shade.bounds)
    let dot = RecordingAreaHandleView(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
    let dotBitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 24, pixelsHigh: 24,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: dotBitmap)
    dot.draw(dot.bounds)
    NSGraphicsContext.restoreGraphicsState()
    let dotImage = NSImage(cgImage: dotBitmap.cgImage!, size: dot.bounds.size)
    for corner in RecordingAreaCorner.allCases {
        let point = corner.point(in: shade.selection)
        dotImage.draw(in: CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24))
    }
    NSGraphicsContext.restoreGraphicsState()
    expect(bitmap.colorAt(x: 400, y: 250)!.alphaComponent < 0.01, "Adding handles leaves the middle of the recording area clear")
    expect(bitmap.colorAt(x: 170, y: 120)!.alphaComponent > 0.99, "Corner dots render visibly at selection corners")
    try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/recording-area-handles.png"))
    return checks
}
