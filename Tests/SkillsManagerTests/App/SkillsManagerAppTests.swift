import AppKit
import SwiftUI
import Testing

@testable import SkillsManager

@MainActor
struct SkillsManagerAppTests {
    @Test("The app bundle declares no global accent color")
    func appBundleDeclaresNoGlobalAccentColor() {
        let globalAccentColorName = Bundle.main.object(
            forInfoDictionaryKey: "NSAccentColorName"
        )

        #expect(
            globalAccentColorName == nil,
            "A global accent-color declaration overrides the user's macOS accent color."
        )
    }

    @Test("The app does not bundle its former custom accent color")
    func appDoesNotBundleFormerCustomAccentColor() {
        let appDefinedAccentColor = NSColor(
            named: "AccentColor",
            bundle: .main
        )

        #expect(
            appDefinedAccentColor == nil,
            "A global AccentColor asset overrides the user's macOS accent color."
        )
    }

    @Test("A native prominent button inherits the macOS system accent color")
    func nativeProminentButtonInheritsSystemAccentColor() throws {
        let inheritedAccent = try prominentButtonAccentColor()
        let systemAccent = try prominentButtonAccentColor(
            tint: Color(nsColor: .controlAccentColor)
        )
        let componentTolerance: CGFloat = 0.06

        #expect(
            abs(inheritedAccent.redComponent - systemAccent.redComponent)
                <= componentTolerance,
            "The inherited red component should match the macOS control accent."
        )
        #expect(
            abs(inheritedAccent.greenComponent - systemAccent.greenComponent)
                <= componentTolerance,
            "The inherited green component should match the macOS control accent."
        )
        #expect(
            abs(inheritedAccent.blueComponent - systemAccent.blueComponent)
                <= componentTolerance,
            "The inherited blue component should match the macOS control accent."
        )
        #expect(
            abs(inheritedAccent.alphaComponent - systemAccent.alphaComponent)
                <= componentTolerance,
            "The inherited alpha component should match the macOS control accent."
        )
    }

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

    private func prominentButtonAccentColor(
        tint: Color? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> NSColor {
        let button = Button("Accent") {}
            .buttonStyle(.borderedProminent)
            .frame(width: 120, height: 40)
        let content =
            tint.map {
                AnyView(button.tint($0))
            } ?? AnyView(button)
        let renderer = ImageRenderer(
            content: content.environment(\.colorScheme, .light)
        )
        renderer.scale = 1

        let image = try #require(
            renderer.nsImage,
            sourceLocation: sourceLocation
        )
        let imageData = try #require(
            image.tiffRepresentation,
            sourceLocation: sourceLocation
        )
        let bitmap = try #require(
            NSBitmapImageRep(data: imageData),
            sourceLocation: sourceLocation
        )

        return try #require(
            bitmap.colorAt(
                x: bitmap.pixelsWide / 4,
                y: bitmap.pixelsHigh / 2
            )?.usingColorSpace(.sRGB),
            sourceLocation: sourceLocation
        )
    }
}
