import AppKit
import Testing

@testable import SkillsManager

@MainActor
struct SkillsManagerAppTests {
    @Test("The application menu contains one Settings command")
    func applicationMenuContainsOneSettingsCommand() throws {
        let mainMenu = try #require(NSApplication.shared.mainMenu)
        let applicationMenu = try #require(mainMenu.items.first?.submenu)
        let settingsCommands = applicationMenu.items.filter {
            $0.keyEquivalent == ","
                && $0.keyEquivalentModifierMask.contains(.command)
        }

        #expect(
            settingsCommands.count == 1,
            "Expected one Command-Comma Settings command, found \(settingsCommands.count)."
        )
    }
}
