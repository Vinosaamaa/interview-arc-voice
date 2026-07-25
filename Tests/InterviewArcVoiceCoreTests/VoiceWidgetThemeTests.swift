import Foundation
import Testing
@testable import InterviewArcVoiceCore

struct VoiceWidgetThemeTests {
    @Test
    func defaultsToArcticTealWhenNoPreferenceExists() {
        let defaults = isolatedDefaults()

        #expect(VoiceWidgetTheme.load(from: defaults) == .arcticTeal)
    }

    @Test
    func persistsAndRestoresEveryApprovedTheme() {
        let defaults = isolatedDefaults()

        for theme in VoiceWidgetTheme.allCases {
            theme.save(to: defaults)
            #expect(VoiceWidgetTheme.load(from: defaults) == theme)
        }
    }

    @Test
    func invalidStoredValueFallsBackSafely() {
        let defaults = isolatedDefaults()
        defaults.set("retired-theme", forKey: VoiceWidgetTheme.preferenceKey)

        #expect(VoiceWidgetTheme.load(from: defaults) == .arcticTeal)
    }

    @Test
    func approvedThemesHaveStableLabelsAndSummaries() {
        #expect(VoiceWidgetTheme.allCases.map(\.displayName) == [
            "Arctic Teal",
            "Neon Circuit",
            "Aurora Night",
            "Solar Ember",
            "Sakura Glass",
        ])
        #expect(VoiceWidgetTheme.allCases.allSatisfy { !$0.summary.isEmpty })
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "VoiceWidgetThemeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
