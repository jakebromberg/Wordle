import Foundation

/// Adaptive solver that automatically selects the fastest algorithm based on query type.
///
/// Decision logic:
/// - Uses `BitmaskWordleSolver` (faster) when yellow position tracking is NOT needed
/// - Uses `PositionAwareWordleSolver` when yellow position tracking IS needed
/// - Always uses parallel execution (TaskGroup) as it's faster in all scenarios
///
/// Usage:
/// ```swift
/// let solver = AdaptiveWordleSolver(words: words)
///
/// // Simple query - uses BitmaskWordleSolver (fastest)
/// let results = await solver.solve(excluded: Set("xyz"), green: [0: "s"], yellow: Set("a"))
///
/// // With yellow positions - uses PositionAwareWordleSolver
/// let results = await solver.solve(
///     excluded: Set("xyz"),
///     green: [0: "s"],
///     yellowPositions: ["a": 0b00110]  // 'a' not at positions 1 or 2
/// )
/// ```
public final class AdaptiveWordleSolver: @unchecked Sendable {
    private let bitmaskSolver: BitmaskWordleSolver
    private let positionAwareSolver: PositionAwareWordleSolver

    public var allWordleWords: [Word] {
        bitmaskSolver.allWordleWords
    }

    public init(words: [String]) {
        self.bitmaskSolver = BitmaskWordleSolver(words: words)
        self.positionAwareSolver = PositionAwareWordleSolver(words: words)
    }

    public init(words: [Word]) {
        self.bitmaskSolver = BitmaskWordleSolver(words: words)
        self.positionAwareSolver = PositionAwareWordleSolver(words: words)
    }

    // MARK: - Simple API (No Yellow Position Tracking)

    /// Solve without yellow position tracking.
    /// Uses the fastest algorithm (BitmaskWordleSolver + TaskGroup).
    ///
    /// - Note: Yellow letters must exist somewhere in the word, but this method
    ///   does NOT track where they cannot be. For full Wordle semantics, use
    ///   `solve(excluded:green:yellowPositions:)` instead.
    public func solve(
        excluded: Set<Character> = [],
        green: [Int: Character] = [:],
        yellow: Set<Character> = []
    ) async -> [Word] {
        await bitmaskSolver.solveAsync(excluded: excluded, green: green, yellow: yellow)
    }

    // MARK: - Full API (With Yellow Position Tracking)

    /// Solve with yellow position tracking.
    /// Uses PositionAwareWordleSolver + TaskGroup when positions are specified.
    ///
    /// - Parameter yellowPositions: Maps each yellow letter to a bitmask of forbidden positions.
    ///   Bit N set means the letter cannot be at position N.
    ///   Example: `["a": 0b00110]` means 'a' cannot be at positions 1 or 2.
    public func solve(
        excluded: Set<Character>,
        green: [Int: Character],
        yellowPositions: [Character: UInt8]
    ) async -> [Word] {
        // Check if any yellow letter has position constraints
        let hasPositionConstraints = yellowPositions.values.contains { $0 != 0 }

        if hasPositionConstraints {
            // Need PositionAwareWordleSolver for position tracking
            return await positionAwareSolver.solveAsync(
                excluded: excluded,
                green: green,
                yellowPositions: yellowPositions
            )
        } else {
            // No position constraints, use faster BitmaskWordleSolver
            let yellow = Set(yellowPositions.keys)
            return await bitmaskSolver.solveAsync(
                excluded: excluded,
                green: green,
                yellow: yellow
            )
        }
    }

    // MARK: - Synchronous API

    /// Synchronous solve without yellow position tracking.
    /// Slightly slower than async version but simpler for non-async code.
    public func solveSync(
        excluded: Set<Character> = [],
        green: [Int: Character] = [:],
        yellow: Set<Character> = []
    ) -> [Word] {
        bitmaskSolver.solve(excluded: excluded, green: green, yellow: yellow)
    }

    /// Synchronous solve with yellow position tracking.
    public func solveSync(
        excluded: Set<Character>,
        green: [Int: Character],
        yellowPositions: [Character: UInt8]
    ) -> [Word] {
        let hasPositionConstraints = yellowPositions.values.contains { $0 != 0 }

        if hasPositionConstraints {
            return positionAwareSolver.solve(
                excluded: excluded,
                green: green,
                yellowPositions: yellowPositions
            )
        } else {
            let yellow = Set(yellowPositions.keys)
            return bitmaskSolver.solve(excluded: excluded, green: green, yellow: yellow)
        }
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

// MARK: - Protocol Conformance

extension AdaptiveWordleSolver: WordleSolver {
    public func getSolutions(
        excludedChars: Set<Character>,
        correctlyPlacedChars: [Int: Character],
        correctLettersInWrongPlaces: Set<Character>
    ) async -> [Word] {
        await solve(excluded: excludedChars, green: correctlyPlacedChars, yellow: correctLettersInWrongPlaces)
    }
}
