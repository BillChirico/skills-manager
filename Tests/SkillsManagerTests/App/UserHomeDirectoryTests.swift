import Foundation
import Testing

@testable import SkillsManager

struct UserHomeDirectoryTests {
    @Test("A failed account-home lookup has no sandbox-container fallback")
    func lookupFailureReturnsNil() {
        #expect(UserHomeDirectory.resolve(accountHomePath: { nil }) == nil)
        #expect(UserHomeDirectory.resolve(accountHomePath: { "" }) == nil)
    }

    @Test("A resolved account-home path becomes a standardized directory URL")
    func accountHomePathIsStandardized() {
        let homeDirectory = UserHomeDirectory.resolve {
            "/Users/reviewer/../reviewer/"
        }

        #expect(
            homeDirectory
                == URL(
                    filePath: "/Users/reviewer",
                    directoryHint: .isDirectory
                ).standardizedFileURL
        )
    }
}
