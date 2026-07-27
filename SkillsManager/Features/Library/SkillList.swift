import AppKit
import SkillsCore
import SwiftUI

struct SkillList: View {
    @Bindable var model: SkillLibraryModel
    let addDirectory: (SkillAgent, URL?) -> Void
    @State private var skillIDsPendingRemoval: Set<AgentSkill.ID> = []

    var body: some View {
        Group {
            if model.visibleSkills.isEmpty {
                emptyState
            } else {
                List(model.visibleSkills, selection: $model.selectedSkillIDs) { skill in
                    SkillRow(
                        skill: skill,
                        isSelected: model.selectedSkillIDs.contains(skill.id),
                        agentName: model.agentName(for: skill),
                        sourceName: model.sourceName(for: skill)
                    )
                    .tag(skill.id)
                    .contextMenu {
                        skillContextMenu(skill)
                    }
                }
                .listStyle(.inset)
                .overlay(alignment: .bottom) {
                    if model.selectedSkillIDs.count > 1 {
                        bulkActionBar
                            .padding(SkillsManagerSpacing.large)
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 460)
        .confirmationDialog(
            removalTitle,
            isPresented: Binding(
                get: { skillIDsPendingRemoval.isEmpty == false },
                set: { isPresented in
                    if isPresented == false {
                        skillIDsPendingRemoval.removeAll()
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove from Library", role: .destructive) {
                model.removeSkills(skillIDsPendingRemoval)
                skillIDsPendingRemoval.removeAll()
            }
            Button("Cancel", role: .cancel) {
                skillIDsPendingRemoval.removeAll()
            }
        } message: {
            Text("The skill folders remain on disk.")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyContent.title, systemImage: emptyContent.systemImage)
        } description: {
            Text(emptyContent.description)
        } actions: {
            switch emptyContent.action {
            case .addDirectory:
                Menu("Add Agent Directory", systemImage: "folder.badge.plus") {
                    AgentDirectoryMenuContent(chooseDirectory: addDirectory)
                }
                .menuStyle(.button)
                .buttonStyle(.borderedProminent)
            case .rescan(let sourceID):
                Button("Rescan") {
                    Task { @MainActor in
                        do {
                            try await model.rescanSource(sourceID)
                        } catch {
                            model.report(error, title: "Unable to Scan Directory")
                        }
                    }
                }
            case .searchAll:
                Button("Search All Skills") {
                    model.searchAllSkills()
                }
            case nil:
                EmptyView()
            }
        }
    }

    private var bulkActionBar: some View {
        HStack(spacing: SkillsManagerSpacing.medium) {
            Text("\(model.selectedSkillIDs.count) selected")
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button(bulkUpdateTitle, systemImage: "arrow.down.circle") {
                model.updateSkills(model.selectedSkillIDs)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedSkillsWithUpdates.isEmpty)

            Button("Cancel") {
                model.selectedSkillIDs.removeAll()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, SkillsManagerSpacing.large)
        .padding(.vertical, SkillsManagerSpacing.medium)
        .skillsManagerPanel()
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func skillContextMenu(_ skill: AgentSkill) -> some View {
        if skill.hasUpdate {
            Button("Update", systemImage: "arrow.down.circle") {
                model.updateSkills([skill.id])
            }
        }

        Button(
            skill.isEnabled ? "Disable" : "Enable",
            systemImage: skill.isEnabled ? "pause.circle" : "play.circle"
        ) {
            model.setSkillsEnabled(!skill.isEnabled, skillIDs: [skill.id])
        }

        Button("Reveal in Finder", systemImage: "finder") {
            NSWorkspace.shared.activateFileViewerSelecting([skill.directoryURL])
        }

        Button("Open SKILL.md", systemImage: "doc.text") {
            NSWorkspace.shared.open(
                skill.directoryURL.appending(path: "SKILL.md", directoryHint: .notDirectory)
            )
        }

        Button("Copy Path", systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(
                skill.directoryURL.path(percentEncoded: false),
                forType: .string
            )
        }

        Divider()

        Button("Remove…", systemImage: "minus.circle", role: .destructive) {
            skillIDsPendingRemoval = [skill.id]
        }
    }

    private var selectedSkillsWithUpdates: Set<AgentSkill.ID> {
        Set(model.selectedSkills.filter(\.hasUpdate).map(\.id))
    }

    private var bulkUpdateTitle: String {
        model.selectedSkillIDs.count == 2 ? "Update Both" : "Update Selected"
    }

    private var removalTitle: String {
        skillIDsPendingRemoval.count == 1 ? "Remove Skill?" : "Remove Selected Skills?"
    }

    private var emptyContent: EmptyContent {
        if model.sources.isEmpty {
            return EmptyContent(
                title: "Build Your Skill Library",
                systemImage: "sparkles",
                description: "Add a directory to start managing skills.",
                action: .addDirectory
            )
        }

        if model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            let description: String
            if case .source(let sourceID) = model.sidebarSelection,
                let source = model.source(for: sourceID)
            {
                description =
                    "Nothing in \(source.displayName) matches “\(model.searchText)”."
            } else {
                description = "Try a different name, description, author, or folder."
            }

            return EmptyContent(
                title: "No Matching Skills",
                systemImage: "magnifyingglass",
                description: description,
                action: model.canSearchAllSkills ? .searchAll : nil
            )
        }

        switch model.sidebarSelection {
        case .source(let sourceID):
            return EmptyContent(
                title: "No Skills in This Directory",
                systemImage: "folder",
                description: "Skills Manager looks for folders containing a SKILL.md manifest.",
                action: .rescan(sourceID)
            )
        case .updatesAvailable:
            return EmptyContent(
                title: "All Skills Are Up to Date",
                systemImage: "checkmark.circle",
                description: "There are no updates available.",
                action: nil
            )
        case .disabled:
            return EmptyContent(
                title: "No Disabled Skills",
                systemImage: "pause.circle",
                description: "Disabled skills will appear here.",
                action: nil
            )
        case .recentlyAdded:
            return EmptyContent(
                title: "No Recently Added Skills",
                systemImage: "clock",
                description: "Skills added in the last 14 days will appear here.",
                action: nil
            )
        case .allSkills:
            return EmptyContent(
                title: "No Skills Found",
                systemImage: "wand.and.stars",
                description: "Add a directory or rescan an existing one.",
                action: .addDirectory
            )
        }
    }
}

private struct SkillRow: View {
    let skill: AgentSkill
    let isSelected: Bool
    let agentName: String
    let sourceName: String

    var body: some View {
        HStack(spacing: SkillsManagerSpacing.medium) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                .frame(width: 44, height: 44)
                .background(
                    isSelected
                        ? Color.white.opacity(0.2)
                        : Color.secondary.opacity(0.12),
                    in: .rect(cornerRadius: SkillsManagerRadius.row)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.headline)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .lineLimit(1)

                Text(skill.summary)
                    .font(.subheadline)
                    .foregroundStyle(
                        isSelected
                            ? Color.white.opacity(0.84)
                            : Color.secondary
                    )
                    .lineLimit(1)

                Text("\(agentName) • \(sourceName)")
                    .font(.caption)
                    .foregroundStyle(
                        isSelected
                            ? Color.white.opacity(0.72)
                            : Color.secondary
                    )
                    .lineLimit(1)
            }

            Spacer(minLength: SkillsManagerSpacing.small)

            HStack(spacing: SkillsManagerSpacing.small) {
                if skill.hasUpdate {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                        .accessibilityLabel("Update available")
                }

                if skill.isEnabled == false {
                    Image(systemName: "pause.circle")
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                        .accessibilityLabel("Disabled")
                }
            }
        }
        .opacity(skill.isEnabled ? 1 : 0.55)
        .padding(.vertical, SkillsManagerSpacing.extraSmall)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        [
            skill.name,
            skill.summary,
            agentName,
            sourceName,
            skill.hasUpdate ? "Update available" : nil,
            skill.isEnabled ? nil : "Disabled",
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

private struct EmptyContent {
    enum Action {
        case addDirectory
        case rescan(SkillSource.ID)
        case searchAll
    }

    let title: String
    let systemImage: String
    let description: String
    let action: Action?
}
