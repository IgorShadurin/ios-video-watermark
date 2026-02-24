import Foundation

final class ConversionSettingsStore {
    private enum Keys {
        static let watermarkSettings = "VideoWatermark.Settings.v1"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadSettings() -> WatermarkSettings {
        guard let data = defaults.data(forKey: Keys.watermarkSettings),
              let settings = try? JSONDecoder().decode(WatermarkSettings.self, from: data)
        else {
            return .defaultSettings
        }
        return settings
    }

    func saveSettings(_ settings: WatermarkSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Keys.watermarkSettings)
    }
}
