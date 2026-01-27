import Foundation

// MARK: - Composite Filters

/// Combines two filters with AND logic.
/// Generic parameters ensure compile-time specialization - no runtime dispatch.
@frozen
public struct AndFilter<F1: WordFilter, F2: WordFilter>: WordFilter {
    public let first: F1
    public let second: F2

    @inlinable
    public init(_ first: F1, _ second: F2) {
        self.first = first
        self.second = second
    }

    @inlinable @inline(__always)
    public func matches(_ word: Word) -> Bool {
        // Short-circuit: if first fails, don't check second
        first.matches(word) && second.matches(word)
    }
}

/// Combines two filters with OR logic.
@frozen
public struct OrFilter<F1: WordFilter, F2: WordFilter>: WordFilter {
    public let first: F1
    public let second: F2

    @inlinable
    public init(_ first: F1, _ second: F2) {
        self.first = first
        self.second = second
    }

    @inlinable @inline(__always)
    public func matches(_ word: Word) -> Bool {
        first.matches(word) || second.matches(word)
    }
}

/// Inverts a filter's result.
@frozen
public struct NotFilter<F: WordFilter>: WordFilter {
    public let filter: F

    @inlinable
    public init(_ filter: F) {
        self.filter = filter
    }

    @inlinable @inline(__always)
    public func matches(_ word: Word) -> Bool {
        !filter.matches(word)
    }
}

// MARK: - Operator Overloads for Ergonomic Composition

/// Combine filters with AND using && operator.
@inlinable
public func && <F1: WordFilter, F2: WordFilter>(lhs: F1, rhs: F2) -> AndFilter<F1, F2> {
    AndFilter(lhs, rhs)
}

/// Combine filters with OR using || operator.
@inlinable
public func || <F1: WordFilter, F2: WordFilter>(lhs: F1, rhs: F2) -> OrFilter<F1, F2> {
    OrFilter(lhs, rhs)
}

/// Invert a filter using ! prefix operator.
@inlinable
public prefix func ! <F: WordFilter>(filter: F) -> NotFilter<F> {
    NotFilter(filter)
}

// MARK: - Convenience Initializers


// MARK: - Type-Erased Filter (for dynamic composition)

/// Type-erased wrapper for WordFilter.
/// Use when you need runtime flexibility at the cost of some performance.
/// For hot paths, prefer generic composition instead.
public struct AnyWordFilter: WordFilter {
    @usableFromInline
    let _matches: @Sendable (Word) -> Bool

    @inlinable
    public init<F: WordFilter>(_ filter: F) {
        self._matches = { filter.matches($0) }
    }

    @inlinable @inline(__always)
    public func matches(_ word: Word) -> Bool {
        _matches(word)
    }
}

// MARK: - Pre-composed Wordle Filter

/// A pre-composed filter for standard Wordle constraints.
/// Combines all filter types in optimal order (most selective first).
@frozen
public struct WordleFilter: WordFilter {
    @usableFromInline let excludedFilter: ExcludedLetterFilter
    @usableFromInline let requiredFilter: RequiredLetterFilter
    @usableFromInline let greenFilter: GreenLetterFilter
    @usableFromInline let yellowFilter: YellowPositionFilter

    @inlinable
    public init(
        excluded: Set<Character> = [],
        green: [Int: Character] = [:],
        yellowPositions: [Character: UInt8] = [:]
    ) {
        // Green letters override exclusions
        let greenLetters = Set(green.values)
        let effectiveExcluded = excluded.subtracting(greenLetters)

        // Required = green + yellow
        let yellowLetters = Set(yellowPositions.keys)
        let required = greenLetters.union(yellowLetters)

        self.excludedFilter = ExcludedLetterFilter(excluded: effectiveExcluded)
        self.requiredFilter = RequiredLetterFilter(required: required)
        self.greenFilter = GreenLetterFilter(green: green)
        self.yellowFilter = YellowPositionFilter(yellowPositions: yellowPositions)
    }

    /// Convenience initializer with simple yellow set (no position constraints).
    @inlinable
    public init(
        excluded: Set<Character> = [],
        green: [Int: Character] = [:],
        yellow: Set<Character> = []
    ) {
        let yellowPositions = Dictionary(uniqueKeysWithValues: yellow.map { ($0, UInt8(0)) })
        self.init(excluded: excluded, green: green, yellowPositions: yellowPositions)
    }

    @inlinable @inline(__always)
    public func matches(_ word: Word) -> Bool {
        // Order: most selective checks first (bitmask checks are fastest)
        let mask = word.letterMask

        // Fast bitmask rejections
        if (mask & excludedFilter.excludedMask) != 0 { return false }
        if (mask & requiredFilter.requiredMask) != requiredFilter.requiredMask { return false }

        // Position checks
        if !greenFilter.matches(word) { return false }
        if !yellowFilter.matches(word) { return false }

        return true
    }
}
