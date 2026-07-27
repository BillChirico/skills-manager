import Foundation
import SkillsCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var model: SkillLibraryModel
    @State private var folderSelection = FolderSettingsSelection()
    @State private var isChoosingFolder = false
    @State private var newFolderAgent = SkillAgent.other
    @State private var folderDialogDefaultDirectory: URL?
    @State private var sourceBeingRemoved: SkillSource?

    var body: some View {
        VStack(alignment: .leading, spacing: SkillsManagerSpacing.extraLarge) {
            VStack(alignment: .leading, spacing: SkillsManagerSpacing.small) {
                Text("Skill Folders")
                    .font(.title2.weight(.semibold))

                Text(
                    "Choose the folders Skills Manager scans. Removing a folder here never deletes its files."
                )
                .foregroundStyle(.secondary)
            }

            folderPanel

            VStack(alignment: .leading, spacing: SkillsManagerSpacing.medium) {
                Text("Discovery")
                    .font(.headline)

                LabeledContent("Catalog") {
                    Text("skills.sh")
                        .foregroundStyle(.secondary)
                }

                Text(
                    "Search skills.sh and install into any enabled agent folder."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .padding(SkillsManagerSpacing.extraExtraLarge)
        .frame(width: 640, height: 520)
        .fileImporter(
            isPresented: $isChoosingFolder,
            allowedContentTypes: [.directory],
            allowsMultipleSelection: false,
            onCompletion: handleFolderImport
        )
        .fileDialogDefaultDirectory(folderDialogDefaultDirectory)
        .confirmationDialog(
            "Remove Folder?",
            isPresented: Binding(
                get: { sourceBeingRemoved != nil },
                set: { isPresented in
                    if isPresented == false {
                        sourceBeingRemoved = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Folder", role: .destructive) {
                guard let source = sourceBeingRemoved else {
                    return
                }
                sourceBeingRemoved = nil
                perform("Unable to Remove Folder") {
                    try await model.removeSource(source.id)
                }
            }
            Button("Cancel", role: .cancel) {
                sourceBeingRemoved = nil
            }
        } message: {
            if let sourceBeingRemoved {
                Text(
                    "This removes “\(sourceBeingRemoved.displayName)” from Skills Manager. Its files stay on disk."
                )
            }
        }
        .alert(item: $model.presentedError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .task {
            await model.restoreSources()
        }
        .onChange(of: model.sources.map(\.id), initial: true) {
            folderSelection.reconcile(with: model.sources)
        }
    }

    private var folderPanel: some View {
        VStack(spacing: 0) {
            Group {
                if model.sources.isEmpty {
                    ContentUnavailableView(
                        "No Skill Folders",
                        systemImage: "folder",
                        description: Text("Use the add button below to choose a folder.")
                    )
                } else {
                    List(model.sources, selection: $folderSelection.sourceID) { source in
                        folderRow(source)
                            .tag(source.id)
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220)

            Divider()

            HStack {
                ControlGroup {
                    addFolderMenu

                    Button {
                        sourceBeingRemoved = selectedSource
                    } label: {
                        Label("Remove Selected Folder", systemImage: "minus")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(selectedSource == nil)
                    .help("Remove the selected folder from Skills Manager")
                }
                .controlSize(.small)

                Spacer()

                Text(
                    model.sources.count == 1
                        ? "1 folder"
                        : "\(model.sources.count) folders"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            .padding(.horizontal, SkillsManagerSpacing.small)
            .padding(.vertical, SkillsManagerSpacing.extraSmall)
        }
        .skillsManagerPanel(cornerRadius: SkillsManagerRadius.card)
    }

    private var addFolderMenu: some View {
        Menu {
            AgentDirectoryMenuContent { agent, defaultDirectory in
                newFolderAgent = agent
                folderDialogDefaultDirectory = defaultDirectory
                isChoosingFolder = true
            }
        } label: {
            Label("Add Folder", systemImage: "plus")
                .labelStyle(.iconOnly)
        }
        .help("Add a folder that contains an agent’s skills")
    }

    private var selectedSource: SkillSource? {
        guard let sourceID = folderSelection.sourceID else {
            return nil
        }

        return model.source(for: sourceID)
    }

    private func folderRow(_ source: SkillSource) -> some View {
        HStack(spacing: SkillsManagerSpacing.medium) {
            Image(systemName: source.agent.systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: SkillsManagerSpacing.small) {
                    Text(source.displayName)
                        .font(.headline)
                        .lineLimit(1)

                    Text(source.agent.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(source.directoryURL.path(percentEncoded: false))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(source.directoryURL.path(percentEncoded: false))
            }

            Spacer(minLength: SkillsManagerSpacing.medium)

            sourceStatus(source)
        }
        .padding(.vertical, SkillsManagerSpacing.extraSmall)
        .opacity(source.isEnabled ? 1 : 0.55)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(source.displayName), \(source.agent.displayName), \(source.directoryURL.path(percentEncoded: false)), \(sourceStatusLabel(source))"
        )
    }

    @ViewBuilder
    private func sourceStatus(_ source: SkillSource) -> some View {
        switch model.sourceState(for: source.id) {
        case .available:
            Image(systemName: source.isEnabled ? "checkmark.circle" : "pause.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        case .scanning:
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)
        case .unavailable:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
        }
    }

    private func sourceStatusLabel(_ source: SkillSource) -> String {
        switch model.sourceState(for: source.id) {
        case .available:
            source.isEnabled ? "available" : "disabled"
        case .scanning:
            "scanning"
        case .unavailable:
            "unavailable"
        }
    }

    private func handleFolderImport(_ result: Result<[URL], any Error>) {
        let agent = newFolderAgent

        Task { @MainActor in
            do {
                guard let folderURL = try result.get().first else {
                    return
                }

                try await model.addSource(at: folderURL, agent: agent)
                folderSelection.reconcile(with: model.sources)

                if case .source(let sourceID) = model.sidebarSelection {
                    folderSelection.sourceID = sourceID
                }
            } catch {
                model.report(error, title: "Unable to Add Folder")
            }
        }
    }

    private func perform(
        _ errorTitle: String,
        operation: @escaping @MainActor () async throws -> Void
    ) {
        Task { @MainActor in
            do {
                try await operation()
            } catch {
                model.report(error, title: errorTitle)
            }
        }
    }
}

struct FolderSettingsSelection {
    var sourceID: SkillSource.ID?

    mutating func reconcile(with sources: [SkillSource]) {
        guard let sourceID else {
            return
        }

        if sources.contains(where: { $0.id == sourceID }) == false {
            self.sourceID = nil
        }
    }
}

struct AgentDirectoryMenuContent: View {
    let chooseDirectory: (SkillAgent, URL?) -> Void
    var homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser

    var body: some View {
        Section("Suggested Locations") {
            ForEach(agentsWithDefaultDirectory) { agent in
                if let relativePath = agent.defaultSkillsDirectoryRelativePath {
                    Button {
                        chooseDirectory(
                            agent,
                            agent.defaultSkillsDirectory(in: homeDirectory)
                        )
                    } label: {
                        Label(
                            "\(agent.displayName) — ~/\(relativePath)",
                            systemImage: agent.systemImage
                        )
                    }
                }
            }
        }

        Section("Choose Another Folder") {
            ForEach(SkillAgent.allCases) { agent in
                Button {
                    chooseDirectory(agent, nil)
                } label: {
                    Label(agent.displayName, systemImage: agent.systemImage)
                }
            }
        }
    }

    private var agentsWithDefaultDirectory: [SkillAgent] {
        SkillAgent.allCases.filter {
            $0.defaultSkillsDirectoryRelativePath != nil
        }
    }
}
