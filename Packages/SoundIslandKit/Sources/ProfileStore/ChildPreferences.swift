// Per-child comfort settings set by a parent (spec section 12: accessibility). Stored per device in
// UserDefaults, keyed by profile id, so they never sync or leave the iPad and need no schema change.

import Foundation

public struct ChildPreferences: Codable, Equatable, Sendable {
    /// Softer, less saturated colors for kids who find the bright palette a lot.
    public var calmColors = false
    /// Studio track rail on the right, so a left hand can switch tracks while the right edits.
    public var leftHanded = false

    public init(calmColors: Bool = false, leftHanded: Bool = false) {
        self.calmColors = calmColors
        self.leftHanded = leftHanded
    }

    static func key(_ id: UUID) -> String { "childPreferences.\(id.uuidString)" }

    public static func load(for id: UUID, from defaults: UserDefaults = .standard) -> ChildPreferences {
        guard let data = defaults.data(forKey: key(id)),
              let prefs = try? JSONDecoder().decode(ChildPreferences.self, from: data) else { return ChildPreferences() }
        return prefs
    }

    public func save(for id: UUID, to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key(id)) }
    }

    public static func remove(for id: UUID, from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(id))
    }
}
