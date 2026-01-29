import Foundation

/// Simple cached solver using only Bitset backend.
///
/// No backend selection logic - just Cache + Bitset.
/// Simpler architecture, fewer branches, potentially faster.
public final class CachedBitsetSolver: @unchecked Sendable {

    /// Backend solver
    private let bitsetSolver: BitsetWordleSolver

    /// Cache: constraint key -> word indices
    private var cache: [UInt64: [Int]]
    private let maxCacheSize: Int

    /// Original words
    public let allWordleWords: [Word]

    // MARK: - Initialization

    public init(words: [Word], maxCacheSize: Int = 10000) {
        self.allWordleWords = words
        self.bitsetSolver = BitsetWordleSolver(words: words)
        self.cache = [:]
        self.maxCacheSize = maxCacheSize
        self.cache.reserveCapacity(min(maxCacheSize, 1000))
    }

    public convenience init(words: [String], maxCacheSize: Int = 10000) {
        let wordObjects = words.compactMap(Word.init)
        self.init(words: wordObjects, maxCacheSize: maxCacheSize)
    }

    // MARK: - Solve

    public func solve(
        excluded: Set<Character>,
        green: [Int: Character],
        yellow: [Character: UInt8]
    ) -> [Word] {
        // Build compact cache key (single UInt64 hash)
        let key = buildKey(excluded: excluded, green: green, yellow: yellow)

        // Cache hit - fast path
        if let indices = cache[key] {
            return indices.map { allWordleWords[$0] }
        }

        // Cache miss - compute with Bitset
        let results = bitsetSolver.solve(excluded: excluded, green: green, yellow: yellow)

        // Cache results
        if cache.count >= maxCacheSize {
            cache.removeAll(keepingCapacity: true)
        }
        cache[key] = results.compactMap { word in
            allWordleWords.firstIndex { $0.raw == word.raw }
        }

        return results
    }

    // MARK: - Key Building

    /// Build a compact 64-bit key from constraints.
    /// Not collision-free but good enough for caching.
    @inline(__always)
    private func buildKey(
        excluded: Set<Character>,
        green: [Int: Character],
        yellow: [Character: UInt8]
    ) -> UInt64 {
        var key: UInt64 = 0

        // Pack excluded (26 bits)
        for char in excluded {
            if let ascii = Word.asciiValue(for: char) {
                key |= 1 << (ascii - 97)
            }
        }

        // Pack green (5 positions × 5 bits = 25 bits, starting at bit 26)
        for pos in 0..<5 {
            if let char = green[pos], let ascii = Word.asciiValue(for: char) {
                let value = UInt64(ascii - 97)
                key |= value << (26 + pos * 5)
            } else {
                key |= 31 << (26 + pos * 5)  // 31 = no green at this position
            }
        }

        // Pack yellow presence (use remaining bits for hash)
        var yellowHash: UInt64 = 0
        for (char, forbidden) in yellow {
            if let ascii = Word.asciiValue(for: char) {
                yellowHash ^= UInt64(ascii) << ((ascii - 97) % 8)
                yellowHash ^= UInt64(forbidden) << 8
            }
        }
        key ^= yellowHash << 51

        return key
    }
}
