import AppKit
import SkillsCore
import SwiftUI

struct SkillCatalogView: View {
    @Bindable var catalogModel: SkillCatalogModel
    @Bindable var libraryModel: SkillLibraryModel

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSkillID: CatalogSkill.ID?
    @State private var selectedSourceIDs: Set<SkillSource.ID> = []
    @State private var presentedError: CatalogPresentedError?
    @State private var didCopyCommand = false

    var body: some View {
        NavigationSplitView {
            resultList
                .navigationTitle("Discover Skills")
                .navigationSubtitle(resultSubtitle)
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 460)
        } detail: {
            detail
                .frame(minWidth: 460)
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
        .task {
            await catalogModel.loadTopDownloads()
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
            reconcileSourceSelection()
        }
        .onChange(of: libraryModel.sources) {
            reconcileSourceSelection()
        }
        .onChange(of: catalogModel.results) {
            if let selectedSkillID,
                catalogModel.results.contains(where: { $0.id == selectedSkillID }) == false
            {
                self.selectedSkillID = nil
            }
        }
        .onChange(of: selectedSkillID) {
            didCopyCommand = false
        }
        .alert(item: $presentedError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultList: some View {
        if catalogModel.isLoading && catalogModel.results.isEmpty {
            VStack(spacing: SkillsManagerSpacing.large) {
                ProgressView()
                Text(
                    catalogModel.isShowingTopDownloads
                        ? "Loading the most downloaded skills…"
                        : "Searching skills.sh…"
                )
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = catalogModel.errorMessage {
            ContentUnavailableView {
                Label("skills.sh Unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                if catalogModel.isShowingTopDownloads {
                    Button("Try Again") {
                        Task { await catalogModel.refreshTopDownloads() }
                    }
                }
            }
        } else if catalogModel.results.isEmpty {
            emptyResults
        } else {
            List(selection: $selectedSkillID) {
                Section(resultSectionTitle) {
                    ForEach(catalogModel.results) { skill in
                        CatalogSkillRow(skill: skill)
                            .tag(skill.id)
                            .contextMenu {
                                catalogContextMenu(for: skill)
                            }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private var emptyResults: some View {
        if catalogModel.isShowingTopDownloads {
            ContentUnavailableView(
                "No Skills to Show",
                systemImage: "globe",
                description: Text("skills.sh did not return any skills. Try searching instead.")
            )
        } else {
            ContentUnavailableView.search(text: catalogModel.query)
        }
    }

    private var resultSectionTitle: String {
        catalogModel.isShowingTopDownloads ? "Top Downloads" : "Most Downloaded Matches"
    }

    private var resultSubtitle: String {
        let count = catalogModel.results.count
        guard count > 0 else {
            return catalogModel.isShowingTopDownloads ? "Top downloads" : "No matches"
        }

        let noun = count == 1 ? "skill" : "skills"
        return catalogModel.isShowingTopDownloads
            ? "Top \(count) \(noun) by downloads"
            : "\(count) \(noun) by downloads"
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let selectedSkill {
            catalogDetail(for: selectedSkill)
        } else {
            ContentUnavailableView(
                "No Catalog Skill Selected",
                systemImage: "sparkles",
                description: Text("Choose a skill to review its source and install it.")
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

                HStack(spacing: SkillsManagerSpacing.large) {
                    LabeledContent("Downloads") {
                        Text(skill.installs, format: .number)
                            .monospacedDigit()
                    }
                    .fixedSize()

                    Spacer(minLength: SkillsManagerSpacing.small)

                    if let pageURL = skill.pageURL {
                        Link(destination: pageURL) {
                            Label("View on skills.sh", systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint("Opens the skill's page on skills.sh in your browser.")
                    }
                }

                installCommandSection(for: skill)

                Divider()

                installSection(for: skill)
            }
            .padding(SkillsManagerSpacing.extraExtraLarge)
            .frame(maxWidth: 680, alignment: .leading)
        }
    }

    @ViewBuilder
    private func installCommandSection(for skill: CatalogSkill) -> some View {
        if let command = skill.installCommand {
            VStack(alignment: .leading, spacing: SkillsManagerSpacing.small) {
                Text("Install Command")
                    .font(.headline)

                HStack(alignment: .firstTextBaseline, spacing: SkillsManagerSpacing.medium) {
                    Text(command.displayText)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        copy(command.displayText)
                    } label: {
                        Label(
                            didCopyCommand ? "Copied" : "Copy",
                            systemImage: didCopyCommand ? "checkmark" : "document.on.document"
                        )
                    }
                    .accessibilityLabel("Copy install command")
                }
                .padding(SkillsManagerSpacing.medium)
                .background(
                    Color(nsColor: .controlBackgroundColor),
                    in: .rect(cornerRadius: SkillsManagerRadius.card)
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: SkillsManagerRadius.card,
                        style: .continuous
                    )
                    .stroke(Color(nsColor: .separatorColor))
                }

                Label(
                    """
                    Installing here performs this command's work natively: Skills Manager \
                    downloads the same files over HTTPS and copies them into the directories \
                    you select. Nothing from skills.sh is run on your Mac.
                    """,
                    systemImage: "checkmark.shield"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func installSection(for skill: CatalogSkill) -> some View {
        if installableSources.isEmpty {
            ContentUnavailableView(
                "Add an Agent Directory First",
                systemImage: "folder.badge.plus",
                description: Text(
                    "Close Discover Skills, then add a Codex, Claude Code, or other agent directory."
                )
            )
        } else if skill.isInstallable == false {
            Label(
                "This skill's source is not an installable GitHub repository.",
                systemImage: "exclamationmark.triangle"
            )
            .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: SkillsManagerSpacing.medium) {
                HStack {
                    Text("Install In")
                        .font(.headline)

                    Spacer(minLength: SkillsManagerSpacing.small)

                    if installableSources.count > 1 {
                        Button(areAllSourcesSelected ? "Deselect All" : "Select All") {
                            toggleAllSources()
                        }
                        .buttonStyle(.link)
                    }
                }

                ForEach(installableSources) { source in
                    sourceToggle(for: source, skill: skill)
                }

                Button {
                    install(skill)
                } label: {
                    if catalogModel.installingSkillID == skill.id {
                        HStack(spacing: SkillsManagerSpacing.small) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Installing…")
                        }
                    } else {
                        Label(installButtonTitle(for: skill), systemImage: "square.and.arrow.down")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    destinations(for: skill).isEmpty
                        || catalogModel.installingSkillID != nil
                )

                if let hint = installHint(for: skill) {
                    Label(hint.message, systemImage: hint.systemImage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func sourceToggle(for source: SkillSource, skill: CatalogSkill) -> some View {
        let isAlreadyInstalled = isInstalled(skill, in: source.id)

        return Toggle(isOn: sourceSelection(for: source.id)) {
            HStack(spacing: SkillsManagerSpacing.small) {
                Label(
                    "\(source.agent.displayName) — \(source.displayName)",
                    systemImage: source.agent.systemImage
                )

                if isAlreadyInstalled {
                    Text("Installed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.checkbox)
        .disabled(isAlreadyInstalled)
        .accessibilityLabel(
            isAlreadyInstalled
                ? "\(source.agent.displayName), \(source.displayName), already installed"
                : "\(source.agent.displayName), \(source.displayName)"
        )
    }

    @ViewBuilder
    private func catalogContextMenu(for skill: CatalogSkill) -> some View {
        if let pageURL = skill.pageURL {
            Link("View on skills.sh", destination: pageURL)
        }

        if let command = skill.installCommand {
            Button("Copy Install Command", systemImage: "document.on.document") {
                copy(command.displayText)
            }
        }

        Button(installButtonTitle(for: skill), systemImage: "square.and.arrow.down") {
            selectedSkillID = skill.id
            install(skill)
        }
        .disabled(destinations(for: skill).isEmpty || catalogModel.installingSkillID != nil)
    }

    // MARK: - Selection

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

    private var areAllSourcesSelected: Bool {
        installableSources.isEmpty == false
            && installableSources.allSatisfy { selectedSourceIDs.contains($0.id) }
    }

    private func sourceSelection(for sourceID: SkillSource.ID) -> Binding<Bool> {
        Binding(
            get: { selectedSourceIDs.contains(sourceID) },
            set: { isSelected in
                if isSelected {
                    selectedSourceIDs.insert(sourceID)
                } else {
                    selectedSourceIDs.remove(sourceID)
                }
            }
        )
    }

    private func toggleAllSources() {
        if areAllSourcesSelected {
            selectedSourceIDs.removeAll()
        } else {
            selectedSourceIDs = Set(installableSources.map(\.id))
        }
    }

    /// Drops directories that are no longer installable and keeps one selected so the
    /// install button is reachable as soon as a skill is chosen.
    private func reconcileSourceSelection() {
        let availableIDs = Set(installableSources.map(\.id))
        selectedSourceIDs.formIntersection(availableIDs)

        if selectedSourceIDs.isEmpty, let firstSource = installableSources.first {
            selectedSourceIDs = [firstSource.id]
        }
    }

    /// The selected directories that do not already contain this skill.
    private func destinations(for skill: CatalogSkill) -> [SkillSource] {
        guard skill.isInstallable else {
            return []
        }

        return installableSources.filter {
            selectedSourceIDs.contains($0.id) && isInstalled(skill, in: $0.id) == false
        }
    }

    private func installButtonTitle(for skill: CatalogSkill) -> String {
        let count = destinations(for: skill).count
        return count > 1 ? "Install in \(count) Directories" : "Install Skill"
    }

    /// Explains a disabled install button, so an unavailable action is never silent.
    private func installHint(
        for skill: CatalogSkill
    ) -> (message: String, systemImage: String)? {
        guard destinations(for: skill).isEmpty else {
            return nil
        }

        guard selectedSourceIDs.isEmpty == false else {
            return ("Select at least one directory to install into.", "info.circle")
        }

        return ("Already installed in every selected directory.", "checkmark.circle")
    }

    private func isInstalled(_ skill: CatalogSkill, in sourceID: SkillSource.ID) -> Bool {
        libraryModel.skills.contains {
            $0.sourceID == sourceID
                && $0.directoryURL.lastPathComponent == skill.slug
        }
    }

    // MARK: - Actions

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        didCopyCommand = true
    }

    private func install(_ skill: CatalogSkill) {
        let destinations = destinations(for: skill)
        guard destinations.isEmpty == false else {
            return
        }

        Task { @MainActor in
            let outcomes = await catalogModel.install(skill, into: destinations)

            for outcome in outcomes where outcome.didSucceed {
                do {
                    try await libraryModel.rescanSource(outcome.sourceID)
                } catch {
                    libraryModel.report(
                        error,
                        title: "Unable to Scan \(outcome.sourceName)"
                    )
                }
            }

            if let installed = outcomes.first(where: { $0.didSucceed }),
                let installedURL = installed.installedURL
            {
                libraryModel.selectSkill(at: installedURL, sourceID: installed.sourceID)
            }

            let failures = outcomes.filter { $0.didSucceed == false }
            guard failures.isEmpty == false else {
                return
            }

            presentedError = CatalogPresentedError(
                title: "Unable to Install \(skill.name)",
                message:
                    failures
                    .map { "\($0.sourceName): \($0.errorMessage ?? "Unknown error.")" }
                    .joined(separator: "\n")
            )
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

            Label {
                Text(skill.installs, format: .number.notation(.compactName))
                    .monospacedDigit()
            } icon: {
                Image(systemName: "arrow.down.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
        }
        .padding(.vertical, SkillsManagerSpacing.extraSmall)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(skill.name), \(skill.source), \(skill.installs) downloads"
        )
    }
}

private struct CatalogPresentedError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
