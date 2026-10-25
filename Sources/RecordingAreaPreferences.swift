import AppKit

// Store display-local points and a stable display UUID, since numeric display
// IDs can change between sessions. Pixel density comes from the current screen.
enum RecordingAreaPreferences {
    private struct SavedArea: Codable {
        enum Mode: String, Codable { case wholeScreen, display, region }
        let mode: Mode
        var displayUUID: String?
        var rect: CGRect?
    }

    @MainActor
    static func save(_ area: RecordingArea, to defaults: UserDefaults) {
        let saved: SavedArea
        switch area {
        case .wholeScreen:
            saved = SavedArea(mode: .wholeScreen)
        case .display(let id):
            guard let uuid = displayUUID(id) else { return }
            saved = SavedArea(mode: .display, displayUUID: uuid)
        case .region(let target):
            guard let uuid = displayUUID(target.displayID) else { return }
            saved = SavedArea(mode: .region, displayUUID: uuid, rect: target.rect)
        }
        if let data = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: "recordingArea")
        }
    }

    @MainActor
    static func load(from defaults: UserDefaults, screens: [NSScreen] = NSScreen.screens) -> RecordingArea {
        guard let data = defaults.data(forKey: "recordingArea"),
              let saved = try? JSONDecoder().decode(SavedArea.self, from: data),
              saved.mode != .wholeScreen,
              let uuid = saved.displayUUID,
              let screen = screens.first(where: { displayUUID($0.displayID) == uuid }) else {
            return .wholeScreen
        }
        if saved.mode == .display { return .display(screen.displayID) }
        guard let rect = saved.rect,
              [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy(\.isFinite),
              rect.width >= 40, rect.height >= 40,
              CGRect(origin: .zero, size: screen.frame.size).contains(rect) else {
            return .wholeScreen
        }
        return .region(RecordingTarget(displayID: screen.displayID, rect: rect,
            scale: screen.backingScaleFactor,
            name: "\(Int(rect.width)) × \(Int(rect.height)) on \(screen.localizedName)"))
    }

    private static func displayUUID(_ id: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
