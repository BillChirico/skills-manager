import Darwin
import Foundation

/// Resolves the signed-in account's home directory.
///
/// Resolving this from the password database keeps agent-directory suggestions,
/// `~` path abbreviation, and the lifecycle CLI on the same account-home path.
/// Resolution fails closed when the password database has no usable path.
enum UserHomeDirectory {
    /// The account home directory, resolved once per process when available.
    static let current: URL? = resolve()

    /// Resolves an account-home path into a standardized directory URL.
    ///
    /// The injected lookup keeps the fail-closed behavior deterministic in tests.
    static func resolve(
        accountHomePath: () -> String? = lookupAccountHomePath
    ) -> URL? {
        guard let path = accountHomePath(), path.isEmpty == false else {
            return nil
        }

        return URL(filePath: path, directoryHint: .isDirectory).standardizedFileURL
    }

    private static func lookupAccountHomePath() -> String? {
        guard
            let entry = getpwuid(getuid()),
            let homePath = entry.pointee.pw_dir
        else {
            return nil
        }

        return String(validatingCString: homePath)
    }
}
