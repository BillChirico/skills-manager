import Foundation
import SkillsCore
import Testing

@testable import SkillsManager

@MainActor
struct FolderSettingsSelectionTests {
    @Test("Reconciliation preserves a folder that still exists")
    func preservesExistingSelection() {
        let first = makeSource(name: "Claude", path: "/skills/claude")
        let second = makeSource(name: "Codex", path: "/skills/codex")
        var selection = FolderSettingsSelection(sourceID: second.id)

        selection.reconcile(with: [first, second])

        #expect(selection.sourceID == second.id)
    }

    @Test("Reconciliation keeps a populated folder list unselected")
    func keepsPopulatedListUnselected() {
        let source = makeSource(name: "Codex", path: "/skills/codex")
        var selection = FolderSettingsSelection()

        selection.reconcile(with: [source])

        #expect(selection.sourceID == nil)
    }

    @Test("Reconciliation clears a selection when its folder disappears")
    func clearsRemovedSelection() {
        let removed = makeSource(name: "Claude", path: "/skills/claude")
        let remaining = makeSource(name: "Codex", path: "/skills/codex")
        var selection = FolderSettingsSelection(sourceID: removed.id)

        selection.reconcile(with: [remaining])

        #expect(selection.sourceID == nil)
    }

    private func makeSource(name: String, path: String) -> SkillSource {
        SkillSource(
            name: name,
            directoryURL: URL(filePath: path, directoryHint: .isDirectory)
        )
    }
}

@MainActor
struct FolderSettingsRowPresentationTests {
    private let homeDirectory = URL(
        filePath: "/Users/reviewer",
        directoryHint: .isDirectory
    )

    @Test("An enabled healthy row has no decorative visible status")
    func healthyStateIsQuietAndAccessible() {
        let source = makeSource(
            name: "Codex",
            path: "/Users/reviewer/.codex/skills/",
            isEnabled: true
        )

        let presentation = FolderSettingsRowPresentation(
            source: source,
            state: .available,
            homeDirectory: homeDirectory
        )

        #expect(presentation.displayPath == "~/.codex/skills")
        #expect(presentation.statusText == nil)
        #expect(presentation.statusSystemImage == nil)
        #expect(presentation.showsReconnectAction == false)
        #expect(presentation.stateAccessibilityLabel == "Available")
        #expect(presentation.toggleAccessibilityLabel == "Enable Codex")
        #expect(presentation.reconnectAccessibilityLabel == "Reconnect Codex")
    }

    @Test("A disabled row names its paused state without hiding its controls")
    func pausedStateUsesTextAndAccessibleControls() {
        let source = makeSource(
            name: "Claude",
            path: "/Users/reviewer/.claude/skills",
            isEnabled: false
        )

        let presentation = FolderSettingsRowPresentation(
            source: source,
            state: .available,
            homeDirectory: homeDirectory
        )

        #expect(presentation.statusText == "Paused")
        #expect(presentation.statusSystemImage == "pause.circle")
        #expect(presentation.showsReconnectAction == false)
        #expect(presentation.stateAccessibilityLabel == "Paused")
        #expect(presentation.toggleAccessibilityLabel == "Enable Claude")
    }

    @Test("A disabled row remains paused while an earlier scan winds down")
    func disabledStateTakesPriorityOverScanning() {
        let source = makeSource(
            name: "Claude",
            path: "/Users/reviewer/.claude/skills",
            isEnabled: false
        )

        let presentation = FolderSettingsRowPresentation(
            source: source,
            state: .scanning,
            homeDirectory: homeDirectory
        )

        #expect(presentation.statusText == "Paused")
        #expect(presentation.statusSystemImage == "pause.circle")
        #expect(presentation.stateAccessibilityLabel == "Paused")
    }

    @Test("A row leaves its path unabridged when the account home is unavailable")
    func unavailableHomeSuppressesAbbreviation() {
        let source = makeSource(
            name: "Claude",
            path: "/Users/reviewer/.claude/skills/",
            isEnabled: true
        )

        let presentation = FolderSettingsRowPresentation(
            source: source,
            state: .available,
            homeDirectory: nil
        )

        #expect(presentation.displayPath == "/Users/reviewer/.claude/skills")
    }

    @Test("An unavailable row exposes a named reconnect action")
    func unavailableStateExposesReconnect() {
        let source = makeSource(
            name: "Team Skills",
            path: "/Volumes/Team/Skills/",
            isEnabled: true
        )

        let presentation = FolderSettingsRowPresentation(
            source: source,
            state: .unavailable,
            homeDirectory: homeDirectory
        )

        #expect(presentation.displayPath == "/Volumes/Team/Skills")
        #expect(presentation.statusText == "Missing")
        #expect(presentation.statusSystemImage == "exclamationmark.triangle.fill")
        #expect(presentation.showsReconnectAction)
        #expect(presentation.stateAccessibilityLabel == "Missing. Reconnect available.")
        #expect(presentation.reconnectAccessibilityLabel == "Reconnect Team Skills")
    }

    private func makeSource(
        name: String,
        path: String,
        isEnabled: Bool
    ) -> SkillSource {
        SkillSource(
            name: name,
            directoryURL: URL(filePath: path, directoryHint: .isDirectory),
            isEnabled: isEnabled
        )
    }
}
