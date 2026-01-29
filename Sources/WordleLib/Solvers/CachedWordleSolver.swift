import Foundation

/// Solver with query result caching using constraint encoding.
///
/// Strategy: Encode constraints as a compact key and cache results.
/// For repeated queries with same constraints, return cached results in O(1).
///
/// Useful for interactive use where users refine constraints incrementally.
public final class CachedWordleSolver: @unchecked Sendable {

    /// Underlying solver for cache misses
    private let turboSolver: TurboWordleSolver

    /// Cache of query results
    /// Key: encoded constraint
    /// Value: array of word indices
    private var cache: [CacheKey: [Int]]

    /// Maximum cache size
    private let maxCacheSize: Int

    /// Cache statistics
    private var hits: Int = 0
    private var misses: Int = 0

    /// Original words for output
    public var allWordleWords: [Word] {
        turboSolver.allWordleWords
    }

    /// Cache key that encodes all constraints compactly
    private struct CacheKey: Hashable {
        /// 26 bits for excluded letters
        let excludedMask: UInt32
        /// Green letters encoded: (pos * 26 + letter) bits set for each green
        let greenEncoded: UInt32
        /// Yellow letters: mask of which letters are yellow
        let yellowLetters: UInt32
        /// Yellow positions: packed forbidden positions
        let yellowPositions: UInt64
    }

    // MARK: - Initialization

    public init(words: [Word], maxCacheSize: Int = 10000) {
        self.turboSolver = TurboWordleSolver(words: words)
        self.cache = [:]
        self.maxCacheSize = maxCacheSize
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
        // Build cache key
        let key = buildCacheKey(excluded: excluded, green: green, yellow: yellow)

        // Check cache
        if let cachedIndices = cache[key] {
            hits += 1
            return cachedIndices.map { allWordleWords[$0] }
        }

        misses += 1

        // Cache miss - compute result
        let results = turboSolver.solve(excluded: excluded, green: green, yellow: yellow)

        // Store in cache (with eviction if needed)
        if cache.count >= maxCacheSize {
            // Simple eviction: clear half the cache
            // In production, use LRU or LFU
            let keysToRemove = Array(cache.keys.prefix(cache.count / 2))
            for key in keysToRemove {
                cache.removeValue(forKey: key)
            }
        }

        // Cache word indices (not Word objects) to save memory
        let indices = results.compactMap { word in
            allWordleWords.firstIndex(where: { $0.raw == word.raw })
        }
        cache[key] = indices

        return results
    }

    // MARK: - Cache Key Building

    private func buildCacheKey(
        excluded: Set<Character>,
        green: [Int: Character],
        yellow: [Character: UInt8]
    ) -> CacheKey {
        // Excluded mask
        var excludedMask: UInt32 = 0
        for char in excluded {
            if let ascii = Word.asciiValue(for: char) {
                excludedMask |= 1 << (ascii - 97)
            }
        }

        // Green encoded: for each green, set bit at (pos * 5 + letterIndex)
        // Since we have 5 positions × 26 letters = 130 possible greens,
        // but we only have up to 5 greens, we encode differently:
        // Use 5 bits per position (0-25 for letter, 31 for none)
        var greenEncoded: UInt32 = 0
        for pos in 0..<5 {
            let value: UInt32
            if let char = green[pos], let ascii = Word.asciiValue(for: char) {
                value = UInt32(ascii - 97)
            } else {
                value = 31  // No green at this position
            }
            greenEncoded |= value << (pos * 5)
        }

        // Yellow letters mask
        var yellowLetters: UInt32 = 0
        var yellowPositions: UInt64 = 0
        var yellowOffset = 0

        for letterIndex in 0..<26 {
            let char = Character(UnicodeScalar(97 + letterIndex)!)
            if let forbidden = yellow[char] {
                yellowLetters |= 1 << letterIndex
                // Pack 5 bits of forbidden positions
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

    // MARK: - Statistics

    /// Get cache hit ratio
    public var hitRatio: Double {
        let total = hits + misses
        return total > 0 ? Double(hits) / Double(total) : 0
    }

    /// Get cache size
    public var cacheSize: Int {
        cache.count
    }

    /// Clear the cache
    public func clearCache() {
        cache.removeAll(keepingCapacity: true)
        hits = 0
        misses = 0
    }

    /// Get cache statistics
    public var statistics: (hits: Int, misses: Int, size: Int, hitRatio: Double) {
        (hits, misses, cache.count, hitRatio)
    }
}
