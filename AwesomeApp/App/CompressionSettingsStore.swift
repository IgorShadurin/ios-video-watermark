import Foundation

final class ConversionSettingsStore {
    private let defaults: UserDefaults
    private let settingsKey = "video_converter_settings_v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadDraftSettings() -> VideoConversionSettings {
        guard let data = defaults.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(VideoConversionSettings.self, from: data)
        else {
            return .default
        }
        return settings
    }

    func saveDraftSettings(_ settings: VideoConversionSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        defaults.set(data, forKey: settingsKey)
    }
}
