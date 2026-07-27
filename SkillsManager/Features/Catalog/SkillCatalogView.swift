import SkillsCore
import SwiftUI

struct SkillCatalogView: View {
    @Bindable var catalogModel: SkillCatalogModel
    @Bindable var libraryModel: SkillLibraryModel

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSkillID: CatalogSkill.ID?
    @State private var selectedSourceID: SkillSource.ID?
    @State private var presentedError: CatalogPresentedError?

    var body: some View {
        NavigationSplitView {
            resultList
                .navigationTitle("Discover Skills")
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 460)
        } detail: {
            detail
                .frame(minWidth: 440)
        }
        .searchable(
            text: $catalogModel.query,
            placement: .toolbar,
            prompt: "Search skills.sh"
        )
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .task(id: catalogModel.query) {
            do {
                try await Task.sleep(for: .milliseconds(300))
                await catalogModel.search()
            } catch is CancellationError {
                return
            } catch {
                presentedError = CatalogPresentedError(
                    title: "Unable to Search skills.sh",
                    message: error.localizedDescription
                )
            }
        }
        .task {
            chooseDefaultSource()
        }
        .onChange(of: libraryModel.sources) {
            chooseDefaultSource()
        }
        .onChange(of: catalogModel.results) {
            if let selectedSkillID,
                catalogModel.results.contains(where: { $0.id == selectedSkillID }) == false
            {
                self.selectedSkillID = nil
            }
        }
        .alert(item: $presentedError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private var resultList: some View {
        if catalogModel.isSearching {
            VStack(spacing: SkillsManagerSpacing.large) {
                ProgressView()
                Text("Searching skills.sh…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = catalogModel.searchErrorMessage {
            ContentUnavailableView(
                "Search Unavailable",
                systemImage: "wifi.exclamationmark",
                description: Text(error)
            )
        } else if catalogModel.query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
            ContentUnavailableView(
                "Search skills.sh",
                systemImage: "globe",
                description: Text("Enter at least two characters to find installable skills.")
            )
        } else if catalogModel.results.isEmpty {
            ContentUnavailableView.search(text: catalogModel.query)
        } else {
            List(catalogModel.results, selection: $selectedSkillID) { skill in
                CatalogSkillRow(skill: skill)
                    .tag(skill.id)
                    .contextMenu {
                        catalogContextMenu(for: skill)
                    }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedSkill {
            catalogDetail(for: selectedSkill)
        } else {
            ContentUnavailableView(
                "No Catalog Skill Selected",
                systemImage: "sparkles",
                description: Text("Choose a result to review its source and install it.")
            )
        }
    }

    private func catalogDetail(for skill: CatalogSkill) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SkillsManagerSpacing.extraLarge) {
                VStack(alignment: .leading, spacing: SkillsManagerSpacing.small) {
                    Text(skill.name)
                        .font(.largeTitle.bold())
                        .textSelection(.enabled)

                    Text(skill.source)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                LabeledContent("Installs") {
                    Text(skill.installs, format: .number)
                        .monospacedDigit()
                }

                if let pageURL = skill.pageURL {
                    Link(destination: pageURL) {
                        Label("Review on skills.sh", systemImage: "arrow.up.right.square")
                    }
                }

                Divider()

                if installableSources.isEmpty {
                    ContentUnavailableView(
                        "Add an Agent Directory First",
                        systemImage: "folder.badge.plus",
                        description: Text(
                            "Close Discover Skills, then add a Codex, Claude Code, or other agent directory."
                        )
                    )
                } else {
                    Picker("Install in", selection: $selectedSourceID) {
                        ForEach(installableSources) { source in
                            Label(
                                "\(source.agent.displayName) — \(source.displayName)",
                                systemImage: source.agent.systemImage
                            )
                            .tag(Optional(source.id))
                        }
                    }

                    Button {
                        install(skill)
                    } label: {
                        if catalogModel.installingSkillID == skill.id {
                            ProgressView()
                                .controlSize(.small)
                            Text("Installing…")
                        } else {
                            Label("Install Skill", systemImage: "square.and.arrow.down")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        selectedSource == nil
                            || isInstalled(skill)
                            || catalogModel.installingSkillID != nil
                            || skill.githubRepository == nil
                    )

                    if isInstalled(skill) {
                        Label("Already installed in this directory", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else if skill.githubRepository == nil {
                        Label(
                            "This source is not a GitHub repository and cannot be installed yet.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.secondary)
                    }
                }

                Label(
                    "Skills are copied as files and are not executed during installation. Review their contents before use.",
                    systemImage: "checkmark.shield"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .padding(SkillsManagerSpacing.extraExtraLarge)
            .frame(maxWidth: 680, alignment: .leading)
        }
    }

    @ViewBuilder
    private func catalogContextMenu(for skill: CatalogSkill) -> some View {
        if let pageURL = skill.pageURL {
            Link("View on skills.sh", destination: pageURL)
        }

        if let source = selectedSource {
            Button("Install in \(source.agent.displayName)", systemImage: "square.and.arrow.down") {
                install(skill)
            }
            .disabled(
                isInstalled(skill)
                    || catalogModel.installingSkillID != nil
                    || skill.githubRepository == nil
            )
        }
    }

    private var selectedSkill: CatalogSkill? {
        guard let selectedSkillID else {
            return nil
        }

        return catalogModel.results.first { $0.id == selectedSkillID }
    }

    private var installableSources: [SkillSource] {
        libraryModel.sources.filter {
            $0.isEnabled && libraryModel.sourceState(for: $0.id) == .available
        }
    }

    private var selectedSource: SkillSource? {
        guard let selectedSourceID else {
            return nil
        }

        return installableSources.first { $0.id == selectedSourceID }
    }

    private func chooseDefaultSource() {
        if let selectedSourceID,
            installableSources.contains(where: { $0.id == selectedSourceID })
        {
            return
        }

        selectedSourceID = installableSources.first?.id
    }

    private func isInstalled(_ skill: CatalogSkill) -> Bool {
        guard let selectedSourceID else {
            return false
        }

        return libraryModel.skills.contains {
            $0.sourceID == selectedSourceID
                && $0.directoryURL.lastPathComponent == skill.slug
        }
    }

    private func install(_ skill: CatalogSkill) {
        guard let source = selectedSource else {
            return
        }

        Task { @MainActor in
            do {
                let installedURL = try await catalogModel.install(
                    skill,
                    into: source.directoryURL
                )
                try await libraryModel.rescanSource(source.id)
                libraryModel.selectSkill(at: installedURL, sourceID: source.id)
            } catch {
                presentedError = CatalogPresentedError(
                    title: "Unable to Install \(skill.name)",
                    message: error.localizedDescription
                )
            }
        }
    }
}

private struct CatalogSkillRow: View {
    let skill: CatalogSkill

    var body: some View {
        HStack(spacing: SkillsManagerSpacing.medium) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)
                .background(
                    Color.secondary.opacity(0.12),
                    in: .rect(cornerRadius: SkillsManagerRadius.row)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SkillsManagerSpacing.extraSmall) {
                Text(skill.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(skill.source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: SkillsManagerSpacing.small)

            Text(skill.installs, format: .number.notation(.compactName))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, SkillsManagerSpacing.extraSmall)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(skill.name), \(skill.source), \(skill.installs) installs"
        )
    }
}

private struct CatalogPresentedError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
