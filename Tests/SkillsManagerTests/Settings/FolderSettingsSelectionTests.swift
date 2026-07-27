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

    @Test("Reconciliation selects a remaining folder and clears an empty list")
    func selectsRemainingSourceThenClearsEmptyList() {
        let removed = makeSource(name: "Claude", path: "/skills/claude")
        let remaining = makeSource(name: "Codex", path: "/skills/codex")
        var selection = FolderSettingsSelection(sourceID: removed.id)

        selection.reconcile(with: [remaining])

        #expect(selection.sourceID == remaining.id)

        selection.reconcile(with: [])

        #expect(selection.sourceID == nil)
    }

    private func makeSource(name: String, path: String) -> SkillSource {
        SkillSource(
            name: name,
            directoryURL: URL(filePath: path, directoryHint: .isDirectory)
        )
    }
}
