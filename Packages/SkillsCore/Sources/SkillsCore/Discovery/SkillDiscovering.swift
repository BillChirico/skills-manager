import Foundation

public protocol SkillDiscovering: Sendable {
    func discoverSkills(in source: SkillSource) async throws -> [AgentSkill]
}

public struct FileSystemSkillDiscoverer: SkillDiscovering {
    public init() {}

    public func discoverSkills(in source: SkillSource) async throws -> [AgentSkill] {
        let fileManager = FileManager()
        let scannedAt = Date.now
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .creationDateKey]
        let children = try fileManager.contentsOfDirectory(
            at: source.directoryURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )

        return try children.compactMap { directoryURL in
            let resourceValues = try directoryURL.resourceValues(forKeys: resourceKeys)
            guard resourceValues.isDirectory == true else {
                return nil
            }

            let manifestURL = directoryURL.appending(path: "SKILL.md", directoryHint: .notDirectory)
            guard fileManager.fileExists(atPath: manifestURL.path) else {
                return nil
            }

            let manifest = SkillManifest(
                contents: try String(contentsOf: manifestURL, encoding: .utf8)
            )
            let fallbackName = directoryURL.lastPathComponent
            let bodyOverview = manifest.firstBodyParagraph
            let discoveredSummary = manifest.metadata["description"] ?? bodyOverview
            let summary =
                discoveredSummary.isEmpty
                ? "No description provided."
                : discoveredSummary
            let overview = bodyOverview.isEmpty ? summary : bodyOverview

            return AgentSkill(
                name: manifest.metadata["name"] ?? fallbackName,
                summary: summary,
                author: manifest.metadata["author"],
                installedVersion: manifest.metadata["version"],
                directoryURL: directoryURL,
                sourceID: source.id,
                relativePath: directoryURL.lastPathComponent,
                addedAt: resourceValues.creationDate ?? scannedAt,
                overview: overview,
                lastScannedAt: scannedAt
            )
        }
        .sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

private struct SkillManifest {
    let metadata: [String: String]
    let body: String

    init(contents: String) {
        let lines = contents.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)
        let hasFrontMatter = lines.first?.trimmingCharacters(in: .whitespaces) == "---"
        let closingIndex =
            hasFrontMatter
            ? lines.dropFirst().firstIndex {
                $0.trimmingCharacters(in: .whitespaces) == "---"
            } : nil

        if let closingIndex {
            metadata = Self.metadata(from: lines[1..<closingIndex])
            body = lines[(closingIndex + 1)...]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            metadata = [:]
            body = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    var firstBodyParagraph: String {
        body.components(separatedBy: "\n\n")
            .map {
                $0.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter {
                        $0.hasPrefix("#") == false
                            && $0.hasPrefix("```") == false
                    }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .first { $0.isEmpty == false } ?? ""
    }

    private static func metadata(from lines: ArraySlice<String>) -> [String: String] {
        var metadata: [String: String] = [:]
        var index = lines.startIndex

        while index < lines.endIndex {
            guard let (key, rawValue) = metadataEntry(lines[index]) else {
                index += 1
                continue
            }

            guard rawValue.first == ">" || rawValue.first == "|" else {
                metadata[key] = unquoted(rawValue)
                index += 1
                continue
            }

            let isFolded = rawValue.first == ">"
            var blockLines: [String] = []
            index += 1

            while index < lines.endIndex {
                let line = lines[index]
                guard line.isEmpty || line.first?.isWhitespace == true else {
                    break
                }

                blockLines.append(line)
                index += 1
            }

            let value =
                isFolded
                ? foldedBlock(blockLines)
                : literalBlock(blockLines)
            if value.isEmpty == false {
                metadata[key] = value
            }
        }

        return metadata
    }

    private static func metadataEntry(_ line: String) -> (String, String)? {
        guard let separator = line.firstIndex(of: ":") else {
            return nil
        }

        let key = line[..<separator]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let rawValue = line[line.index(after: separator)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard key.isEmpty == false, rawValue.isEmpty == false else {
            return nil
        }

        return (key, rawValue)
    }

    private static func foldedBlock(_ lines: [String]) -> String {
        var paragraphs: [String] = []
        var currentParagraph: [String] = []

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.isEmpty {
                if currentParagraph.isEmpty == false {
                    paragraphs.append(currentParagraph.joined(separator: " "))
                    currentParagraph.removeAll()
                }
            } else {
                currentParagraph.append(trimmedLine)
            }
        }

        if currentParagraph.isEmpty == false {
            paragraphs.append(currentParagraph.joined(separator: " "))
        }

        return paragraphs.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func literalBlock(_ lines: [String]) -> String {
        let indentation =
            lines
            .filter { $0.trimmingCharacters(in: .whitespaces).isEmpty == false }
            .map { $0.prefix(while: \.isWhitespace).count }
            .min() ?? 0

        return
            lines
            .map { String($0.dropFirst(min(indentation, $0.count))) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2 else {
            return value
        }

        let isDoubleQuoted = value.first == "\"" && value.last == "\""
        let isSingleQuoted = value.first == "'" && value.last == "'"
        guard isDoubleQuoted || isSingleQuoted else {
            return value
        }

        return String(value.dropFirst().dropLast())
    }
}
