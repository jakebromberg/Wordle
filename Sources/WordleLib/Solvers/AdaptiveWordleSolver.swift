import Foundation

/// Adaptive solver that selects the optimal backend based on constraint characteristics.
///
/// Automatically chooses between:
/// - **TurboWordleSolver**: When first-letter indexing provides benefit (green[0] known
///   or many first letters excluded). Uses packed 40-bit words and bucket skipping.
/// - **SIMDWordleSolver**: When full scan is needed with no indexing benefit.
///   Uses SIMD8<UInt32> for maximum throughput on bitmask operations.
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
    private let turboSolver: TurboWordleSolver
    private let simdSolver: SIMDWordleSolver

    public var allWordleWords: [Word] {
        turboSolver.allWordleWords
    }

    public init(words: [String]) {
        self.turboSolver = TurboWordleSolver(words: words)
        self.simdSolver = SIMDWordleSolver(words: words)
    }

    public init(words: [Word]) {
        self.turboSolver = TurboWordleSolver(words: words)
        self.simdSolver = SIMDWordleSolver(words: words)
    }

    // MARK: - Solve API

    /// Solve with the given constraints.
    ///
    /// Automatically selects the optimal solver backend:
    /// - Uses Turbo when green[0] is known (first-letter indexing gives 5-7x speedup)
    /// - Uses Turbo when many first letters are excluded (bucket skipping helps)
    /// - Uses SIMD for pure bitmask scans with no indexing benefit
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
        // Choose solver based on constraint characteristics
        if shouldUseTurbo(excluded: excluded, green: green) {
            return turboSolver.solve(excluded: excluded, green: green, yellow: yellow)
        } else {
            return simdSolver.solve(excluded: excluded, green: green, yellow: yellow)
        }
    }

    // MARK: - Solver Selection

    /// Determine whether Turbo solver will outperform SIMD.
    ///
    /// Turbo wins when its indexing can reduce the search space:
    /// - green[0] known: search only 1/26th of words
    /// - Many first letters excluded: skip entire buckets
    @inline(__always)
    private func shouldUseTurbo(excluded: Set<Character>, green: [Int: Character]) -> Bool {
        // If we know the first letter, Turbo's indexing gives massive speedup (5-7x)
        if green[0] != nil {
            return true
        }

        // Count how many first-letter buckets can be skipped
        // If we can skip many buckets, Turbo's bucket skipping helps
        let excludedFirstLetters = excluded.filter { char in
            guard let ascii = Word.asciiValue(for: char) else { return false }
            return ascii >= 97 && ascii <= 122 // a-z
        }.count

        // If more than ~30% of alphabet is excluded, bucket skipping is worthwhile
        // (8+ letters excluded means we skip 8+ of 26 buckets = 30%+)
        if excludedFirstLetters >= 8 {
            return true
        }

        // For other cases, SIMD's pure throughput wins
        // (no index overhead, straight vectorized scan)
        return false
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

