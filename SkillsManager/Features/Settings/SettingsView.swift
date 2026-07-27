import Foundation
import SkillsCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    private static let catalogURL: URL = {
        guard let url = URL(string: "https://skills.sh") else {
            preconditionFailure("The skills.sh catalog URL must be valid.")
        }
        return url
    }()

    @Bindable var model: SkillLibraryModel
    @State private var folderSelection = FolderSettingsSelection()
    @State private var isChoosingFolder = false
    @State private var newFolderAgent = SkillAgent.other
    @State private var folderDialogDefaultDirectory: URL?
    @State private var sourceBeingReconnected: SkillSource.ID?
    @State private var sourceBeingRemoved: SkillSource?

    var body: some View {
        Form {
            Section {
                folderPanel
            } header: {
                Text("Skill Folders")
            } footer: {
                Text(
                    "Choose the folders Skills Manager scans. Removing a folder here never deletes its files."
                )
            }

            Section {
                LabeledContent("Catalog") {
                    Link(destination: Self.catalogURL) {
                        Label("skills.sh", systemImage: "arrow.up.right.square")
                            .labelStyle(.titleAndIcon)
                    }
                }
            } header: {
                Text("Discovery")
            } footer: {
                Text(
                    "Search skills.sh and install into any enabled agent folder."
                )
            }
        }
        .formStyle(.grouped)
        .frame(
            minWidth: 620,
            idealWidth: 680,
            maxWidth: .infinity,
            minHeight: 480,
            idealHeight: 560,
            maxHeight: .infinity
        )
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
                    ContentUnavailableView {
                        Label("No Skill Folders", systemImage: "folder")
                    } description: {
                        Text("Add a folder that contains an agent’s skills.")
                    } actions: {
                        emptyStateAddFolderMenu
                    }
                } else {
                    List(model.sources, selection: $folderSelection.sourceID) { source in
                        folderRow(source)
                            .tag(source.id)
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 280)

            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
                .accessibilityHidden(true)

            HStack {
                folderControls

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
        .clipShape(
            .rect(
                cornerRadius: SkillsManagerRadius.card,
                style: .continuous
            )
        )
    }

    @ViewBuilder
    private var folderControls: some View {
        if #available(macOS 26.0, *) {
            folderControlGroup
                .buttonStyle(.glass)
        } else {
            folderControlGroup
        }
    }

    private var folderControlGroup: some View {
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
    }

    private var addFolderMenu: some View {
        Menu {
            AgentDirectoryMenuContent { agent, defaultDirectory in
                beginAddingFolder(
                    for: agent,
                    defaultDirectory: defaultDirectory
                )
            }
        } label: {
            Label("Add Folder", systemImage: "plus")
                .labelStyle(.iconOnly)
        }
        .help("Add a folder that contains an agent’s skills")
    }

    private var emptyStateAddFolderMenu: some View {
        Menu {
            AgentDirectoryMenuContent { agent, defaultDirectory in
                beginAddingFolder(
                    for: agent,
                    defaultDirectory: defaultDirectory
                )
            }
        } label: {
            Label("Add Folder", systemImage: "plus")
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
        let state = model.sourceState(for: source.id)
        let presentation = FolderSettingsRowPresentation(
            source: source,
            state: state
        )

        return HStack(spacing: SkillsManagerSpacing.medium) {
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

                Text(presentation.displayPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(source.directoryURL.path(percentEncoded: false))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(source.displayName), \(source.agent.displayName), \(presentation.displayPath)"
            )

            Spacer(minLength: SkillsManagerSpacing.medium)

            sourceStatus(presentation, state: state)

            if presentation.showsReconnectAction {
                Button("Reconnect…", systemImage: "folder.badge.questionmark") {
                    beginReconnectingFolder(source)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel(presentation.reconnectAccessibilityLabel)
                .help("Choose the current location of \(source.displayName)")
            }

            Toggle(
                "Enabled",
                isOn: Binding(
                    get: { source.isEnabled },
                    set: { isEnabled in
                        setFolderEnabled(isEnabled, source: source)
                    }
                )
            )
            .toggleStyle(.switch)
            .fixedSize()
            .accessibilityLabel(presentation.toggleAccessibilityLabel)
            .accessibilityValue(source.isEnabled ? "On" : "Off")
            .accessibilityHint(presentation.stateAccessibilityLabel)
            .accessibilityActions {
                if presentation.showsReconnectAction {
                    Button(presentation.reconnectAccessibilityLabel) {
                        beginReconnectingFolder(source)
                    }
                }
            }
            .help(
                source.isEnabled
                    ? "Pause scanning \(source.displayName)"
                    : "Resume scanning \(source.displayName)"
            )
        }
        .padding(.vertical, SkillsManagerSpacing.extraSmall)
        .contentShape(.rect)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func sourceStatus(
        _ presentation: FolderSettingsRowPresentation,
        state: SkillLibraryModel.SourceState
    ) -> some View {
        if let statusText = presentation.statusText {
            HStack(spacing: SkillsManagerSpacing.extraSmall) {
                if let statusSystemImage = presentation.statusSystemImage {
                    Image(systemName: statusSystemImage)
                        .foregroundStyle(
                            state == .unavailable
                                ? Color.orange
                                : Color.secondary
                        )
                        .accessibilityHidden(true)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }

                Text(statusText)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .fixedSize()
            .accessibilityElement(children: .combine)
            .accessibilityLabel(presentation.stateAccessibilityLabel)
        }
    }

    private func beginAddingFolder(
        for agent: SkillAgent,
        defaultDirectory: URL?
    ) {
        sourceBeingReconnected = nil
        newFolderAgent = agent
        folderDialogDefaultDirectory = defaultDirectory
        isChoosingFolder = true
    }

    private func beginReconnectingFolder(_ source: SkillSource) {
        sourceBeingReconnected = source.id
        folderDialogDefaultDirectory =
            source.directoryURL
            .deletingLastPathComponent()
        isChoosingFolder = true
    }

    private func setFolderEnabled(
        _ isEnabled: Bool,
        source: SkillSource
    ) {
        guard source.isEnabled != isEnabled else {
            return
        }

        perform("Unable to Update Folder") {
            try await model.setSourceEnabled(
                isEnabled,
                sourceID: source.id
            )
        }
    }

    private func handleFolderImport(_ result: Result<[URL], any Error>) {
        let agent = newFolderAgent
        let reconnectSourceID = sourceBeingReconnected
        let errorTitle =
            reconnectSourceID == nil
            ? "Unable to Add Folder"
            : "Unable to Reconnect Folder"

        Task { @MainActor in
            defer {
                sourceBeingReconnected = nil
                folderDialogDefaultDirectory = nil
            }

            do {
                guard let folderURL = try result.get().first else {
                    return
                }

                if let reconnectSourceID {
                    try await model.relocateSource(
                        reconnectSourceID,
                        to: folderURL
                    )
                    folderSelection.sourceID = reconnectSourceID
                } else {
                    try await model.addSource(at: folderURL, agent: agent)
                    folderSelection.reconcile(with: model.sources)

                    if case .source(let sourceID) = model.sidebarSelection {
                        folderSelection.sourceID = sourceID
                    }
                }
            } catch let error as CocoaError where error.code == .userCancelled {
                return
            } catch {
                model.report(error, title: errorTitle)
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

@MainActor
struct FolderSettingsRowPresentation {
    let displayPath: String
    let statusText: String?
    let statusSystemImage: String?
    let showsReconnectAction: Bool
    let stateAccessibilityLabel: String
    let toggleAccessibilityLabel: String
    let reconnectAccessibilityLabel: String

    init(
        source: SkillSource,
        state: SkillLibraryModel.SourceState,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        displayPath = Self.displayPath(
            for: source.directoryURL,
            homeDirectory: homeDirectory
        )
        toggleAccessibilityLabel = "Enable \(source.displayName)"
        reconnectAccessibilityLabel = "Reconnect \(source.displayName)"

        switch (state, source.isEnabled) {
        case (.unavailable, _):
            statusText = "Missing"
            statusSystemImage = "exclamationmark.triangle.fill"
            showsReconnectAction = true
            stateAccessibilityLabel = "Missing. Reconnect available."
        case (_, false):
            statusText = "Paused"
            statusSystemImage = "pause.circle"
            showsReconnectAction = false
            stateAccessibilityLabel = "Paused"
        case (.available, true):
            statusText = nil
            statusSystemImage = nil
            showsReconnectAction = false
            stateAccessibilityLabel = "Available"
        case (.scanning, true):
            statusText = "Scanning…"
            statusSystemImage = nil
            showsReconnectAction = false
            stateAccessibilityLabel = "Scanning"
        }
    }

    private static func displayPath(
        for directoryURL: URL,
        homeDirectory: URL
    ) -> String {
        let path = trimmedPath(directoryURL.path(percentEncoded: false))
        let homePath = trimmedPath(homeDirectory.path(percentEncoded: false))

        if path == homePath {
            return "~"
        }

        if path.hasPrefix("\(homePath)/") {
            return "~\(path.dropFirst(homePath.count))"
        }

        return path
    }

    private static func trimmedPath(_ path: String) -> String {
        guard path != "/" else {
            return path
        }

        return path.replacing(/\/+$/, with: "")
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
