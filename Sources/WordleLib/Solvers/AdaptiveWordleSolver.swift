import Foundation

/// Adaptive solver that uses `StaticWordleFilter` for optimal performance.
///
/// Uses the composable filter architecture with `StaticWordleFilter`, which
/// combines all constraint checks into a single tight loop. Bitmasks are
/// computed once at query time, then filtering runs at maximum speed.
///
/// Usage:
/// ```swift
/// let solver = AdaptiveWordleSolver(words: words)
///
/// // After guessing "CRANE" with C gray, R yellow at position 1, A green at position 2, N/E gray:
/// let results = await solver.solve(
///     excluded: Set("cne"),
///     green: [2: "a"],
///     yellow: ["r": 0b00010]  // 'r' in word but not at position 1
/// )
///
/// // Use helpers to build yellow constraints:
/// let yellow = AdaptiveWordleSolver.yellowFromGuess([("r", 1)])  // ["r": 0b00010]
/// ```
public final class AdaptiveWordleSolver: @unchecked Sendable {
    private let composableSolver: ComposableWordleSolver

    public var allWordleWords: [Word] {
        composableSolver.words
    }

    public init(words: [String]) {
        self.composableSolver = ComposableWordleSolver(words: words)
    }

    public init(words: [Word]) {
        self.composableSolver = ComposableWordleSolver(words: words)
    }

    // MARK: - Solve API

    /// Solve with the given constraints.
    ///
    /// - Parameters:
    ///   - excluded: Gray letters that are not in the word.
    ///   - green: Green letters at their correct positions.
    ///   - yellow: Yellow letters mapped to forbidden position bitmasks.
    ///     Bit N set means the letter cannot be at position N.
    ///     Example: `["a": 0b00110]` means 'a' must be in the word but not at positions 1 or 2.
    ///     Use `forbiddenPositions()` or `yellowFromGuess()` helpers to build these.
    public func solve(
        excluded: Set<Character> = [],
        green: [Int: Character] = [:],
        yellow: [Character: UInt8] = [:]
    ) async -> [Word] {
        let filter = StaticWordleFilter(excluded: excluded, green: green, yellowPositions: yellow)
        return await composableSolver.solveAsync(filter: filter)
    }

    // MARK: - Convenience Helpers

    /// Create a position bitmask from positions where a letter cannot be.
    /// Example: `forbiddenPositions([1, 2])` returns `0b00110`
    public static func forbiddenPositions(_ positions: Int...) -> UInt8 {
        var mask: UInt8 = 0
        for pos in positions where pos >= 0 && pos <= 4 {
            mask |= 1 << pos
        }
        return mask
    }

    /// Create yellow constraints from guesses.
    /// Example: After guessing "CRANE" with 'A' yellow at position 2:
    /// `yellowFromGuess([("a", 2)])` returns `["a": 0b00100]`
    public static func yellowFromGuess(_ letters: [(Character, Int)]) -> [Character: UInt8] {
        var result: [Character: UInt8] = [:]
        for (letter, position) in letters where position >= 0 && position <= 4 {
            let lower = Character(letter.lowercased())
            result[lower, default: 0] |= 1 << position
        }
        return result
    }
}

