import AppKit

@MainActor
func runRecordingPanelTests(audio: AudioController) -> Int {
    var checks = 0
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError("FAIL: \(message)") }
    }
    let controls = RecordingControlsView(audio: audio)
    let buttons = controls.subviews.compactMap { $0 as? NSButton }
    let play = buttons.first { $0.accessibilityLabel() == "Start recording" }!
    let pause = buttons.first { $0.accessibilityLabel() == "Pause recording" }!
    let stop = buttons.first { $0.accessibilityLabel() == "Stop recording" }!
    var actions: [String] = []
    controls.onPlay = { actions.append("play") }
    controls.onPause = { actions.append("pause") }
    controls.onStop = { actions.append("stop") }

    for (phase, enabled) in [
        (RecordingPhase.idle, [true, false, false]),
        (.starting, [false, false, true]),
        (.recording, [false, true, true]),
        (.paused, [true, false, true]),
        (.finishing, [false, false, false])
    ] {
        controls.update(phase: phase, status: "Test", areaName: "Whole Screen", selectingArea: false)
        expect([play, pause, stop].map(\.isEnabled) == enabled,
               "Transport buttons offer only valid actions during \(phase)")
        expect(controls.areaButton.isEnabled == !phase.busy,
               "The area stays locked during \(phase)")
        let before = actions.count
        for (index, button) in [play, pause, stop].enumerated() where enabled[index] {
            expect(button.image != nil && button.title.isEmpty,
                   "Transport controls use icons with accessibility labels")
            button.performClick(nil)
        }
        let expected = zip(["play", "pause", "stop"], enabled).compactMap { $1 ? $0 : nil }
        expect(Array(actions.dropFirst(before)) == expected, "Transport actions are connected during \(phase)")
        if phase == .paused {
            expect(play.accessibilityLabel() == "Resume recording", "Play resumes a paused recording")
        }
        if phase == .starting {
            expect(stop.accessibilityLabel() == "Cancel recording", "Stop can cancel startup")
        }
    }
    controls.update(phase: .idle, status: "Ready", areaName: "Whole Screen", selectingArea: true)
    expect(!play.isEnabled && !controls.areaButton.isEnabled,
           "Selecting a region prevents recording before the selection is complete")
    return checks
}
