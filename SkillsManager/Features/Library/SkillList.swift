import SkillsCore
import SwiftUI

struct SkillList: View {
    @Bindable var model: SkillLibraryModel
    let addDirectory: () -> Void

    var body: some View {
        Group {
            if model.visibleSkills.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: emptySystemImage)
                } description: {
                    Text(emptyDescription)
                } actions: {
                    if model.sources.isEmpty {
                        Button("Add Skill Directory", action: addDirectory)
                    }
                }
            } else {
                List(model.visibleSkills, selection: $model.selectedSkillID) { skill in
                    SkillRow(skill: skill)
                        .tag(skill.id)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Skills")
        .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 420)
    }

    private var emptyTitle: String {
        if model.searchText.isEmpty {
            return model.sources.isEmpty ? "Build Your Skill Library" : "No Skills Found"
        }

        return "No Matching Skills"
    }

    private var emptySystemImage: String {
        model.searchText.isEmpty ? "sparkles" : "magnifyingglass"
    }

    private var emptyDescription: String {
        if model.searchText.isEmpty {
            if model.sources.isEmpty {
                return "Add a directory to start discovering and managing agent skills."
            }

            return "This directory does not contain any discovered skills yet."
        }

        return "Try a different name, description, author, or folder."
    }
}

private struct SkillRow: View {
    let skill: AgentSkill

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wand.and.sparkles")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(skill.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(skill.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if skill.managementState == .updateAvailable {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Update available")
            }
        }
        .padding(.vertical, 4)
    }
}
