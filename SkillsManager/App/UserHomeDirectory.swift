import Darwin
import Foundation

/// The signed-in account's home directory.
///
/// `FileManager.homeDirectoryForCurrentUser` reports the sandbox container rather
/// than the account home, so suggested agent locations and `~` path abbreviation
/// would both resolve inside the container instead of against the user's real
/// folders. Reading the account home from the password database stays inside the
/// sandbox: it yields a path, never access to the files beneath it.
enum UserHomeDirectory {
    /// The account home directory, resolved once per process.
    static let current = resolve()

    private static func resolve() -> URL {
        guard
            let entry = getpwuid(getuid()),
            let homePath = entry.pointee.pw_dir,
            let path = String(validatingCString: homePath),
            path.isEmpty == false
        else {
            return FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        }

        return URL(filePath: path, directoryHint: .isDirectory).standardizedFileURL
    }
}
