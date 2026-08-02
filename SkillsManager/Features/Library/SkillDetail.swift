import Foundation
import SkillsCore
import SwiftUI

struct SkillDetail: View {
    @Bindable var model: SkillLibraryModel
    @State private var selectedTab = DetailTab.overview
    @State private var skillIDsPendingRemoval: Set<AgentSkill.ID> = []

    var body: some View {
        Group {
            if model.selectedSkills.count > 1 {
                multipleSelection
            } else if let skill = model.selectedSkill {
                loadedDetail(skill)
            } else {
                ContentUnavailableView(
                    "No Skill Selected",
                    systemImage: "wand.and.stars"
                )
            }
        }
        .frame(minWidth: 420)
        .confirmationDialog(
            skillIDsPendingRemoval.count == 1 ? "Remove Skill?" : "Remove Selected Skills?",
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
            Button("Remove from Disk", role: .destructive) {
                let skillIDs = skillIDsPendingRemoval
                skillIDsPendingRemoval.removeAll()
                Task { @MainActor in
                    await model.removeSkills(skillIDs)
                }
            }
            Button("Cancel", role: .cancel) {
                skillIDsPendingRemoval.removeAll()
            }
        } message: {
            Text("This permanently removes the selected skill folders from disk.")
        }
        .onChange(of: model.selectedSkill?.id) {
            selectedTab = .overview
        }
    }

    private func loadedDetail(_ skill: AgentSkill) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SkillsManagerSpacing.extraLarge) {
                header(for: skill)
                statusChips(for: skill)
                actionBar(for: skill)
                tabBar
                tabContent(for: skill)
            }
            .padding(SkillsManagerSpacing.extraExtraLarge)
            .frame(maxWidth: 680, alignment: .leading)
        }
    }

    private func header(for skill: AgentSkill) -> some View {
        HStack(alignment: .top, spacing: SkillsManagerSpacing.large) {
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 64, height: 64)
                .background(
                    Color.secondary.opacity(0.14),
                    in: .rect(cornerRadius: SkillsManagerRadius.card)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SkillsManagerSpacing.extraSmall) {
                Text(skill.name)
                    .font(.title.bold())
                    .textSelection(.enabled)

                Text(skill.summary)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statusChips(for skill: AgentSkill) -> some View {
        FlowLayout(spacing: SkillsManagerSpacing.small) {
            if model.isMutating(skill.id) {
                StatusChip(title: "WORKING", systemImage: "arrow.triangle.2.circlepath")
            }

            if skill.hasUpdate {
                StatusChip(
                    title: "UPDATE AVAILABLE",
                    systemImage: "arrow.down.circle",
                    isEmphasized: true
                )
            }

            if let installedVersion = skill.installedVersion {
                let title =
                    if let availableVersion = skill.availableVersion, skill.hasUpdate {
                        "\(installedVersion) → \(availableVersion)"
                    } else {
                        installedVersion
                    }
                StatusChip(title: title)
            }

            StatusChip(
                title: model.sourceName(for: skill),
                systemImage: "folder"
            )

            if skill.isEnabled == false {
                StatusChip(title: "DISABLED", systemImage: "pause.circle")
            }
        }
    }

    private func actionBar(for skill: AgentSkill) -> some View {
        HStack(spacing: SkillsManagerSpacing.small) {
            if skill.hasUpdate {
                Button(
                    "Update to \(skill.availableVersion ?? "Latest")",
                    systemImage: "arrow.down.circle"
                ) {
                    Task { @MainActor in
                        await model.updateSkills([skill.id])
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isMutating(skill.id))
            }

            Button(skill.isEnabled ? "Disable" : "Enable") {
                model.setSkillsEnabled(!skill.isEnabled, skillIDs: [skill.id])
            }
            .buttonStyle(.bordered)
            .disabled(model.isMutating(skill.id))

            Button("Remove…") {
                skillIDsPendingRemoval = [skill.id]
            }
            .buttonStyle(.bordered)
            .disabled(model.isMutating(skill.id))
        }
    }

    private var tabBar: some View {
        HStack(spacing: SkillsManagerSpacing.extraLarge) {
            ForEach(DetailTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: SkillsManagerSpacing.small) {
                        Text(tab.title)
                            .font(.headline)
                            .foregroundStyle(
                                selectedTab == tab
                                    ? Color.primary
                                    : Color.secondary
                            )

                        Rectangle()
                            .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @ViewBuilder
    private func tabContent(for skill: AgentSkill) -> some View {
        switch selectedTab {
        case .overview:
            VStack(alignment: .leading, spacing: SkillsManagerSpacing.extraLarge) {
                Text(skill.attributedOverview)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .textSelection(.enabled)

                metadata(for: skill)
            }
        case .files:
            VStack(alignment: .leading, spacing: SkillsManagerSpacing.medium) {
                Label("SKILL.md", systemImage: "doc.text")
                    .font(.headline)
                Text(skill.directoryURL.path(percentEncoded: false))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        case .history:
            if let lastScannedAt = skill.lastScannedAt {
                Label {
                    VStack(alignment: .leading, spacing: SkillsManagerSpacing.extraSmall) {
                        Text("Scanned")
                            .font(.headline)
                        Text(lastScannedAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.tint)
                }
            } else {
                ContentUnavailableView(
                    "No History",
                    systemImage: "clock",
                    description: Text("Scan activity will appear here.")
                )
            }
        }
    }

    private func metadata(for skill: AgentSkill) -> some View {
        VStack(spacing: 0) {
            if let author = skill.author {
                metadataRow(label: "Author", value: author)
                Divider()
            }

            if let installedVersion = skill.installedVersion {
                metadataRow(label: "Installed version", value: installedVersion, monospaced: true)
                Divider()
            }

            if let availableVersion = skill.availableVersion {
                metadataRow(label: "Latest version", value: availableVersion, monospaced: true)
                Divider()
            }

            metadataRow(
                label: "Folder",
                value: skill.directoryURL.lastPathComponent,
                monospaced: true
            )
            Divider()
            metadataRow(label: "Status", value: skill.isEnabled ? "Enabled" : "Disabled")

            if let lastScannedAt = skill.lastScannedAt {
                Divider()
                metadataRow(
                    label: "Last scanned",
                    value: lastScannedAt.formatted(date: .abbreviated, time: .shortened)
                )
            }
        }
        .padding(.horizontal, SkillsManagerSpacing.large)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: .rect(cornerRadius: SkillsManagerRadius.card)
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: SkillsManagerRadius.card,
                style: .continuous
            )
            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }

    private func metadataRow(
        label: String,
        value: String,
        monospaced: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SkillsManagerSpacing.large) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 160, alignment: .leading)

            Text(value)
                .font(
                    monospaced
                        ? .system(.subheadline, design: .monospaced)
                        : .subheadline
                )
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .padding(.vertical, SkillsManagerSpacing.medium)
    }

    private var multipleSelection: some View {
        VStack(spacing: SkillsManagerSpacing.large) {
            Text("\(model.selectedSkills.count) Skills Selected")
                .font(.largeTitle.bold())
                .monospacedDigit()

            Text(multipleSelectionDescription)
                .font(.title3)
                .foregroundStyle(.secondary)

            HStack(spacing: SkillsManagerSpacing.small) {
                Button(bulkUpdateTitle, systemImage: "arrow.down.circle") {
                    let skillIDs = model.selectedSkillIDs
                    Task { @MainActor in
                        await model.updateSkills(skillIDs)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    model.selectedSkills.contains(where: \.hasUpdate) == false
                        || selectedSkillsAreMutating
                )

                Button(bulkEnablementTitle) {
                    model.setSkillsEnabled(
                        model.selectedSkills.allSatisfy { $0.isEnabled == false },
                        skillIDs: model.selectedSkillIDs
                    )
                }
                .buttonStyle(.bordered)
                .disabled(selectedSkillsAreMutating)

                Button("Remove…") {
                    skillIDsPendingRemoval = model.selectedSkillIDs
                }
                .buttonStyle(.bordered)
                .disabled(selectedSkillsAreMutating)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(SkillsManagerSpacing.extraExtraLarge)
    }

    private var multipleSelectionDescription: String {
        let updateCount = model.selectedSkills.filter(\.hasUpdate).count
        if updateCount == model.selectedSkills.count {
            return "All have updates available."
        }
        if updateCount > 0 {
            return "\(updateCount) have updates available."
        }
        return "Manage the selected skills together."
    }

    private var bulkUpdateTitle: String {
        model.selectedSkills.count == 2 ? "Update Both" : "Update Selected"
    }

    private var bulkEnablementTitle: String {
        model.selectedSkills.allSatisfy { $0.isEnabled == false } ? "Enable" : "Disable"
    }

    private var selectedSkillsAreMutating: Bool {
        model.selectedSkills.contains { model.isMutating($0.id) }
    }
}

private enum DetailTab: String, CaseIterable, Identifiable {
    case overview
    case files
    case history

    var id: Self { self }

    var title: String {
        rawValue.capitalized
    }
}

private struct StatusChip: View {
    let title: String
    var systemImage: String?
    var isEmphasized = false

    var body: some View {
        HStack(spacing: SkillsManagerSpacing.extraSmall) {
            if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            Text(title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(isEmphasized ? Color.accentColor : Color.secondary)
        .padding(.horizontal, SkillsManagerSpacing.medium)
        .padding(.vertical, SkillsManagerSpacing.extraSmall)
        .background(
            isEmphasized
                ? Color.accentColor.opacity(0.12)
                : Color.secondary.opacity(0.1),
            in: .rect(cornerRadius: SkillsManagerRadius.chip)
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: SkillsManagerRadius.chip,
                style: .continuous
            )
            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    private let content: Content

    init(
        spacing: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) {
                content
            }

            VStack(alignment: .leading, spacing: spacing) {
                content
            }
        }
    }
}
