import Foundation

/// Protocol for composable word filters.
/// Uses generics (not existentials) to enable compile-time specialization.
///
/// Key performance considerations:
/// - Conforming types should be structs (value types)
/// - Use `@inlinable` on `matches` for cross-module optimization
/// - The compiler will specialize generic code, eliminating dispatch overhead
public protocol WordFilter: Sendable {
    /// Check if a word passes this filter.
    /// Called in tight loops - must be fast.
    @inlinable
    func matches(_ word: Word) -> Bool
}

// MARK: - Basic Filters

/// Filter that rejects words containing any excluded letter.
/// Uses bitmask for O(1) check.
@frozen
public struct ExcludedLetterFilter: WordFilter {
    public let excludedMask: UInt32

    @inlinable
    public init(excluded: Set<Character>) {
        self.excludedMask = Self.buildMask(from: excluded)
    }

    @inlinable
    public init(excludedMask: UInt32) {
        self.excludedMask = excludedMask
    }

    @inlinable @inline(__always)
    public func matches(_ word: Word) -> Bool {
        (word.letterMask & excludedMask) == 0
    }

    @inlinable
    static func buildMask(from chars: Set<Character>) -> UInt32 {
        var mask: UInt32 = 0
        for char in chars {
            if let bit = Word.bit(for: char) {
                mask |= bit
            }
        }
        return mask
    }
}

/// Filter that requires words to contain all specified letters.
/// Uses bitmask for O(1) check.
@frozen
public struct RequiredLetterFilter: WordFilter {
    public let requiredMask: UInt32

    @inlinable
    public init(required: Set<Character>) {
        self.requiredMask = Self.buildMask(from: required)
    }

    @inlinable
    public init(requiredMask: UInt32) {
        self.requiredMask = requiredMask
    }

    @inlinable @inline(__always)
    public func matches(_ word: Word) -> Bool {
        (word.letterMask & requiredMask) == requiredMask
    }

    @inlinable
    static func buildMask(from chars: Set<Character>) -> UInt32 {
        var mask: UInt32 = 0
        for char in chars {
            if let bit = Word.bit(for: char) {
                mask |= bit
            }
        }
        return mask
    }
}

/// Filter that requires specific letters at specific positions (green letters).
@frozen
public struct GreenLetterFilter: WordFilter {
    /// Stored as (position, ascii) pairs for direct byte comparison.
    public let constraints: [(position: Int, ascii: UInt8)]

    @inlinable
    public init(green: [Int: Character]) {
        self.constraints = green.compactMap { position, char in
            guard let ascii = Word.asciiValue(for: char),
                  position >= 0, position <= 4 else { return nil }
            return (position, ascii)
        }
    }

    @inlinable @inline(__always)
    public func matches(_ word: Word) -> Bool {
        for (position, ascii) in constraints {
            if word[position] != ascii { return false }
        }
        return true
    }
}

/// Filter that requires letters to NOT be at certain positions (yellow letters).
/// Each yellow letter has a bitmask of forbidden positions.
@frozen
public struct YellowPositionFilter: WordFilter {
    /// Stored as (ascii, forbiddenMask) pairs.
    /// forbiddenMask: bit N set means letter cannot be at position N.
    public let constraints: [(ascii: UInt8, forbidden: UInt8)]

    @inlinable
    public init(yellowPositions: [Character: UInt8]) {
        self.constraints = yellowPositions.compactMap { char, forbidden in
            guard let ascii = Word.asciiValue(for: char) else { return nil }
            return (ascii, forbidden)
        }
    }

    @inlinable @inline(__always)
    public func matches(_ word: Word) -> Bool {
        for (ascii, forbidden) in constraints {
            if (forbidden & 0b00001) != 0 && word[0] == ascii { return false }
            if (forbidden & 0b00010) != 0 && word[1] == ascii { return false }
            if (forbidden & 0b00100) != 0 && word[2] == ascii { return false }
            if (forbidden & 0b01000) != 0 && word[3] == ascii { return false }
            if (forbidden & 0b10000) != 0 && word[4] == ascii { return false }
        }
        return true
    }
}

// MARK: - Filter that always passes (identity)

/// A filter that accepts all words. Useful as a default or placeholder.
@frozen
public struct PassAllFilter: WordFilter {
    @inlinable
    public init() {}

    @inlinable @inline(__always)
    public func matches(_ word: Word) -> Bool {
        true
    }
}

// MARK: - Compile-Time Filter Construction

/// A filter with constraints known at compile time.
/// Uses macros to compute bitmasks with zero runtime overhead.
///
/// Usage:
/// ```swift
/// // All masks computed at compile time
/// let filter = StaticWordleFilter(
///     excludedMask: #letterMask("qxzjv"),
///     requiredMask: #letterMask("aer"),
///     green: [(0, #ascii("s")), (4, #ascii("e"))],
///     yellow: [(#ascii("a"), #positionMask(0, 1))]
/// )
/// ```
@frozen
public struct StaticWordleFilter: WordFilter {
    public let excludedMask: UInt32
    public let requiredMask: UInt32
    public let green: [(position: Int, ascii: UInt8)]
    public let yellow: [(ascii: UInt8, forbidden: UInt8)]

    @inlinable
    public init(
        excludedMask: UInt32 = 0,
        requiredMask: UInt32 = 0,
        green: [(Int, UInt8)] = [],
        yellow: [(UInt8, UInt8)] = []
    ) {
        self.excludedMask = excludedMask
        self.requiredMask = requiredMask
        self.green = green
        self.yellow = yellow
    }

    @inlinable @inline(__always)
    public func matches(_ word: Word) -> Bool {
        let mask = word.letterMask

        // Fast bitmask rejections (computed at compile time)
        if (mask & excludedMask) != 0 { return false }
        if (mask & requiredMask) != requiredMask { return false }

        // Green position checks
        for (position, ascii) in green {
            if word[position] != ascii { return false }
        }

        // Yellow position checks
        for (ascii, forbidden) in yellow {
            if (forbidden & 0b00001) != 0 && word[0] == ascii { return false }
            if (forbidden & 0b00010) != 0 && word[1] == ascii { return false }
            if (forbidden & 0b00100) != 0 && word[2] == ascii { return false }
            if (forbidden & 0b01000) != 0 && word[3] == ascii { return false }
            if (forbidden & 0b10000) != 0 && word[4] == ascii { return false }
        }

        return true
    }
}
