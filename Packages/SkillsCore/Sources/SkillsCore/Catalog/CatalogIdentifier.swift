import Foundation

/// Validation for catalog-supplied identifiers before they reach a URL path or a
/// process argument vector.
///
/// Every value in a `CatalogSkill` arrives from skills.sh, so it is untrusted input.
/// A value that survives these checks contains no path separators, no relative path
/// segments, and no leading option marker, which is what keeps a remote catalog entry
/// from steering a request off its intended path or from being read as a flag.
enum CatalogIdentifier {
    /// Long enough for any real GitHub owner, repository, or skill slug.
    static let maximumLength = 100

    private static let allowedCharacters = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-"
    )

    /// Returns the value when it is safe to append as a single URL path component.
    static func validatedPathComponent(_ value: String) -> String? {
        guard
            value.isEmpty == false,
            value.count <= maximumLength,
            value != ".",
            value != "..",
            value.allSatisfy(allowedCharacters.contains)
        else {
            return nil
        }

        return value
    }

    /// Returns the value when it is safe to pass as a single command argument.
    ///
    /// This is `validatedPathComponent(_:)` plus a rejection of a leading `-`, because a
    /// slug such as `--force` would otherwise be read as an option by the invoked tool.
    static func validatedArgument(_ value: String) -> String? {
        guard
            let value = validatedPathComponent(value),
            value.hasPrefix("-") == false
        else {
            return nil
        }

        return value
    }
}
