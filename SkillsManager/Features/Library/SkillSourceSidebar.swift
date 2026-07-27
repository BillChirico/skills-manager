import AppKit
import SkillsCore
import SwiftUI

struct SkillSourceSidebar: View {
    @Bindable var model: SkillLibraryModel
    @State private var sourceBeingRenamed: SkillSource?
    @State private var sourceBeingRemoved: SkillSource?
    @State private var renamedSourceName = ""

    var body: some View {
        List(selection: $model.sidebarSelection) {
            Section("Library") {
                smartGroupRow(
                    title: "All Skills",
                    systemImage: "square.grid.2x2",
                    count: model.allSkillsCount
                )
                .tag(SkillLibraryScope.allSkills)

                smartGroupRow(
                    title: "Updates Available",
                    systemImage: "arrow.down.circle",
                    count: model.updatesAvailableCount,
                    drawsAttention: true
                )
                .tag(SkillLibraryScope.updatesAvailable)

                smartGroupRow(
                    title: "Disabled",
                    systemImage: "pause.circle",
                    count: model.disabledCount
                )
                .tag(SkillLibraryScope.disabled)

                smartGroupRow(
                    title: "Recently Added",
                    systemImage: "clock",
                    count: model.recentlyAddedCount
                )
                .tag(SkillLibraryScope.recentlyAdded)
            }

            Section("Directories") {
                if model.sources.isEmpty {
                    Text("No directories added")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.sources) { source in
                        sourceRow(source)
                            .tag(SkillLibraryScope.source(source.id))
                            .contextMenu {
                                sourceContextMenu(source)
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        .alert(
            "Rename Directory",
            isPresented: Binding(
                get: { sourceBeingRenamed != nil },
                set: { isPresented in
                    if isPresented == false {
                        sourceBeingRenamed = nil
                    }
                }
            )
        ) {
            TextField("Directory name", text: $renamedSourceName)
            Button("Cancel", role: .cancel) {
                sourceBeingRenamed = nil
            }
            Button("Rename") {
                guard let source = sourceBeingRenamed else {
                    return
                }
                sourceBeingRenamed = nil
                perform("Unable to Rename Directory") {
                    try await model.renameSource(source.id, to: renamedSourceName)
                }
            }
        } message: {
            Text("Choose the name shown in the sidebar. The folder on disk is not renamed.")
        }
        .confirmationDialog(
            "Remove Directory?",
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
            Button("Remove Directory", role: .destructive) {
                guard let source = sourceBeingRemoved else {
                    return
                }
                sourceBeingRemoved = nil
                perform("Unable to Remove Directory") {
                    try await model.removeSource(source.id)
                }
            }
            Button("Cancel", role: .cancel) {
                sourceBeingRemoved = nil
            }
        } message: {
            Text("This removes the directory from Skills Manager. Its files stay on disk.")
        }
    }

    private func smartGroupRow(
        title: String,
        systemImage: String,
        count: Int,
        drawsAttention: Bool = false
    ) -> some View {
        HStack(spacing: SkillsManagerSpacing.small) {
            Image(systemName: systemImage)
                .foregroundStyle(
                    drawsAttention && count > 0
                        ? Color.accentColor
                        : Color.secondary
                )
                .frame(width: 18)
                .accessibilityHidden(true)

            Text(title)

            Spacer(minLength: SkillsManagerSpacing.small)

            Text(count, format: .number)
                .monospacedDigit()
                .foregroundStyle(count == 0 ? .tertiary : .secondary)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(count)")
    }

    private func sourceRow(_ source: SkillSource) -> some View {
        HStack(spacing: SkillsManagerSpacing.small) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(source.displayName)
                .lineLimit(1)

            Spacer(minLength: SkillsManagerSpacing.small)

            switch model.sourceState(for: source.id) {
            case .available:
                if source.isEnabled {
                    Text(model.skillCount(for: source.id), format: .number)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            case .scanning:
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Scanning")
            case .unavailable:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Directory unavailable")
            }
        }
        .opacity(source.isEnabled ? 1 : 0.55)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func sourceContextMenu(_ source: SkillSource) -> some View {
        Button("Rescan", systemImage: "arrow.clockwise") {
            perform("Unable to Scan \(source.displayName)") {
                try await model.rescanSource(source.id)
            }
        }
        .disabled(
            source.isEnabled == false
                || model.sourceState(for: source.id) == .scanning
        )

        Button("Reveal in Finder", systemImage: "finder") {
            NSWorkspace.shared.activateFileViewerSelecting([source.directoryURL])
        }

        Button("Rename…", systemImage: "pencil") {
            renamedSourceName = source.displayName
            sourceBeingRenamed = source
        }

        Divider()

        Button(
            source.isEnabled ? "Disable Directory" : "Enable Directory",
            systemImage: source.isEnabled ? "pause.circle" : "play.circle"
        ) {
            perform("Unable to Update Directory") {
                try await model.setSourceEnabled(!source.isEnabled, sourceID: source.id)
            }
        }

        Button("Remove…", systemImage: "minus.circle", role: .destructive) {
            sourceBeingRemoved = source
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
