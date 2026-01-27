import Foundation

/// High-performance solver using precomputed bitmasks and ASCII operations.
/// Uses a 26-bit bitmask for O(1) letter presence checks.
///
/// This solver does NOT track yellow letter positions (where a letter cannot be).
/// For full Wordle semantics with yellow position tracking, use `PositionAwareWordleSolver`.
public final class BitmaskWordleSolver: WordleSolver, @unchecked Sendable {
    public let allWordleWords: [Word]

    /// Number of CPU cores for parallel execution.
    private let processorCount: Int

    public init(words: [String]) {
        self.allWordleWords = words.compactMap(Word.init)
        self.processorCount = ProcessInfo.processInfo.activeProcessorCount
    }

    public init(words: [Word]) {
        self.allWordleWords = words
        self.processorCount = ProcessInfo.processInfo.activeProcessorCount
    }

    // MARK: - Sequential Solve

    /// Sequential solve - fastest for broad queries with many results.
    @inline(__always)
    public func solveSync(
        excluded: Set<Character> = [],
        green: [Int: Character] = [:],
        yellow: Set<Character> = []
    ) -> [Word] {
        let query = QueryConstraints(
            excluded: excluded,
            placed: green,
            wrongPlace: yellow
        )

        var results: [Word] = []
        results.reserveCapacity(allWordleWords.count / 4)

        for word in allWordleWords {
            if query.matches(word) {
                results.append(word)
            }
        }

        return results
    }

    // MARK: - Parallel Solve (TaskGroup / Protocol Conformance)

    /// Parallel solve using Swift's structured concurrency.
    ///
    /// Performance:
    /// - 2-6x faster for selective queries (few results)
    /// - Similar speed for broad queries (many results)
    public func solve(
        excluded: Set<Character> = [],
        green: [Int: Character] = [:],
        yellow: Set<Character> = []
    ) async -> [Word] {
        let query = QueryConstraints(
            excluded: excluded,
            placed: green,
            wrongPlace: yellow
        )

        let wordCount = allWordleWords.count
        let chunkCount = processorCount
        let chunkSize = (wordCount + chunkCount - 1) / chunkCount

        return await withTaskGroup(of: [Word].self, returning: [Word].self) { group in
            for chunkIndex in 0..<chunkCount {
                let start = chunkIndex * chunkSize
                let end = min(start + chunkSize, wordCount)
                let words = allWordleWords

                group.addTask {
                    var chunkResults: [Word] = []
                    chunkResults.reserveCapacity((end - start) / 4)

                    for i in start..<end {
                        if query.matches(words[i]) {
                            chunkResults.append(words[i])
                        }
                    }
                    return chunkResults
                }
            }

            var merged: [Word] = []
            merged.reserveCapacity(wordCount / 4)
            for await chunkResults in group {
                merged.append(contentsOf: chunkResults)
            }
            return merged
        }
    }
}
