import Foundation

/// A solver built using the composable filter architecture.
/// Demonstrates how to assemble filters and executors for different use cases.
///
/// Performance: With `@inlinable` and generics, the compiler specializes all code
/// at compile time. The resulting machine code is equivalent to hand-written loops.
///
/// Usage:
/// ```swift
/// let solver = ComposableWordleSolver(words: words)
///
/// // Using pre-composed WordleFilter (simplest)
/// let results = solver.solve(excluded: Set("xyz"), green: [0: "s"], yellow: Set("a"))
///
/// // Using custom filter composition
/// let filter = ExcludedLetterFilter(excluded: Set("xyz"))
///     && RequiredLetterFilter(required: Set("ae"))
///     && GreenLetterFilter(green: [0: "s"])
/// let results = solver.solve(filter: filter)
///
/// // With specific executor
/// let results = solver.solve(filter: filter, executor: GCDParallelExecutor())
/// ```
public final class ComposableWordleSolver: @unchecked Sendable {
    public let words: [Word]
    @usableFromInline let defaultExecutor: AdaptiveExecutor

    public init(words: [String]) {
        self.words = words.compactMap(Word.init)
        self.defaultExecutor = AdaptiveExecutor()
    }

    public init(words: [Word]) {
        self.words = words
        self.defaultExecutor = AdaptiveExecutor()
    }

    // MARK: - Generic Filter API

    /// Solve using any WordFilter with the default (adaptive) executor.
    @inlinable
    public func solve<F: WordFilter>(filter: F) -> [Word] {
        defaultExecutor.execute(filter: filter, over: words)
    }

    /// Solve using any WordFilter with a specific executor.
    @inlinable
    public func solve<F: WordFilter, E: FilterExecutor>(filter: F, executor: E) -> [Word] {
        executor.execute(filter: filter, over: words)
    }

    /// Async solve using any WordFilter.
    @inlinable
    public func solveAsync<F: WordFilter>(filter: F) async -> [Word] {
        await defaultExecutor.executeAsync(filter: filter, over: words)
    }

    // MARK: - Convenience API (Wordle-specific)

    /// Sync solve with standard Wordle constraints using the pre-composed WordleFilter.
    @inlinable
    public func solveSync(
        excluded: Set<Character> = [],
        green: [Int: Character] = [:],
        yellow: Set<Character> = []
    ) -> [Word] {
        let filter = WordleFilter(excluded: excluded, green: green, yellow: yellow)
        return solve(filter: filter)
    }

    /// Sync solve with yellow position constraints.
    @inlinable
    public func solveSync(
        excluded: Set<Character>,
        green: [Int: Character],
        yellowPositions: [Character: UInt8]
    ) -> [Word] {
        let filter = WordleFilter(excluded: excluded, green: green, yellowPositions: yellowPositions)
        return solve(filter: filter)
    }

    /// Async solve with standard Wordle constraints (protocol conformance).
    @inlinable
    public func solve(
        excluded: Set<Character> = [],
        green: [Int: Character] = [:],
        yellow: Set<Character> = []
    ) async -> [Word] {
        let filter = WordleFilter(excluded: excluded, green: green, yellow: yellow)
        return await solveAsync(filter: filter)
    }

    /// Async solve with yellow position constraints.
    @inlinable
    public func solve(
        excluded: Set<Character>,
        green: [Int: Character],
        yellowPositions: [Character: UInt8]
    ) async -> [Word] {
        let filter = WordleFilter(excluded: excluded, green: green, yellowPositions: yellowPositions)
        return await solveAsync(filter: filter)
    }
}

// MARK: - Protocol Conformance

extension ComposableWordleSolver: WordleSolver {
    public var allWordleWords: [Word] { words }
}

// MARK: - Filter Builder DSL

/// A result builder for composing filters declaratively.
@resultBuilder
public struct FilterBuilder {
    public static func buildBlock<F: WordFilter>(_ filter: F) -> F {
        filter
    }

    public static func buildBlock<F1: WordFilter, F2: WordFilter>(
        _ f1: F1, _ f2: F2
    ) -> AndFilter<F1, F2> {
        AndFilter(f1, f2)
    }

    public static func buildBlock<F1: WordFilter, F2: WordFilter, F3: WordFilter>(
        _ f1: F1, _ f2: F2, _ f3: F3
    ) -> AndFilter<AndFilter<F1, F2>, F3> {
        AndFilter(AndFilter(f1, f2), f3)
    }

    public static func buildBlock<F1: WordFilter, F2: WordFilter, F3: WordFilter, F4: WordFilter>(
        _ f1: F1, _ f2: F2, _ f3: F3, _ f4: F4
    ) -> AndFilter<AndFilter<AndFilter<F1, F2>, F3>, F4> {
        AndFilter(AndFilter(AndFilter(f1, f2), f3), f4)
    }

    public static func buildOptional<F: WordFilter>(_ filter: F?) -> AnyWordFilter {
        if let filter = filter {
            return AnyWordFilter(filter)
        } else {
            return AnyWordFilter(PassAllFilter())
        }
    }
}

// MARK: - Extension for DSL Usage

extension ComposableWordleSolver {
    /// Solve using a filter built with the FilterBuilder DSL.
    ///
    /// Usage:
    /// ```swift
    /// let results = solver.solve {
    ///     ExcludedLetterFilter(excluded: Set("xyz"))
    ///     RequiredLetterFilter(required: Set("ae"))
    ///     GreenLetterFilter(green: [0: "s"])
    /// }
    /// ```
    @inlinable
    public func solve<F: WordFilter>(@FilterBuilder _ build: () -> F) -> [Word] {
        solve(filter: build())
    }
}
