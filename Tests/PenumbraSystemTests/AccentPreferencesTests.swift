import Testing
import PenumbraCore
@testable import PenumbraSystem

@Suite struct AccentPreferencesTests {
    @Test func accentValuesMatchMacOS() {
        #expect(AccentColor.multicolor.preferenceValue == nil)
        #expect(AccentColor.graphite.preferenceValue == -1)
        #expect(AccentColor.red.preferenceValue == 0)
        #expect(AccentColor.purple.preferenceValue == 5)
        #expect(AccentColor.pink.preferenceValue == 6)
    }

    @Test func accentValuesReadBack() {
        for accent in AccentColor.allCases {
            #expect(AccentColor(preferenceValue: accent.preferenceValue) == accent)
        }
        #expect(AccentColor(preferenceValue: 99) == .multicolor)
    }

    @Test func highlightParsesNamedAndCustomValues() {
        #expect(ThemeColor(preferenceString: "1.000000 0.500000 0.000000 Other") == ThemeColor(red: 1, green: 0.5, blue: 0))
        #expect(ThemeColor(preferenceString: "0.25 0.5 0.75 Purple") == ThemeColor(red: 0.25, green: 0.5, blue: 0.75))
        #expect(ThemeColor(preferenceString: "not a colour") == nil)
    }

    @Test func onlyGraphiteSetsTheAquaVariant() {
        #expect(AccentColor.graphite.aquaVariant == 6)
        #expect(AccentColor.blue.aquaVariant == nil)
    }

    @Test func highlightUsesTheSystemFormat() {
        #expect(ThemeColor(red: 1, green: 0.5, blue: 0).preferenceString == "1.000000 0.500000 0.000000 Other")
    }
}
