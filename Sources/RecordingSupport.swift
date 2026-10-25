import AppKit
import AVFoundation

struct RecordingFailure: LocalizedError, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct RecordingTarget: Equatable, Sendable {
    let displayID: CGDirectDisplayID
    // Display-local points, with the origin at the top left (ScreenCaptureKit).
    let rect: CGRect
    let scale: CGFloat
    let name: String

    @MainActor
    static func fullScreen(_ screen: NSScreen) -> RecordingTarget {
        RecordingTarget(displayID: screen.displayID, rect: CGRect(origin: .zero, size: screen.frame.size),
                        scale: screen.backingScaleFactor, name: screen.localizedName)
    }

    static func localRect(_ selection: CGRect, screen: CGRect) -> CGRect {
        CGRect(x: selection.minX - screen.minX, y: screen.maxY - selection.maxY,
               width: selection.width, height: selection.height)
    }

    var pixelSize: CGSize {
        let factor = min(scale, 4096 / max(rect.width, rect.height))
        return CGSize(width: max(2, floor(rect.width * factor / 2) * 2),
                      height: max(2, floor(rect.height * factor / 2) * 2))
    }
}

enum RecordingArea: Equatable, Sendable {
    case wholeScreen
    case display(CGDirectDisplayID)
    case region(RecordingTarget)
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

enum RecordingFiles {
    static func nextURL(in directory: URL, date: Date = Date()) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "ddMMM-HH.mm.ss"
        let name = "YouCam-Recording-\(formatter.string(from: date))"
        var url = directory.appendingPathComponent(name).appendingPathExtension("mov")
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(name)-\(suffix)").appendingPathExtension("mov")
            suffix += 1
        }
        return url
    }
}

// A shared host-clock timeline keeps screen and microphone samples in sync.
// Intervals also reject late-arriving samples captured during a pause.
struct RecordingTimeline {
    var origin: Double?
    private(set) var pausedAt: Double?
    private(set) var pauses: [(start: Double, end: Double)] = []

    mutating func pause(at time: Double) {
        guard pausedAt == nil else { return }
        pausedAt = time
    }

    mutating func resume(at time: Double) {
        guard let start = pausedAt else { return }
        pauses.append((start, max(start, time)))
        pausedAt = nil
    }

    func presentationTime(for hostTime: Double) -> Double? {
        guard let origin, hostTime >= origin else { return nil }
        if let pausedAt, hostTime >= pausedAt { return nil }
        var removed = 0.0
        for pause in pauses {
            if hostTime >= pause.start && hostTime < pause.end { return nil }
            if hostTime >= pause.end { removed += max(0, pause.end - max(pause.start, origin)) }
        }
        return max(0, hostTime - origin - removed)
    }

    func duration(at hostTime: Double) -> Double {
        guard let origin else { return 0 }
        let end = min(hostTime, pausedAt ?? hostTime)
        let removed = pauses.reduce(0.0) { $0 + max(0, min(end, $1.end) - max(origin, $1.start)) }
        return max(0, end - origin - removed)
    }
}

struct AudioLevel: Sendable {
    var peak: Float = 0
    var clipped = false
    var decibels: Float { peak > 0 ? max(-60, 20 * log10(peak)) : -60 }
}

enum AudioGain {
    static func apply(_ samples: inout [Float], gain: Float) -> AudioLevel {
        var level = AudioLevel()
        for index in samples.indices {
            let input = samples[index].isFinite ? samples[index] : 0
            let output = input * gain
            level.peak = max(level.peak, abs(output))
            level.clipped = level.clipped || abs(input) >= 0.999 || abs(output) >= 0.999
            samples[index] = max(-1, min(1, output))
        }
        return level
    }
}

func hostSeconds() -> Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }

// CoreMedia buffers are immutable while crossing queues. Any gain processing
// creates a new buffer, rather than mutating buffers owned by the capture API.
final class SampleBufferBox: @unchecked Sendable {
    let sample: CMSampleBuffer
    init(_ sample: CMSampleBuffer) { self.sample = sample }
}
