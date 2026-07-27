import SwiftUI

@main
struct SkillsManagerApp: App {
    @State private var libraryModel = SkillLibraryModel()

    var body: some Scene {
        WindowGroup("Skills") {
            SkillLibraryView(model: libraryModel)
                .frame(minWidth: 880, minHeight: 560)
        }
        .defaultSize(width: 1_120, height: 720)

        Settings {
            SettingsView()
        }
    }
}
