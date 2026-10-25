import AppKit
import AVFoundation

// Always write mono 48 kHz PCM into the encoder, even when the selected input
// device changes format. Software gain works with USB and virtual microphones.
enum PCMBuffer {
    static func make(samples: [Float], at time: CMTime) -> CMSampleBuffer? {
        guard !samples.isEmpty else { return nil }
        var asbd = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1,
            mBitsPerChannel: 32, mReserved: 0)
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0,
                layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil,
                formatDescriptionOut: &format) == noErr, let format else { return nil }
        var block: CMBlockBuffer?
        let count = samples.count * MemoryLayout<Float>.size
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
                blockLength: count, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
                offsetToData: 0, dataLength: count, flags: 0, blockBufferOut: &block) == noErr,
              let block else { return nil }
        let copied = samples.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: count)
        }
        guard copied == noErr else { return nil }
        var sample: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault,
                dataBuffer: block, formatDescription: format, sampleCount: samples.count,
                presentationTimeStamp: time, packetDescriptions: nil, sampleBufferOut: &sample) == noErr else { return nil }
        return sample
    }
}

private final class MicrophoneDriver: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.youcam.microphone", qos: .userInitiated)
    private let sampleQueue = DispatchQueue(label: "app.youcam.microphone-samples", qos: .userInitiated)
    private let movie: RecordingWriter
    private var deviceID: String?
    private var gain: Float = 1
    private var lastMeterTime = 0.0
    private var pendingLevel = AudioLevel()
    private var errorObserver: NSObjectProtocol?
    var onLevel: (@MainActor @Sendable (AudioLevel) -> Void)?
    var onFailure: (@MainActor @Sendable (String) -> Void)?

    init(movie: RecordingWriter) {
        self.movie = movie
        super.init()
        errorObserver = NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
                                                               object: session, queue: nil) { [weak self] notification in
            let message = (notification.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription
                ?? "The microphone stopped unexpectedly."
            if let callback = self?.onFailure { Task { @MainActor in callback(message) } }
        }
    }

    func start(deviceID: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                if self.deviceID == deviceID, session.isRunning { continuation.resume(); return }
                do {
                    guard let device = AVCaptureDevice(uniqueID: deviceID) else {
                        throw RecordingFailure("The selected microphone is disconnected. Choose another Audio Input.")
                    }
                    if session.isRunning { session.stopRunning() }
                    let input = try AVCaptureDeviceInput(device: device)
                    let output = AVCaptureAudioDataOutput()
                    output.audioSettings = [AVFormatIDKey: kAudioFormatLinearPCM,
                        AVSampleRateKey: 48000, AVNumberOfChannelsKey: 1,
                        AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
                        AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false]
                    output.setSampleBufferDelegate(self, queue: sampleQueue)
                    session.beginConfiguration()
                    session.inputs.forEach { session.removeInput($0) }
                    session.outputs.forEach { session.removeOutput($0) }
                    guard session.canAddInput(input), session.canAddOutput(output) else {
                        session.commitConfiguration()
                        throw RecordingFailure("This microphone cannot be opened.")
                    }
                    session.addInput(input)
                    session.addOutput(output)
                    session.commitConfiguration()
                    session.startRunning()
                    guard session.isRunning else { throw RecordingFailure("The microphone could not start.") }
                    self.deviceID = deviceID
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func setGain(_ gain: Float) { sampleQueue.async { [self] in self.gain = gain } }
    func stop() { queue.async { [self] in if session.isRunning { session.stopRunning() }; deviceID = nil } }
    func shutdown() {
        if let errorObserver { NotificationCenter.default.removeObserver(errorObserver) }
        queue.sync { if session.isRunning { session.stopRunning() } }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let data = sampleBuffer.dataBuffer,
              let description = sampleBuffer.formatDescription,
              let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              format.mFormatID == kAudioFormatLinearPCM, format.mBitsPerChannel == 32,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mChannelsPerFrame == 1 else { return }
        let count = CMBlockBufferGetDataLength(data) / 4
        var samples = [Float](repeating: 0, count: count)
        let status = samples.withUnsafeMutableBytes { bytes in
            CMBlockBufferCopyDataBytes(data, atOffset: 0, dataLength: bytes.count, destination: bytes.baseAddress!)
        }
        guard status == noErr else { return }
        let level = AudioGain.apply(&samples, gain: gain)
        pendingLevel.peak = max(pendingLevel.peak, level.peak)
        pendingLevel.clipped = pendingLevel.clipped || level.clipped
        let now = hostSeconds()
        if now - lastMeterTime >= 0.05 {
            let delivered = pendingLevel
            pendingLevel = AudioLevel()
            lastMeterTime = now
            if let onLevel { Task { @MainActor in onLevel(delivered) } }
        }
        var time = sampleBuffer.presentationTimeStamp
        if let clock = session.synchronizationClock {
            time = CMSyncConvertTime(time, from: clock, to: CMClockGetHostTimeClock())
        }
        if let processed = PCMBuffer.make(samples: samples, at: time) { movie.appendAudio(processed) }
    }
}

@MainActor
final class AudioController: NSObject, NSMenuDelegate {
    private let defaults: UserDefaults
    private let driver: MicrophoneDriver
    private let previewMode: Bool
    private let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
    private var observers: [NSObjectProtocol] = []
    private var reasons: Set<String> = []
    private var generation = 0
    private var monitoringReady = false
    private(set) var devices: [AVCaptureDevice] = []
    private(set) var selectedID: String
    private(set) var gainDB: Double
    private(set) var level = AudioLevel()
    private(set) var status = "Microphone idle"
    var onChange: (() -> Void)?
    var onDeviceLost: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var hasAudio: Bool { selectedID != "none" }
    var name: String { devices.first { $0.uniqueID == selectedID }?.localizedName ?? (hasAudio ? "Microphone unavailable" : "No Audio") }

    init(defaults: UserDefaults, movie: RecordingWriter, previewMode: Bool) {
        self.defaults = defaults
        self.previewMode = previewMode
        driver = MicrophoneDriver(movie: movie)
        selectedID = defaults.string(forKey: "audioID") ?? AVCaptureDevice.default(for: .audio)?.uniqueID ?? "none"
        let savedGain = defaults.double(forKey: "audioGainDB")
        gainDB = savedGain.isFinite ? min(12, max(-36, savedGain)) : 0
        super.init()
        driver.setGain(Float(pow(10, gainDB / 20)))
        driver.onLevel = { [weak self] level in
            guard let self, self.monitoringReady, self.hasAudio, !self.reasons.isEmpty else { return }
            self.level = level
            self.onChange?()
        }
        driver.onFailure = { [weak self] message in
            guard let self, !self.reasons.isEmpty else { return }
            self.monitoringReady = false
            self.status = message
            self.level = AudioLevel()
            self.onChange?()
            self.onFailure?(message)
        }
        refreshDevices()
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshDevices() }
            })
        }
    }

    private func refreshDevices() {
        let wasDisconnected = status == "Microphone disconnected"
        devices = discovery.devices.sorted { $0.localizedName.localizedStandardCompare($1.localizedName) == .orderedAscending }
        if hasAudio, !devices.contains(where: { $0.uniqueID == selectedID }) {
            status = "Microphone disconnected"
            monitoringReady = false
            level = AudioLevel()
            driver.stop()
            onDeviceLost?()
        } else if wasDisconnected {
            status = "Microphone idle"
            if !reasons.isEmpty { startMonitoring() }
        }
        onChange?()
    }

    func select(_ id: String) {
        selectedID = id
        defaults.set(id, forKey: "audioID")
        generation += 1
        monitoringReady = false
        driver.stop()
        level = AudioLevel()
        status = hasAudio ? "Microphone idle" : "Audio off"
        if !reasons.isEmpty { startMonitoring() }
        onChange?()
    }

    func setGain(_ decibels: Double) {
        gainDB = min(12, max(-36, decibels))
        defaults.set(gainDB, forKey: "audioGainDB")
        driver.setGain(Float(pow(10, gainDB / 20)))
        onChange?()
    }

    func acquire(_ reason: String) async throws {
        reasons.insert(reason)
        guard hasAudio, !previewMode else { return }
        let request = generation
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: granted = true
        case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .audio)
        default: granted = false
        }
        guard request == generation, !reasons.isEmpty else { throw CancellationError() }
        guard granted else {
            status = "Allow Microphone access in System Settings"
            onChange?()
            throw RecordingFailure("Allow YouCam in System Settings → Privacy & Security → Microphone, or select No Audio.")
        }
        do {
            try await driver.start(deviceID: selectedID)
            guard request == generation, !reasons.isEmpty else { throw CancellationError() }
            monitoringReady = true
            status = name
            onChange?()
        } catch {
            if !(error is CancellationError) { status = error.localizedDescription; onChange?() }
            throw error
        }
    }

    func release(_ reason: String) {
        reasons.remove(reason)
        if reasons.isEmpty {
            generation += 1
            monitoringReady = false
            driver.stop()
            level = AudioLevel()
            status = hasAudio ? "Microphone idle" : "Audio off"
            onChange?()
        }
    }

    func monitor(_ reason: String, enabled: Bool) {
        if enabled {
            reasons.insert(reason)
            startMonitoring()
        } else { release(reason) }
    }

    private func startMonitoring() {
        guard let reason = reasons.first else { return }
        let request = generation
        Task { [weak self] in
            guard let self, self.generation == request, self.reasons.contains(reason) else { return }
            try? await self.acquire(reason)
        }
    }

    func menuWillOpen(_ menu: NSMenu) { monitor("menu", enabled: true) }
    func menuDidClose(_ menu: NSMenu) { monitor("menu", enabled: false) }

    func shutdown() {
        generation += 1
        reasons.removeAll()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        driver.shutdown()
    }
}
