import Foundation
import Observation

/// Persists `Preferences` as a single JSON blob in `UserDefaults`, which keeps
/// settings per machine and makes a later export/import trivial.
@MainActor @Observable
final class PreferencesStore {
    var value: Preferences {
        didSet { if value != oldValue { save() } }
    }

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "preferences.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode(Preferences.self, from: data) {
            value = stored
        } else {
            value = Preferences()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
