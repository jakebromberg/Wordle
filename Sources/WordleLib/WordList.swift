import Foundation

/// Utility for loading word lists.
public enum WordList {
    /// Load words from the bundled resource file.
    public static func loadBundled() throws -> [String] {
        guard let url = Bundle.module.url(forResource: "words5", withExtension: "txt") else {
            throw WordListError.resourceNotFound
        }
        return try load(from: url)
    }

    /// Load words from a file URL.
    public static func load(from url: URL) throws -> [String] {
        let content = try String(contentsOf: url, encoding: .utf8)
        return content
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.count == 5 }
    }

    /// Load words from a file path.
    public static func load(from path: String) throws -> [String] {
        try load(from: URL(fileURLWithPath: path))
    }

    public enum WordListError: Error, LocalizedError {
        case resourceNotFound

        public var errorDescription: String? {
            switch self {
            case .resourceNotFound:
                return "Could not find bundled word list resource"
            }
        }
    }
}
