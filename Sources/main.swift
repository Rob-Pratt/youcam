import AppKit
import AVFoundation

// Developer check: sample the meter briefly, without saving audio or asking for
// new permissions. Normal app launch never starts this diagnostic.
if CommandLine.arguments.contains("--microphone-test") {
    guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
        print("Microphone test skipped: permission has not been granted.")
        exit(0)
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let domain = "app.youcam.microphone-test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    let audio = AudioController(defaults: defaults, movie: RecordingWriter(), previewMode: false)
    var updates = 0
    audio.onChange = { updates += 1 }
    Task { @MainActor in
        var result: Int32 = 0
        do {
            try await audio.acquire("test")
            let initial = updates
            try await Task.sleep(for: .seconds(2))
            let received = updates - initial
            print("Microphone: \(audio.name); live meter updates: \(received)")
            if received < 5 { result = 1 }
        } catch {
            print("Microphone test failed: \(error.localizedDescription)")
            result = 1
        }
        audio.release("test")
        audio.shutdown()
        defaults.removePersistentDomain(forName: domain)
        exit(result)
    }
    app.run()
    exit(0)
}

let smokeTest = CommandLine.arguments.contains("--smoke-test")
let smokeTestDomain = "app.youcam.smoke-test.\(UUID().uuidString)"
let defaults = smokeTest ? UserDefaults(suiteName: smokeTestDomain)! : .standard
let app = NSApplication.shared
let delegate = AppDelegate(previewMode: smokeTest, defaults: defaults)
app.delegate = delegate
if smokeTest {
    print("Screen Recording permission: \(CGPreflightScreenCaptureAccess() ? "granted" : "not granted")")
    print("Microphone permission: \(AVCaptureDevice.authorizationStatus(for: .audio) == .authorized ? "granted" : "not granted")")
    // Exercise the actual app bundle without requesting access to a camera.
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { app.terminate(nil) }
}
app.run()
if smokeTest { defaults.removePersistentDomain(forName: smokeTestDomain) }
