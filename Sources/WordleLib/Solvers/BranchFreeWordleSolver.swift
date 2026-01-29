import Foundation

/// Solver using branch-free operations in the hot loop.
///
/// Strategy: Replace all conditional branches with arithmetic/bitwise operations.
/// Modern CPUs have branch predictors, but mispredictions are expensive.
/// Branch-free code has consistent timing regardless of data patterns.
///
/// Techniques used:
/// - Conditional moves via arithmetic
/// - Bitmask accumulation instead of early exit
/// - SIMD comparison to mask conversion
public final class BranchFreeWordleSolver: @unchecked Sendable {

    /// Packed word representation
    private let packedWords: [UInt64]

    /// Letter masks for bitmask filtering
    private let letterMasks: [UInt32]

    /// Original words for output
    public let allWordleWords: [Word]

    /// Sorted indices by first letter
    private let sortedIndices: [Int]

    /// First letter index
    private let firstLetterIndex: [(start: Int, count: Int)]

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

        // Build packed representations
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

        // Build packed green constraint
        var greenMask: UInt64 = 0
        var greenValue: UInt64 = 0
        for (pos, char) in green {
            guard let ascii = Word.asciiValue(for: char), pos >= 0, pos < 5 else { continue }
            let shift = pos * 8
            greenMask |= 0xFF << shift
            greenValue |= UInt64(ascii) << shift
        }

        // Precompute yellow constraint data for branch-free checking
        // yellowBytes[i] = ASCII value of yellow letter, or 0 if none
        // yellowForbidden[i] = forbidden position mask
        var yellowBytes: [UInt8] = []
        var yellowForbidden: [UInt8] = []
        for (char, forbidden) in yellow {
            if let ascii = Word.asciiValue(for: char) {
                yellowBytes.append(ascii)
                yellowForbidden.append(forbidden)
            }
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

        // Two-pass approach for branch-free:
        // 1. Compute validity mask for all words
        // 2. Collect valid words

        var validIndices: [Int] = []
        validIndices.reserveCapacity(allWordleWords.count / 4)

        for range in searchRanges {
            let end = range.start + range.count

            for i in range.start..<end {
                // Branch-free validity computation
                let valid = computeValidityBranchFree(
                    index: i,
                    excludedMask: excludedMask,
                    requiredMask: requiredMask,
                    greenMask: greenMask,
                    greenValue: greenValue,
                    yellowBytes: yellowBytes,
                    yellowForbidden: yellowForbidden
                )

                // Use the validity to conditionally append
                // This is still a branch, but it's the only one in the hot loop
                if valid != 0 {
                    validIndices.append(i)
                }
            }
        }

        // Convert to words
        return validIndices.map { allWordleWords[sortedIndices[$0]] }
    }

    // MARK: - Branch-Free Validity Check

    /// Returns non-zero if word is valid, zero otherwise
    @inline(__always)
    private func computeValidityBranchFree(
        index: Int,
        excludedMask: UInt32,
        requiredMask: UInt32,
        greenMask: UInt64,
        greenValue: UInt64,
        yellowBytes: [UInt8],
        yellowForbidden: [UInt8]
    ) -> Int {
        let mask = letterMasks[index]
        let packed = packedWords[index]

        // Excluded check: (mask & excludedMask) == 0
        // Convert to: valid if excluded check passes
        let excludedCheck = mask & excludedMask
        let excludedValid = (excludedCheck == 0) ? 1 : 0

        // Required check: (mask & requiredMask) == requiredMask
        let requiredCheck = mask & requiredMask
        let requiredValid = (requiredCheck == requiredMask) ? 1 : 0

        // Green check: (packed & greenMask) == greenValue
        let greenCheck = packed & greenMask
        // If greenMask is 0, skip check (always valid)
        let greenValid = (greenMask == 0 || greenCheck == greenValue) ? 1 : 0

        // Yellow position check (branch-free)
        var yellowValid = 1
        for j in 0..<yellowBytes.count {
            let ascii = yellowBytes[j]
            let forbidden = yellowForbidden[j]

            // Check each position branch-free
            // For each position, compute: (forbidden & positionBit) != 0 && byte == ascii
            // If true for any position, word is invalid

            let byte0 = UInt8(packed & 0xFF)
            let byte1 = UInt8((packed >> 8) & 0xFF)
            let byte2 = UInt8((packed >> 16) & 0xFF)
            let byte3 = UInt8((packed >> 24) & 0xFF)
            let byte4 = UInt8((packed >> 32) & 0xFF)

            // Compute match at each forbidden position
            // match = (positionForbidden && letterMatches)
            let match0 = ((forbidden & 0b00001) != 0 && byte0 == ascii) ? 1 : 0
            let match1 = ((forbidden & 0b00010) != 0 && byte1 == ascii) ? 1 : 0
            let match2 = ((forbidden & 0b00100) != 0 && byte2 == ascii) ? 1 : 0
            let match3 = ((forbidden & 0b01000) != 0 && byte3 == ascii) ? 1 : 0
            let match4 = ((forbidden & 0b10000) != 0 && byte4 == ascii) ? 1 : 0

            // If any match, this yellow constraint is violated
            let anyMatch = match0 | match1 | match2 | match3 | match4

            // Branch-free: yellowValid &= (1 - anyMatch)
            // If anyMatch is 1, this becomes 0 and invalidates yellowValid
            yellowValid &= (1 - anyMatch)
        }

        // Combine all validity checks with AND
        return excludedValid & requiredValid & greenValid & yellowValid
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
}
