import AppKit

@MainActor
final class AudioLevelMeter: NSView {
    private var level = AudioLevel()
    private var clipUntil = 0.0
    var isClipping: Bool { hostSeconds() < clipUntil }

    func update(_ level: AudioLevel) {
        self.level = level
        if level.clipped { clipUntil = hostSeconds() + 1.5 }
        setAccessibilityValue(String(format: "%.0f decibels%@", level.decibels, isClipping ? ", clipping" : ""))
        needsDisplay = true
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.levelIndicator)
        setAccessibilityLabel("Microphone input level")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let segments = 40
        let segmentWidth = (bounds.width - 42) / CGFloat(segments)
        let filled = Int((min(0, level.decibels) + 60) / 60 * Float(segments))
        for index in 0..<segments {
            let threshold = -60 + Float(index + 1) * 60 / Float(segments)
            let color: NSColor = threshold > -6 ? .systemRed : threshold > -12 ? .systemYellow : .systemGreen
            color.withAlphaComponent(index < filled ? 1 : 0.2).setFill()
            NSBezierPath(roundedRect: NSRect(x: CGFloat(index) * segmentWidth, y: 3,
                width: max(1, segmentWidth - 2), height: bounds.height - 6), xRadius: 1, yRadius: 1).fill()
        }
        let text = isClipping ? "CLIP" : String(format: "%.0f", level.decibels)
        (text as NSString).draw(at: NSPoint(x: bounds.width - 37, y: 4), withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: isClipping ? NSColor.systemRed : NSColor.secondaryLabelColor
        ])
    }
}

@MainActor
final class AudioControlView: NSView {
    private let audio: AudioController
    private let compact: Bool
    let meter = AudioLevelMeter(frame: .zero)
    private let caption = NSTextField(labelWithString: "Input level")
    private let value = NSTextField(labelWithString: "0 dB")
    private let source = NSTextField(labelWithString: "")
    private let slider: NSSlider
    private var timer: Timer?

    init(audio: AudioController, width: CGFloat = 300, compact: Bool = false) {
        self.audio = audio
        self.compact = compact
        slider = NSSlider(value: audio.gainDB, minValue: -36, maxValue: 12, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: compact ? 72 : 110))
        caption.font = .systemFont(ofSize: 12, weight: .medium)
        caption.isHidden = compact
        value.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        value.alignment = .right
        source.font = .systemFont(ofSize: 10)
        source.textColor = .secondaryLabelColor
        source.lineBreakMode = .byTruncatingMiddle
        slider.target = self
        slider.action = #selector(changeLevel)
        slider.isContinuous = true
        slider.setAccessibilityLabel("Microphone input gain in decibels")
        for child in [caption, value, source, slider, meter] { addSubview(child) }
        update()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        if compact {
            slider.frame = NSRect(x: 12, y: 46, width: bounds.width - 86, height: 24)
            value.frame = NSRect(x: bounds.width - 68, y: 50, width: 53, height: 16)
            meter.frame = NSRect(x: 15, y: 25, width: bounds.width - 30, height: 18)
            source.frame = NSRect(x: 15, y: 5, width: bounds.width - 30, height: 14)
            return
        }
        caption.frame = NSRect(x: 14, y: 87, width: 140, height: 16)
        value.frame = NSRect(x: bounds.width - 95, y: 87, width: 80, height: 16)
        slider.frame = NSRect(x: 12, y: 57, width: bounds.width - 24, height: 24)
        meter.frame = NSRect(x: 15, y: 31, width: bounds.width - 30, height: 21)
        source.frame = NSRect(x: 15, y: 9, width: bounds.width - 30, height: 16)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer?.invalidate()
        timer = nil
        guard window != nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] timer in
            let alive = MainActor.assumeIsolated {
                guard let self else { return false }
                if self.window?.isVisible == true { self.update() }
                return true
            }
            if !alive { timer.invalidate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func update() {
        slider.doubleValue = audio.gainDB
        slider.isEnabled = audio.hasAudio
        value.stringValue = String(format: "%+.0f dB", audio.gainDB)
        meter.update(audio.level)
        source.stringValue = meter.isClipping ? "Clipping — lower the input or microphone level" : audio.status
        source.textColor = meter.isClipping ? .systemRed : .secondaryLabelColor
        source.toolTip = source.stringValue
    }

    @objc private func changeLevel() { audio.setGain(slider.doubleValue); update() }
}

@MainActor
final class RecordingPanel: NSPanel {
    var makeMenu: (() -> NSMenu)?
    let controls: RecordingControlsView
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(audio: AudioController) {
        controls = RecordingControlsView(audio: audio)
        super.init(contentRect: NSRect(origin: NSPoint(x: 100, y: 100), size: controls.frame.size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "YouCam Recording Controls"
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        appearance = NSAppearance(named: .darkAqua)
        contentView = controls
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) {
            if let menu = makeMenu?() { NSMenu.popUpContextMenu(menu, with: event, for: controls) }
            return
        }
        super.sendEvent(event)
    }
}

@MainActor
private final class RecordingStartCell: NSButtonCell {
    var phase = RecordingPhase.idle

    override func drawImage(_ image: NSImage, withFrame frame: NSRect, in controlView: NSView) {
        if phase == .paused {
            super.drawImage(image, withFrame: frame, in: controlView)
            return
        }
        // The active circle is also a status indicator. Keep it bright even
        // though starting another recording is disabled while one is running.
        let color = phase == .recording
            ? NSColor(srgbRed: 1, green: 0.42, blue: 0.45, alpha: 1)
            : NSColor(srgbRed: 0.82, green: 0.19, blue: 0.23, alpha: 1)
        color.withAlphaComponent(isEnabled || phase == .recording ? 1 : 0.35).setFill()
        let diameter: CGFloat = 12
        NSBezierPath(ovalIn: NSRect(x: frame.midX - diameter / 2, y: frame.midY - diameter / 2,
                                   width: diameter, height: diameter)).fill()
    }
}

@MainActor
final class RecordingControlsView: NSView {
    private let status = NSTextField(labelWithString: "Ready to record")
    private let play = NSButton(title: "", target: nil, action: nil)
    private let startCell = RecordingStartCell(textCell: "")
    private let pause = NSButton(title: "", target: nil, action: nil)
    private let stop = NSButton(title: "", target: nil, action: nil)
    private let close = NSButton(title: "", target: nil, action: nil)
    private(set) var areaButton = NSButton(title: "Area: Whole Screen ▾", target: nil, action: nil)
    let audioControls: AudioControlView
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onStop: (() -> Void)?
    var onHide: (() -> Void)?
    var makeAreaMenu: (() -> NSMenu)?

    init(audio: AudioController) {
        audioControls = AudioControlView(audio: audio, width: 300, compact: true)
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 156))
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.98).cgColor
        layer?.cornerRadius = 12
        status.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        play.cell = startCell
        for (button, symbol, label, action) in [
            (play, "circle.fill", "Start recording", #selector(playClicked)),
            (pause, "pause.fill", "Pause recording", #selector(pauseClicked)),
            (stop, "stop.fill", "Stop recording", #selector(stopClicked))
        ] {
            button.bezelStyle = .texturedRounded
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel(label)
            button.toolTip = label
            button.target = self
            button.action = action
        }
        pause.isEnabled = false
        stop.isEnabled = false
        areaButton.bezelStyle = .rounded
        areaButton.alignment = .left
        areaButton.font = .systemFont(ofSize: 11)
        areaButton.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: nil)
        areaButton.imagePosition = .imageLeading
        areaButton.cell?.lineBreakMode = .byTruncatingTail
        areaButton.setAccessibilityLabel("Recording area")
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Hide recording panel")
        close.isBordered = false
        close.contentTintColor = .secondaryLabelColor
        close.setAccessibilityLabel("Hide recording panel")
        close.toolTip = "Hide recording panel"
        close.target = self; close.action = #selector(hideClicked)
        areaButton.target = self; areaButton.action = #selector(areaClicked)
        for view in [status, play, pause, stop, close, areaButton, audioControls] { addSubview(view) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        areaButton.frame = NSRect(x: 10, y: 120, width: 254, height: 26)
        close.frame = NSRect(x: 270, y: 122, width: 20, height: 22)
        play.frame = NSRect(x: 12, y: 82, width: 30, height: 30)
        pause.frame = NSRect(x: 46, y: 82, width: 30, height: 30)
        stop.frame = NSRect(x: 80, y: 82, width: 30, height: 30)
        status.frame = NSRect(x: 120, y: 89, width: 168, height: 16)
        audioControls.frame = NSRect(x: 0, y: 5, width: 300, height: 72)
    }

    func update(phase: RecordingPhase, status text: String, areaName: String, selectingArea: Bool) {
        areaButton.title = "\(areaName) ▾"
        areaButton.toolTip = "\(areaName) — \(phase.busy ? "Stop recording to change the area" : "Choose the recording area")"
        areaButton.isEnabled = !phase.busy && !selectingArea
        status.stringValue = text
        status.toolTip = text
        status.textColor = phase == .recording ? .systemRed : phase == .paused ? .systemOrange : .secondaryLabelColor
        play.isEnabled = (phase == .idle || phase == .paused) && !selectingArea
        play.toolTip = switch phase {
        case .idle: "Start recording"
        case .starting: "Starting recording"
        case .recording: "Recording"
        case .paused: "Resume recording"
        case .finishing: "Saving recording"
        }
        if startCell.phase != phase {
            startCell.phase = phase
            play.image = NSImage(systemSymbolName: phase == .paused ? "play.fill" : "circle.fill",
                                 accessibilityDescription: nil)
            play.needsDisplay = true
        }
        play.setAccessibilityLabel(play.toolTip)
        pause.isEnabled = phase == .recording
        stop.isEnabled = phase == .starting || phase == .recording || phase == .paused
        stop.toolTip = phase == .starting ? "Cancel recording" : "Stop recording"
        stop.setAccessibilityLabel(stop.toolTip)
        audioControls.update()
    }

    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    @objc private func playClicked() { onPlay?() }
    @objc private func pauseClicked() { onPause?() }
    @objc private func stopClicked() { onStop?() }
    @objc private func hideClicked() { onHide?() }
    @objc private func areaClicked() {
        makeAreaMenu?().popUp(positioning: nil, at: NSPoint(x: areaButton.frame.minX, y: areaButton.frame.minY), in: self)
    }
}
