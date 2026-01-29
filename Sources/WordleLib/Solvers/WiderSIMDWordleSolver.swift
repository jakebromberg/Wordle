import Foundation
import simd

/// Solver using wider SIMD operations (SIMD16 where available).
///
/// Strategy: Process 16 words at a time using SIMD16<UInt32> for bitmask checks.
/// On Apple Silicon, this uses 128-bit NEON with 2x unrolling for 16-wide effect.
/// On x86, this could use AVX2 (256-bit) or AVX-512 (512-bit) when available.
///
/// Also uses manual loop unrolling and software prefetching hints.
public final class WiderSIMDWordleSolver: @unchecked Sendable {

    /// Packed word representation (padded for SIMD alignment)
    private let packedWords: [UInt64]

    /// Letter masks (padded for SIMD16 alignment)
    private let letterMasks: [UInt32]

    /// Original words for output
    public let allWordleWords: [Word]

    /// First letter index
    private let firstLetterIndex: [(start: Int, count: Int)]

    /// Sorted indices
    private let sortedIndices: [Int]

    /// Padded word count (multiple of 16)
    private let paddedCount: Int

    // MARK: - Initialization

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

        // Flatten buckets
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

        // Pad to multiple of 16
        let actualCount = words.count
        let paddedCount = ((actualCount + 15) / 16) * 16
        self.paddedCount = paddedCount

        // Build packed representations with padding
        var packed: [UInt64] = []
        var masks: [UInt32] = []
        packed.reserveCapacity(paddedCount)
        masks.reserveCapacity(paddedCount)

        for i in indices {
            let word = words[i]
            packed.append(Self.pack(word))
            masks.append(word.letterMask)
        }

        // Pad with invalid entries
        while packed.count < paddedCount {
            packed.append(0)
            masks.append(0xFFFFFFFF)  // Will fail excluded check
        }

        self.packedWords = packed
        self.letterMasks = masks
    }

    public convenience init(words: [String]) {
        let wordObjects = words.compactMap(Word.init)
        self.init(words: wordObjects)
    }

    // MARK: - Packing

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

    // MARK: - Solve API

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

        // Determine search ranges
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

        // SIMD constants
        let excludedVec8 = SIMD8<UInt32>(repeating: excludedMask)
        let requiredVec8 = SIMD8<UInt32>(repeating: requiredMask)
        let zero8 = SIMD8<UInt32>.zero

        for range in searchRanges {
            let rangeEnd = range.start + range.count
            let simd16End = range.start + ((range.count / 16) * 16)

            var i = range.start

            // SIMD16 pass (2x SIMD8 unrolled)
            while i < simd16End {
                // Load 16 masks as two SIMD8 vectors
                let masks0 = SIMD8<UInt32>(
                    letterMasks[i], letterMasks[i+1], letterMasks[i+2], letterMasks[i+3],
                    letterMasks[i+4], letterMasks[i+5], letterMasks[i+6], letterMasks[i+7]
                )
                let masks1 = SIMD8<UInt32>(
                    letterMasks[i+8], letterMasks[i+9], letterMasks[i+10], letterMasks[i+11],
                    letterMasks[i+12], letterMasks[i+13], letterMasks[i+14], letterMasks[i+15]
                )

                // Excluded check
                let excl0 = (masks0 & excludedVec8) .== zero8
                let excl1 = (masks1 & excludedVec8) .== zero8

                // Required check
                let req0 = (masks0 & requiredVec8) .== requiredVec8
                let req1 = (masks1 & requiredVec8) .== requiredVec8

                // Combined mask
                let pass0 = excl0 .& req0
                let pass1 = excl1 .& req1

                // Process first 8
                for j in 0..<8 where pass0[j] {
                    let idx = i + j
                    if idx >= allWordleWords.count { continue }

                    let packed = packedWords[idx]
                    if greenMask != 0 && (packed & greenMask) != greenValue { continue }
                    if !checkYellow(packed: packed, yellow: yellowConstraints) { continue }

                    let originalIndex = sortedIndices[idx]
                    results.append(allWordleWords[originalIndex])
                }

                // Process second 8
                for j in 0..<8 where pass1[j] {
                    let idx = i + 8 + j
                    if idx >= allWordleWords.count { continue }

                    let packed = packedWords[idx]
                    if greenMask != 0 && (packed & greenMask) != greenValue { continue }
                    if !checkYellow(packed: packed, yellow: yellowConstraints) { continue }

                    let originalIndex = sortedIndices[idx]
                    results.append(allWordleWords[originalIndex])
                }

                i += 16
            }

            // SIMD8 remainder
            while i + 8 <= rangeEnd {
                let masks = SIMD8<UInt32>(
                    letterMasks[i], letterMasks[i+1], letterMasks[i+2], letterMasks[i+3],
                    letterMasks[i+4], letterMasks[i+5], letterMasks[i+6], letterMasks[i+7]
                )

                let excl = (masks & excludedVec8) .== zero8
                let req = (masks & requiredVec8) .== requiredVec8
                let pass = excl .& req

                for j in 0..<8 where pass[j] {
                    let idx = i + j
                    if idx >= rangeEnd { continue }

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

    // MARK: - Helpers

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
