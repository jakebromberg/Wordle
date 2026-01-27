import Foundation

// MARK: - Executor Protocol

/// Protocol for executing filters over a word list.
/// Different implementations provide different execution strategies.
public protocol FilterExecutor: Sendable {
    /// Execute a filter over words and return matching results.
    func execute<F: WordFilter>(filter: F, over words: [Word]) -> [Word]
}

// MARK: - Sequential Executor

/// Executes filter sequentially on a single thread.
/// Best for small word lists or when parallelization overhead exceeds benefit.
@frozen
public struct SequentialExecutor: FilterExecutor {
    @inlinable
    public init() {}

    @inlinable
    public func execute<F: WordFilter>(filter: F, over words: [Word]) -> [Word] {
        var results: [Word] = []
        results.reserveCapacity(words.count / 4)

        for word in words {
            if filter.matches(word) {
                results.append(word)
            }
        }

        return results
    }
}

// MARK: - GCD Parallel Executor

/// Executes filter in parallel using Grand Central Dispatch.
/// Best for CPU-bound work on large word lists.
@frozen
public struct GCDParallelExecutor: FilterExecutor {
    public let chunkCount: Int

    @inlinable
    public init(chunkCount: Int? = nil) {
        self.chunkCount = chunkCount ?? ProcessInfo.processInfo.activeProcessorCount
    }

    @inlinable
    public func execute<F: WordFilter>(filter: F, over words: [Word]) -> [Word] {
        let wordCount = words.count
        let chunkSize = (wordCount + chunkCount - 1) / chunkCount
        var chunkResults = [[Word]](repeating: [], count: chunkCount)

        DispatchQueue.concurrentPerform(iterations: chunkCount) { chunkIndex in
            let start = chunkIndex * chunkSize
            let end = min(start + chunkSize, wordCount)

            var results: [Word] = []
            results.reserveCapacity((end - start) / 4)

            for i in start..<end {
                if filter.matches(words[i]) {
                    results.append(words[i])
                }
            }

            chunkResults[chunkIndex] = results
        }

        return chunkResults.flatMap { $0 }
    }
}

// MARK: - TaskGroup Parallel Executor

/// Executes filter in parallel using Swift's structured concurrency.
/// Best for async codebases and when you want cooperative scheduling.
@frozen
public struct TaskGroupExecutor: FilterExecutor, Sendable {
    public let chunkCount: Int

    @inlinable
    public init(chunkCount: Int? = nil) {
        self.chunkCount = chunkCount ?? ProcessInfo.processInfo.activeProcessorCount
    }

    /// Synchronous execution - falls back to GCD for true parallelism without async overhead.
    @inlinable
    public func execute<F: WordFilter>(filter: F, over words: [Word]) -> [Word] {
        // Use GCD for sync path - avoids semaphore/Task overhead
        GCDParallelExecutor(chunkCount: chunkCount).execute(filter: filter, over: words)
    }

    /// Async version for use in async contexts.
    @inlinable
    public func executeAsync<F: WordFilter>(filter: F, over words: [Word]) async -> [Word] {
        let wordCount = words.count
        let chunkSize = (wordCount + chunkCount - 1) / chunkCount

        return await withTaskGroup(of: [Word].self, returning: [Word].self) { group in
            for chunkIndex in 0..<chunkCount {
                let start = chunkIndex * chunkSize
                let end = min(start + chunkSize, wordCount)

                group.addTask {
                    var chunkResults: [Word] = []
                    chunkResults.reserveCapacity((end - start) / 4)

                    for i in start..<end {
                        if filter.matches(words[i]) {
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

// MARK: - Adaptive Executor

/// Automatically selects the best execution strategy based on constraints.
public struct AdaptiveExecutor: FilterExecutor {
    @usableFromInline let sequentialExecutor = SequentialExecutor()
    @usableFromInline let parallelExecutor: TaskGroupExecutor

    @inlinable
    public init() {
        self.parallelExecutor = TaskGroupExecutor()
    }

    @inlinable
    public func execute<F: WordFilter>(filter: F, over words: [Word]) -> [Word] {
        // Use parallel for larger word lists
        if words.count >= 5000 {
            return parallelExecutor.execute(filter: filter, over: words)
        } else {
            return sequentialExecutor.execute(filter: filter, over: words)
        }
    }

    /// Async version with smarter heuristics.
    @inlinable
    public func executeAsync<F: WordFilter>(filter: F, over words: [Word]) async -> [Word] {
        // Always use parallel in async context - TaskGroup has low overhead
        await parallelExecutor.executeAsync(filter: filter, over: words)
    }
}
