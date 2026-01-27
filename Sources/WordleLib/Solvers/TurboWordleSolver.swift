import Foundation
import simd

/// Ultra-optimized solver combining multiple advanced techniques:
/// - Packed 40-bit word representation for single-instruction green checks
/// - First-letter indexing for O(1) bucket selection
/// - Branch-free filtering using arithmetic operations
/// - SIMD-width aligned memory for optimal cache utilization
public final class TurboWordleSolver: @unchecked Sendable {

    // MARK: - Packed Word Storage

    /// Packed representation: 5 bytes in a UInt64 (bits 0-39)
    /// Layout: [byte0: 0-7] [byte1: 8-15] [byte2: 16-23] [byte3: 24-31] [byte4: 32-39]
    /// This allows checking all green positions with a single mask & compare.
    private let packedWords: [UInt64]

    /// Letter masks for bitmask filtering (parallel array)
    private let letterMasks: [UInt32]

    /// Original words for result output
    public let allWordleWords: [Word]

    // MARK: - First-Letter Index

    /// Index ranges by first letter: firstLetterIndex[letter - 'a'] = (start, count)
    /// Words are sorted by first letter for cache-friendly sequential access.
    private let firstLetterIndex: [(start: Int, count: Int)]

    /// Sorted indices into the original word array
    private let sortedIndices: [Int]

    // MARK: - Initialization

    public init(words: [Word]) {
        self.allWordleWords = words

        // Build first-letter buckets
        var buckets: [[Int]] = Array(repeating: [], count: 26)
        for (index, word) in words.enumerated() {
            let firstLetter = Int(word[0] - 97) // 'a' = 97
            if firstLetter >= 0 && firstLetter < 26 {
                buckets[firstLetter].append(index)
            }
        }

        // Flatten buckets into sorted indices and build index
        var indices: [Int] = []
        var index: [(start: Int, count: Int)] = []
        indices.reserveCapacity(words.count)

        for bucket in buckets {
            let start = indices.count
            indices.append(contentsOf: bucket)
            index.append((start: start, count: bucket.count))
        }

        self.sortedIndices = indices
        self.firstLetterIndex = index

        // Build packed representations in sorted order
        var packed: [UInt64] = []
        var masks: [UInt32] = []
        packed.reserveCapacity(words.count)
        masks.reserveCapacity(words.count)

        for i in indices {
            let word = words[i]
            packed.append(Self.pack(word))
            masks.append(word.letterMask)
        }

        self.packedWords = packed
        self.letterMasks = masks
    }

    public convenience init(words: [String]) {
        let wordObjects = words.compactMap(Word.init)
        self.init(words: wordObjects)
    }

    // MARK: - Packing

    /// Pack 5 bytes into lower 40 bits of UInt64
    @inline(__always)
    private static func pack(_ word: Word) -> UInt64 {
        var packed: UInt64 = 0
        packed |= UInt64(word[0])
        packed |= UInt64(word[1]) << 8
        packed |= UInt64(word[2]) << 16
        packed |= UInt64(word[3]) << 24
        packed |= UInt64(word[4]) << 32
        return packed
    }

    /// Build a green mask and expected value for packed comparison
    /// Returns (mask, expected) where (packed & mask) == expected means match
    @inline(__always)
    private static func buildGreenMaskAndValue(_ green: [Int: Character]) -> (UInt64, UInt64) {
        var mask: UInt64 = 0
        var value: UInt64 = 0

        for (pos, char) in green {
            guard let ascii = Word.asciiValue(for: char), pos >= 0, pos < 5 else { continue }
            let shift = pos * 8
            mask |= 0xFF << shift
            value |= UInt64(ascii) << shift
        }

        return (mask, value)
    }

    // MARK: - Solve API

    public func solve(
        excluded: Set<Character>,
        green: [Int: Character],
        yellow: [Character: UInt8]
    ) -> [Word] {
        // Build constraint data
        let placedLetters = Set(green.values)
        let effectiveExcluded = excluded.subtracting(placedLetters)
        let required = placedLetters.union(yellow.keys)

        let excludedMask = buildMask(from: effectiveExcluded)
        let requiredMask = buildMask(from: required)

        // Build packed green constraint
        let (greenMask, greenValue) = Self.buildGreenMaskAndValue(green)

        // Build yellow constraints
        let yellowConstraints: [(UInt8, UInt8)] = yellow.compactMap { char, forbidden in
            guard let ascii = Word.asciiValue(for: char) else { return nil }
            return (ascii, forbidden)
        }

        // Determine search range based on first letter
        let searchRanges: [(start: Int, count: Int)]
        if let firstLetterChar = green[0], let ascii = Word.asciiValue(for: firstLetterChar) {
            // Only search the bucket for this first letter
            let bucketIndex = Int(ascii - 97)
            if bucketIndex >= 0 && bucketIndex < 26 {
                searchRanges = [firstLetterIndex[bucketIndex]]
            } else {
                searchRanges = []
            }
        } else {
            // Search all buckets, but skip ones with excluded first letters
            searchRanges = (0..<26).compactMap { bucketIndex -> (start: Int, count: Int)? in
                let letterBit: UInt32 = 1 << bucketIndex
                // Skip bucket if first letter is excluded
                if (excludedMask & letterBit) != 0 {
                    return nil
                }
                let range = firstLetterIndex[bucketIndex]
                return range.count > 0 ? range : nil
            }
        }

        var results: [Word] = []
        results.reserveCapacity(allWordleWords.count / 4)

        // Process each search range
        for range in searchRanges {
            let end = range.start + range.count

            for i in range.start..<end {
                let mask = letterMasks[i]

                // Branch-free bitmask check:
                // excluded check: (mask & excludedMask) == 0
                // required check: (mask & requiredMask) == requiredMask
                let excludedOK = (mask & excludedMask) == 0
                let requiredOK = (mask & requiredMask) == requiredMask

                guard excludedOK && requiredOK else { continue }

                // Packed green check - single comparison for all green positions
                let packed = packedWords[i]
                if greenMask != 0 && (packed & greenMask) != greenValue {
                    continue
                }

                // Yellow position check
                if !checkYellowPositions(packed: packed, yellow: yellowConstraints) {
                    continue
                }

                let originalIndex = sortedIndices[i]
                results.append(allWordleWords[originalIndex])
            }
        }

        return results
    }

    // MARK: - Yellow Position Checking

    @inline(__always)
    private func checkYellowPositions(packed: UInt64, yellow: [(UInt8, UInt8)]) -> Bool {
        for (ascii, forbidden) in yellow {
            // Extract each byte and check against forbidden positions
            if (forbidden & 0b00001) != 0 && UInt8(packed & 0xFF) == ascii { return false }
            if (forbidden & 0b00010) != 0 && UInt8((packed >> 8) & 0xFF) == ascii { return false }
            if (forbidden & 0b00100) != 0 && UInt8((packed >> 16) & 0xFF) == ascii { return false }
            if (forbidden & 0b01000) != 0 && UInt8((packed >> 24) & 0xFF) == ascii { return false }
            if (forbidden & 0b10000) != 0 && UInt8((packed >> 32) & 0xFF) == ascii { return false }
        }
        return true
    }

    // MARK: - Helpers

    private func buildMask(from chars: Set<Character>) -> UInt32 {
        var mask: UInt32 = 0
        for char in chars {
            if let bit = Word.bit(for: char) {
                mask |= bit
            }
        }
        return mask
    }

    // MARK: - Convenience Helpers

    /// Create a position bitmask from positions where a letter cannot be.
    /// Example: `forbiddenPositions(1, 2)` returns `0b00110`
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

// MARK: - SIMD-Enhanced Turbo Solver

/// Even faster variant using SIMD for batch bitmask checking combined with indexing.
public final class SIMDTurboSolver: @unchecked Sendable {

    private let packedWords: [UInt64]
    private let letterMasks: [UInt32]
    public let allWordleWords: [Word]
    private let firstLetterIndex: [(start: Int, count: Int)]
    private let sortedIndices: [Int]

    public init(words: [Word]) {
        self.allWordleWords = words

        // Build first-letter buckets
        var buckets: [[Int]] = Array(repeating: [], count: 26)
        for (index, word) in words.enumerated() {
            let firstLetter = Int(word[0] - 97)
            if firstLetter >= 0 && firstLetter < 26 {
                buckets[firstLetter].append(index)
            }
        }

        // Flatten with padding for SIMD alignment
        var indices: [Int] = []
        var index: [(start: Int, count: Int)] = []

        for bucket in buckets {
            let start = indices.count
            indices.append(contentsOf: bucket)
            index.append((start: start, count: bucket.count))
        }

        self.sortedIndices = indices
        self.firstLetterIndex = index

        // Build packed representations
        var packed: [UInt64] = []
        var masks: [UInt32] = []
        packed.reserveCapacity(words.count + 8) // Extra for SIMD padding
        masks.reserveCapacity(words.count + 8)

        for i in indices {
            let word = words[i]
            packed.append(Self.pack(word))
            masks.append(word.letterMask)
        }

        // Pad to SIMD width
        while packed.count % 8 != 0 {
            packed.append(0)
            masks.append(0xFFFFFFFF) // Will fail excluded check
        }

        self.packedWords = packed
        self.letterMasks = masks
    }

    public convenience init(words: [String]) {
        let wordObjects = words.compactMap(Word.init)
        self.init(words: wordObjects)
    }

    @inline(__always)
    private static func pack(_ word: Word) -> UInt64 {
        var packed: UInt64 = 0
        packed |= UInt64(word[0])
        packed |= UInt64(word[1]) << 8
        packed |= UInt64(word[2]) << 16
        packed |= UInt64(word[3]) << 24
        packed |= UInt64(word[4]) << 32
        return packed
    }

    public func solve(
        excluded: Set<Character>,
        green: [Int: Character],
        yellow: [Character: UInt8]
    ) -> [Word] {
        let placedLetters = Set(green.values)
        let effectiveExcluded = excluded.subtracting(placedLetters)
        let required = placedLetters.union(yellow.keys)

        let excludedMask = buildMask(from: effectiveExcluded)
        let requiredMask = buildMask(from: required)

        // Build packed green constraint
        var greenMask: UInt64 = 0
        var greenValue: UInt64 = 0
        for (pos, char) in green {
            guard let ascii = Word.asciiValue(for: char), pos >= 0, pos < 5 else { continue }
            let shift = pos * 8
            greenMask |= 0xFF << shift
            greenValue |= UInt64(ascii) << shift
        }

        let yellowConstraints: [(UInt8, UInt8)] = yellow.compactMap { char, forbidden in
            guard let ascii = Word.asciiValue(for: char) else { return nil }
            return (ascii, forbidden)
        }

        // Determine search range
        let searchRanges: [(start: Int, count: Int)]
        if let firstLetterChar = green[0], let ascii = Word.asciiValue(for: firstLetterChar) {
            let bucketIndex = Int(ascii - 97)
            if bucketIndex >= 0 && bucketIndex < 26 {
                searchRanges = [firstLetterIndex[bucketIndex]]
            } else {
                searchRanges = []
            }
        } else {
            searchRanges = (0..<26).compactMap { bucketIndex -> (start: Int, count: Int)? in
                let letterBit: UInt32 = 1 << bucketIndex
                if (excludedMask & letterBit) != 0 { return nil }
                let range = firstLetterIndex[bucketIndex]
                return range.count > 0 ? range : nil
            }
        }

        var results: [Word] = []
        results.reserveCapacity(allWordleWords.count / 4)

        let excludedVec = SIMD8<UInt32>(repeating: excludedMask)
        let requiredVec = SIMD8<UInt32>(repeating: requiredMask)
        let zero = SIMD8<UInt32>.zero

        for range in searchRanges {
            let rangeEnd = range.start + range.count
            let simdEnd = range.start + ((range.count / 8) * 8)

            // SIMD pass
            var i = range.start
            while i < simdEnd {
                let wordMasks = SIMD8<UInt32>(
                    letterMasks[i], letterMasks[i+1], letterMasks[i+2], letterMasks[i+3],
                    letterMasks[i+4], letterMasks[i+5], letterMasks[i+6], letterMasks[i+7]
                )

                let excludedCheck = (wordMasks & excludedVec) .== zero
                let requiredCheck = (wordMasks & requiredVec) .== requiredVec
                let passedMask = excludedCheck .& requiredCheck

                for j in 0..<8 where passedMask[j] {
                    let idx = i + j
                    let packed = packedWords[idx]

                    if greenMask != 0 && (packed & greenMask) != greenValue { continue }
                    if !checkYellow(packed: packed, yellow: yellowConstraints) { continue }

                    let originalIndex = sortedIndices[idx]
                    results.append(allWordleWords[originalIndex])
                }
                i += 8
            }

            // Scalar remainder
            while i < rangeEnd {
                let mask = letterMasks[i]
                if (mask & excludedMask) != 0 { i += 1; continue }
                if (mask & requiredMask) != requiredMask { i += 1; continue }

                let packed = packedWords[i]
                if greenMask != 0 && (packed & greenMask) != greenValue { i += 1; continue }
                if !checkYellow(packed: packed, yellow: yellowConstraints) { i += 1; continue }

                let originalIndex = sortedIndices[i]
                results.append(allWordleWords[originalIndex])
                i += 1
            }
        }

        return results
    }

    @inline(__always)
    private func checkYellow(packed: UInt64, yellow: [(UInt8, UInt8)]) -> Bool {
        for (ascii, forbidden) in yellow {
            if (forbidden & 0b00001) != 0 && UInt8(packed & 0xFF) == ascii { return false }
            if (forbidden & 0b00010) != 0 && UInt8((packed >> 8) & 0xFF) == ascii { return false }
            if (forbidden & 0b00100) != 0 && UInt8((packed >> 16) & 0xFF) == ascii { return false }
            if (forbidden & 0b01000) != 0 && UInt8((packed >> 24) & 0xFF) == ascii { return false }
            if (forbidden & 0b10000) != 0 && UInt8((packed >> 32) & 0xFF) == ascii { return false }
        }
        return true
    }

    private func buildMask(from chars: Set<Character>) -> UInt32 {
        var mask: UInt32 = 0
        for char in chars {
            if let bit = Word.bit(for: char) {
                mask |= bit
            }
        }
        return mask
    }
}
