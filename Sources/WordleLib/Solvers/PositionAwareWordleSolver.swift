import Foundation

/// Maximum performance solver combining all optimizations:
/// - Bitmask for letter presence (O(1) contains check)
/// - Bitmask for forbidden positions (O(1) position check)
/// - Precomputed constraints
/// - Single-pass with early exits
/// - Specialized for Word type (no generic overhead)
/// - Optional parallel execution for large word lists
public final class PositionAwareWordleSolver: @unchecked Sendable {
    public let allWordleWords: [Word]

    /// Number of CPU cores available for parallel execution.
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

    /// Sequential solve with full yellow position support.
    /// - Parameter yellowPositions: Maps each yellow letter to forbidden positions as a bitmask.
    ///   Bit 0 = position 0, bit 1 = position 1, etc.
    @inline(__always)
    public func solve(
        excluded: Set<Character>,
        green: [Int: Character],
        yellowPositions: [Character: UInt8]
    ) -> [Word] {
        let query = UltraConstraints(
            excluded: excluded,
            green: green,
            yellowPositions: yellowPositions
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

    /// Convenience method accepting yellow letters as a simple set (no position constraints).
    @inline(__always)
    public func solve(
        excluded: Set<Character> = [],
        green: [Int: Character] = [:],
        yellow: Set<Character> = []
    ) -> [Word] {
        let yellowPositions = Dictionary(uniqueKeysWithValues: yellow.map { ($0, UInt8(0)) })
        return solve(excluded: excluded, green: green, yellowPositions: yellowPositions)
    }

    // MARK: - Parallel Solve (GCD)

    /// Parallel solve using Grand Central Dispatch.
    /// Only beneficial for larger word lists (>50k words) or expensive per-word checks.
    /// For typical Wordle lists (~10k words), use `solve()` or `solveAsync()` instead.
    public func solveParallel(
        excluded: Set<Character>,
        green: [Int: Character],
        yellowPositions: [Character: UInt8]
    ) -> [Word] {
        let query = UltraConstraints(
            excluded: excluded,
            green: green,
            yellowPositions: yellowPositions
        )

        let wordCount = allWordleWords.count

        // For small lists, sequential is faster due to parallelization overhead
        if wordCount < 20_000 {
            return solve(excluded: excluded, green: green, yellowPositions: yellowPositions)
        }

        let chunkCount = processorCount
        let chunkSize = (wordCount + chunkCount - 1) / chunkCount

        // Use array instead of unsafe pointer for simpler code
        var chunkResults = [[Word]](repeating: [], count: chunkCount)

        DispatchQueue.concurrentPerform(iterations: chunkCount) { chunkIndex in
            let start = chunkIndex * chunkSize
            let end = min(start + chunkSize, wordCount)

            var results: [Word] = []
            results.reserveCapacity((end - start) / 4)

            for i in start..<end {
                let word = allWordleWords[i]
                if query.matches(word) {
                    results.append(word)
                }
            }

            chunkResults[chunkIndex] = results
        }

        // Merge results
        return chunkResults.flatMap { $0 }
    }

    /// Convenience parallel solve with simple yellow set.
    public func solveParallel(
        excluded: Set<Character> = [],
        green: [Int: Character] = [:],
        yellow: Set<Character> = []
    ) -> [Word] {
        let yellowPositions = Dictionary(uniqueKeysWithValues: yellow.map { ($0, UInt8(0)) })
        return solveParallel(excluded: excluded, green: green, yellowPositions: yellowPositions)
    }

    // MARK: - Parallel Solve (Swift Concurrency)

    /// Parallel solve using Swift's structured concurrency (TaskGroup).
    ///
    /// Performance characteristics:
    /// - 2-6x faster than sequential for selective queries (few results)
    /// - ~1.2x faster for broad queries (many results)
    /// - Best choice for async/await codebases
    ///
    /// Recommended for:
    /// - Integration with async code
    /// - Queries expected to return few results
    /// - When latency matters more than throughput
    public func solveAsync(
        excluded: Set<Character>,
        green: [Int: Character],
        yellowPositions: [Character: UInt8]
    ) async -> [Word] {
        let query = UltraConstraints(
            excluded: excluded,
            green: green,
            yellowPositions: yellowPositions
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

    /// Convenience async solve with simple yellow set.
    public func solveAsync(
        excluded: Set<Character> = [],
        green: [Int: Character] = [:],
        yellow: Set<Character> = []
    ) async -> [Word] {
        let yellowPositions = Dictionary(uniqueKeysWithValues: yellow.map { ($0, UInt8(0)) })
        return await solveAsync(excluded: excluded, green: green, yellowPositions: yellowPositions)
    }

    // MARK: - Auto-Selecting Solve

    /// Automatically chooses the best execution strategy based on constraints.
    /// Uses parallel execution for selective queries, sequential for broad queries.
    public func solveAuto(
        excluded: Set<Character>,
        green: [Int: Character],
        yellowPositions: [Character: UInt8]
    ) async -> [Word] {
        // Heuristic: more constraints = more selective = parallel benefits more
        let constraintScore = excluded.count + green.count * 3 + yellowPositions.count * 2

        if constraintScore >= 5 {
            return await solveAsync(excluded: excluded, green: green, yellowPositions: yellowPositions)
        } else {
            return solve(excluded: excluded, green: green, yellowPositions: yellowPositions)
        }
    }

    /// Convenience auto solve with simple yellow set.
    public func solveAuto(
        excluded: Set<Character> = [],
        green: [Int: Character] = [:],
        yellow: Set<Character> = []
    ) async -> [Word] {
        let yellowPositions = Dictionary(uniqueKeysWithValues: yellow.map { ($0, UInt8(0)) })
        return await solveAuto(excluded: excluded, green: green, yellowPositions: yellowPositions)
    }
}

// MARK: - Protocol Conformance (async wrapper)

extension PositionAwareWordleSolver: WordleSolver {
    public func getSolutions(
        excludedChars: Set<Character>,
        correctlyPlacedChars: [Int: Character],
        correctLettersInWrongPlaces: Set<Character>
    ) async -> [Word] {
        solve(excluded: excludedChars, green: correctlyPlacedChars, yellow: correctLettersInWrongPlaces)
    }
}

// MARK: - Ultra Constraints

/// Highly optimized constraint representation using bitmasks throughout.
private struct UltraConstraints: Sendable {
    /// Mask of letters to exclude (with green letters removed).
    let excludedMask: UInt32

    /// Mask of all letters that must be present (green + yellow).
    let requiredMask: UInt32

    /// Green constraints: (position, ascii byte)
    let greenConstraints: [(Int, UInt8)]

    /// Yellow constraints: (ascii byte, forbidden position bitmask)
    /// Bitmask: bit N set means letter cannot be at position N
    let yellowConstraints: [(UInt8, UInt8)]

    init(
        excluded: Set<Character>,
        green: [Int: Character],
        yellowPositions: [Character: UInt8]
    ) {
        // Build letter masks
        let greenMask = Self.letterMask(from: green.values)
        let yellowMask = Self.letterMask(from: yellowPositions.keys)
        let rawExcludedMask = Self.letterMask(from: excluded)

        // Green overrides excluded
        self.excludedMask = rawExcludedMask & ~greenMask
        self.requiredMask = greenMask | yellowMask

        // Precompute green constraints
        self.greenConstraints = green.compactMap { pos, char in
            guard let ascii = Self.ascii(for: char), pos >= 0, pos <= 4 else { return nil }
            return (pos, ascii)
        }

        // Precompute yellow constraints
        self.yellowConstraints = yellowPositions.compactMap { char, forbiddenMask in
            guard let ascii = Self.ascii(for: char) else { return nil }
            return (ascii, forbiddenMask)
        }
    }

    @inline(__always)
    func matches(_ word: Word) -> Bool {
        let mask = word.letterMask

        // Fast bitmask rejections (most selective first)
        if (mask & excludedMask) != 0 { return false }
        if (mask & requiredMask) != requiredMask { return false }

        // Green position checks
        for (pos, ascii) in greenConstraints {
            if word[pos] != ascii { return false }
        }

        // Yellow forbidden position checks (bitmask-based)
        for (ascii, forbidden) in yellowConstraints {
            // Check each position where this letter is forbidden
            if (forbidden & 0b00001) != 0 && word[0] == ascii { return false }
            if (forbidden & 0b00010) != 0 && word[1] == ascii { return false }
            if (forbidden & 0b00100) != 0 && word[2] == ascii { return false }
            if (forbidden & 0b01000) != 0 && word[3] == ascii { return false }
            if (forbidden & 0b10000) != 0 && word[4] == ascii { return false }
        }

        return true
    }

    @inline(__always)
    private static func letterMask<S: Sequence>(from chars: S) -> UInt32 where S.Element == Character {
        var mask: UInt32 = 0
        for char in chars {
            if let ascii = Self.ascii(for: char) {
                mask |= 1 << (ascii - ASCII.lowerA)
            }
        }
        return mask
    }

    @inline(__always)
    private static func ascii(for char: Character) -> UInt8? {
        guard let scalar = char.unicodeScalars.first, scalar.isASCII else { return nil }
        let value = UInt8(scalar.value)
        let lower = (value >= 65 && value <= 90) ? value + 32 : value
        guard lower >= ASCII.lowerA, lower <= ASCII.lowerZ else { return nil }
        return lower
    }
}

// MARK: - Helper for Creating Position Bitmasks

extension PositionAwareWordleSolver {
    /// Helper to create a position bitmask from an array of positions.
    /// Example: `positionMask([0, 2])` returns `0b00101` (bits 0 and 2 set)
    public static func positionMask(_ positions: [Int]) -> UInt8 {
        var mask: UInt8 = 0
        for pos in positions where pos >= 0 && pos <= 4 {
            mask |= 1 << pos
        }
        return mask
    }

    /// Helper to create a position bitmask from a single position.
    public static func positionMask(_ position: Int) -> UInt8 {
        guard position >= 0 && position <= 4 else { return 0 }
        return 1 << position
    }
}
