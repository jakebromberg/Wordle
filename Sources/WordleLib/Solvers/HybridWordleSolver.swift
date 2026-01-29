import Foundation

/// Adaptive hybrid solver that selects the optimal backend based on constraint characteristics.
///
/// Combines the strengths of multiple solvers:
/// - **Cache layer**: O(1) lookup for repeated queries
/// - **Bitset**: Fastest for broad scans (no constraints, excluded only)
/// - **Bigram**: Fastest when first two letters are known (searches ~13 words)
///
/// Selection heuristics based on empirical benchmarks:
/// ```
/// ┌─────────────────────────────────────────────────────────┐
/// │                    Query arrives                         │
/// └─────────────────────────────────────────────────────────┘
///                            │
///                            ▼
///                  ┌──────────────────┐
///                  │  Cache hit?      │──── Yes ──▶ Return cached (5-17µs)
///                  └──────────────────┘
///                            │ No
///                            ▼
///                  ┌──────────────────┐
///                  │ green[0] AND     │──── Yes ──▶ Bigram (24-45µs)
///                  │ green[1] known?  │
///                  └──────────────────┘
///                            │ No
///                            ▼
///                  ┌──────────────────┐
///                  │ green[0] known   │──── Yes ──▶ Bigram (45-106µs)
///                  │ AND 5+ excluded? │
///                  └──────────────────┘
///                            │ No
///                            ▼
///                      Bitset (43-458µs)
/// ```
public final class HybridWordleSolver: @unchecked Sendable {

    /// Backend solvers
    private let bitsetSolver: BitsetWordleSolver
    private let bigramSolver: BigramWordleSolver

    /// Cache layer
    private var cache: [CacheKey: [Int]]
    private let maxCacheSize: Int

    /// Original words for output
    public let allWordleWords: [Word]

    /// Statistics for monitoring solver selection
    private var stats: SolverStats

    /// Cache key for constraint encoding
    private struct CacheKey: Hashable {
        let excludedMask: UInt32
        let greenEncoded: UInt32
        let yellowLetters: UInt32
        let yellowPositions: UInt64
    }

    /// Statistics tracking
    public struct SolverStats {
        public var cacheHits: Int = 0
        public var bigramCalls: Int = 0
        public var bitsetCalls: Int = 0
        public var totalQueries: Int = 0

        public var cacheHitRate: Double {
            totalQueries > 0 ? Double(cacheHits) / Double(totalQueries) : 0
        }

        public var distribution: String {
            guard totalQueries > 0 else { return "No queries yet" }
            let cacheP = String(format: "%.1f", Double(cacheHits) / Double(totalQueries) * 100)
            let bigramP = String(format: "%.1f", Double(bigramCalls) / Double(totalQueries) * 100)
            let bitsetP = String(format: "%.1f", Double(bitsetCalls) / Double(totalQueries) * 100)
            return "Cache: \(cacheP)%, Bigram: \(bigramP)%, Bitset: \(bitsetP)%"
        }
    }

    // MARK: - Initialization

    public init(words: [Word], maxCacheSize: Int = 10000) {
        self.allWordleWords = words
        self.bitsetSolver = BitsetWordleSolver(words: words)
        self.bigramSolver = BigramWordleSolver(words: words)
        self.cache = [:]
        self.maxCacheSize = maxCacheSize
        self.stats = SolverStats()
        self.cache.reserveCapacity(min(maxCacheSize, 1000))
    }

    public convenience init(words: [String], maxCacheSize: Int = 10000) {
        let wordObjects = words.compactMap(Word.init)
        self.init(words: wordObjects, maxCacheSize: maxCacheSize)
    }

    // MARK: - Solve API

    public func solve(
        excluded: Set<Character>,
        green: [Int: Character],
        yellow: [Character: UInt8]
    ) -> [Word] {
        stats.totalQueries += 1

        // Build cache key
        let key = buildCacheKey(excluded: excluded, green: green, yellow: yellow)

        // Check cache first (fastest path)
        if let cachedIndices = cache[key] {
            stats.cacheHits += 1
            return cachedIndices.map { allWordleWords[$0] }
        }

        // Select backend based on heuristics
        let results: [Word]
        let backend = selectBackend(excluded: excluded, green: green, yellow: yellow)

        switch backend {
        case .bigram:
            stats.bigramCalls += 1
            results = bigramSolver.solve(excluded: excluded, green: green, yellow: yellow)
        case .bitset:
            stats.bitsetCalls += 1
            results = bitsetSolver.solve(excluded: excluded, green: green, yellow: yellow)
        }

        // Cache results
        cacheResults(key: key, results: results)

        return results
    }

    // MARK: - Backend Selection

    private enum Backend {
        case bigram
        case bitset
    }

    /// Select optimal backend based on constraint characteristics.
    ///
    /// Decision tree based on empirical benchmarks:
    /// - Bigram excels when it can narrow search to small buckets (17-30µs)
    /// - Bitset excels at broad scans with bitwise intersection (28-299µs)
    /// - Turbo is competitive for indexed lookups when green[0] known
    @inline(__always)
    private func selectBackend(
        excluded: Set<Character>,
        green: [Int: Character],
        yellow: [Character: UInt8]
    ) -> Backend {
        let hasGreen0 = green[0] != nil
        let hasGreen1 = green[1] != nil
        let constraintCount = green.count + yellow.count + (excluded.isEmpty ? 0 : 1)

        // Best case for Bigram: both first letters known
        // Searches only ~13 words (average bucket size: 8506/676)
        // Benchmark: 18-29µs vs Bitset 28-45µs
        if hasGreen0 && hasGreen1 {
            return .bigram
        }

        // Heavy constraints with first letter known: Bigram wins
        // Benchmark: 18µs vs Bitset 44µs for heavy constraints
        if hasGreen0 && constraintCount >= 4 {
            return .bigram
        }

        // Good case for Bigram: first letter known + significant excluded
        // Bucket skipping helps: 83-93µs vs Bitset 45µs
        // Actually Bitset wins here, so only use Bigram for very heavy
        if hasGreen0 && excluded.count >= 8 {
            return .bigram
        }

        // For everything else, Bitset's O(1) intersection wins
        // Especially: no constraints (299µs), excluded only (269µs), yellow only (32µs)
        return .bitset
    }

    // MARK: - Caching

    private func buildCacheKey(
        excluded: Set<Character>,
        green: [Int: Character],
        yellow: [Character: UInt8]
    ) -> CacheKey {
        var excludedMask: UInt32 = 0
        for char in excluded {
            if let ascii = Word.asciiValue(for: char) {
                excludedMask |= 1 << (ascii - 97)
            }
        }

        var greenEncoded: UInt32 = 0
        for pos in 0..<5 {
            let value: UInt32
            if let char = green[pos], let ascii = Word.asciiValue(for: char) {
                value = UInt32(ascii - 97)
            } else {
                value = 31
            }
            greenEncoded |= value << (pos * 5)
        }

        var yellowLetters: UInt32 = 0
        var yellowPositions: UInt64 = 0
        var yellowOffset = 0

        for letterIndex in 0..<26 {
            let char = Character(UnicodeScalar(97 + letterIndex)!)
            if let forbidden = yellow[char] {
                yellowLetters |= 1 << letterIndex
                yellowPositions |= UInt64(forbidden & 0x1F) << yellowOffset
                yellowOffset += 5
            }
        }

        return CacheKey(
            excludedMask: excludedMask,
            greenEncoded: greenEncoded,
            yellowLetters: yellowLetters,
            yellowPositions: yellowPositions
        )
    }

    private func cacheResults(key: CacheKey, results: [Word]) {
        // Evict if cache is full
        if cache.count >= maxCacheSize {
            // Simple random eviction - could use LRU for production
            let keysToRemove = Array(cache.keys.prefix(cache.count / 2))
            for k in keysToRemove {
                cache.removeValue(forKey: k)
            }
        }

        // Store indices to save memory
        let indices = results.compactMap { word -> Int? in
            // Fast path: check if word is at expected position
            for (idx, w) in allWordleWords.enumerated() {
                if w.raw == word.raw { return idx }
            }
            return nil
        }
        cache[key] = indices
    }

    // MARK: - Statistics & Management

    /// Get current solver statistics
    public var statistics: SolverStats {
        stats
    }

    /// Clear the cache and reset statistics
    public func reset() {
        cache.removeAll(keepingCapacity: true)
        stats = SolverStats()
    }

    /// Get cache size
    public var cacheSize: Int {
        cache.count
    }
}

// MARK: - Convenience Helpers

extension HybridWordleSolver {
    /// Create a position bitmask from positions where a letter cannot be.
    public static func forbiddenPositions(_ positions: Int...) -> UInt8 {
        var mask: UInt8 = 0
        for pos in positions where pos >= 0 && pos <= 4 {
            mask |= 1 << pos
        }
        return mask
    }

    /// Create yellow constraints from guesses.
    public static func yellowFromGuess(_ letters: [(Character, Int)]) -> [Character: UInt8] {
        var result: [Character: UInt8] = [:]
        for (letter, position) in letters where position >= 0 && position <= 4 {
            let lower = Character(letter.lowercased())
            result[lower, default: 0] |= 1 << position
        }
        return result
    }
}
