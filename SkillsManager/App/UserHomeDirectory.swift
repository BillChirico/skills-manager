import Darwin
import Foundation

/// Resolves the signed-in account's home directory.
///
/// `FileManager.homeDirectoryForCurrentUser` reports the sandbox container rather
/// than the account home, so suggested agent locations and `~` path abbreviation
/// would both resolve inside the container instead of against the user's real
/// folders. Reading the account home from the password database stays inside the
/// sandbox: it yields a path, never access to the files beneath it. Resolution
/// fails closed when the password database has no usable account-home path.
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
