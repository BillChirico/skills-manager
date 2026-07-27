import SkillsCore
import SwiftUI

struct SkillDetail: View {
    let skill: AgentSkill?

    var body: some View {
        if let skill {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header(for: skill)
                    metadata(for: skill)
                }
                .padding(28)
                .frame(maxWidth: 720, alignment: .leading)
            }
            .navigationTitle(skill.name)
        } else {
            ContentUnavailableView(
                "Select a Skill",
                systemImage: "wand.and.stars",
                description: Text("Choose a skill to inspect its details and available actions.")
            )
            .navigationTitle("Details")
        }
    }

    private func header(for skill: AgentSkill) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "wand.and.sparkles")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text(skill.name)
                .font(.largeTitle.bold())

            Text(skill.summary)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private func metadata(for skill: AgentSkill) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
            if let author = skill.author {
                metadataRow(label: "Author", value: author)
            }

            if let version = skill.version {
                metadataRow(label: "Version", value: version)
            }

            metadataRow(label: "Folder", value: skill.directoryURL.lastPathComponent)
            metadataRow(label: "Status", value: skill.managementState.displayName)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .skillsManagerPanel()
    }

    private func metadataRow(label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)

            Text(value)
                .textSelection(.enabled)
        }
    }
}

private extension AgentSkill.ManagementState {
    var displayName: String {
        switch self {
        case .installed:
            "Installed"
        case .updateAvailable:
            "Update Available"
        case .disabled:
            "Disabled"
        }
    }
}
