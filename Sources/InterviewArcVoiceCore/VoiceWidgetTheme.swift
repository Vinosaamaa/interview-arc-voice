import Foundation

public enum VoiceWidgetTheme: String, CaseIterable, Codable, Identifiable, Sendable {
    case arcticTeal
    case neonCircuit
    case auroraNight
    case solarEmber
    case sakuraGlass

    public static let preferenceKey = "voice.widgetTheme"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .arcticTeal: "Arctic Teal"
        case .neonCircuit: "Neon Circuit"
        case .auroraNight: "Aurora Night"
        case .solarEmber: "Solar Ember"
        case .sakuraGlass: "Sakura Glass"
        }
    }

    public var summary: String {
        switch self {
        case .arcticTeal: "Original frosted instrument"
        case .neonCircuit: "Electric cyberpunk"
        case .auroraNight: "Calm midnight spectrum"
        case .solarEmber: "Warm precision instrument"
        case .sakuraGlass: "Soft editorial light"
        }
    }

    public static func load(
        from defaults: UserDefaults = .standard
    ) -> VoiceWidgetTheme {
        guard let rawValue = defaults.string(forKey: preferenceKey),
              let theme = VoiceWidgetTheme(rawValue: rawValue) else {
            return .arcticTeal
        }
        return theme
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.preferenceKey)
    }
}
