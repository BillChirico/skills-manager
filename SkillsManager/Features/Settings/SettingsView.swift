import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            LabeledContent("Skill directories") {
                Text("Managed from the Library sidebar")
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Updates") {
                Text("Manual")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 480)
    }
}
