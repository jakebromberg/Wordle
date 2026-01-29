import Foundation

/// Solver using two-letter (bigram) indexing for faster lookups.
///
/// Strategy: Index words by first two letters (676 buckets instead of 26).
/// Average bucket size: 8506/676 ≈ 12.6 words vs ~327 with single-letter indexing.
///
/// When green[0] and green[1] are known, search only ~13 words instead of ~327.
public final class BigramWordleSolver: @unchecked Sendable {

    /// Packed word representation
    private let packedWords: [UInt64]

    /// Letter masks for bitmask filtering
    private let letterMasks: [UInt32]

    /// Original words for output
    public let allWordleWords: [Word]

    /// Bigram index: bigramIndex[firstLetter * 26 + secondLetter] = (start, count)
    /// 26 × 26 = 676 buckets
    private let bigramIndex: [(start: Int, count: Int)]

    /// Single-letter index for when only first letter is known
    private let firstLetterIndex: [(start: Int, count: Int)]

    /// Sorted word indices (sorted by bigram)
    private let sortedIndices: [Int]

    // MARK: - Initialization

    public init(words: [Word]) {
        self.allWordleWords = words

        // Build bigram buckets (676 buckets)
        var bigramBuckets: [[Int]] = Array(repeating: [], count: 676)

        for (index, word) in words.enumerated() {
            let first = Int(word[0] - 97)
            let second = Int(word[1] - 97)
            if first >= 0 && first < 26 && second >= 0 && second < 26 {
                let bigramKey = first * 26 + second
                bigramBuckets[bigramKey].append(index)
            }
        }

        // Flatten buckets and build indices
        var indices: [Int] = []
        var bigramIdx: [(start: Int, count: Int)] = []
        var firstLetterIdx: [(start: Int, count: Int)] = Array(repeating: (0, 0), count: 26)

        indices.reserveCapacity(words.count)
        bigramIdx.reserveCapacity(676)

        // Track first letter ranges
        var currentFirstLetter = -1
        var firstLetterStart = 0

        for bigramKey in 0..<676 {
            let firstLetter = bigramKey / 26
            let bucket = bigramBuckets[bigramKey]

            // Track first letter boundaries
            if firstLetter != currentFirstLetter {
                if currentFirstLetter >= 0 {
                    firstLetterIdx[currentFirstLetter] = (firstLetterStart, indices.count - firstLetterStart)
                }
                currentFirstLetter = firstLetter
                firstLetterStart = indices.count
            }

            let start = indices.count
            indices.append(contentsOf: bucket)
            bigramIdx.append((start: start, count: bucket.count))
        }

        // Finalize last first letter
        if currentFirstLetter >= 0 {
            firstLetterIdx[currentFirstLetter] = (firstLetterStart, indices.count - firstLetterStart)
        }

        self.sortedIndices = indices
        self.bigramIndex = bigramIdx
        self.firstLetterIndex = firstLetterIdx

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

        let yellowConstraints: [(UInt8, UInt8)] = yellow.compactMap { char, forbidden in
            guard let ascii = Word.asciiValue(for: char) else { return nil }
            return (ascii, forbidden)
        }

        // Determine search ranges using bigram or single-letter index
        let searchRanges = determineSearchRanges(green: green, excludedMask: excludedMask)

        var results: [Word] = []
        results.reserveCapacity(allWordleWords.count / 4)

        for range in searchRanges {
            let end = range.start + range.count

            for i in range.start..<end {
                let mask = letterMasks[i]

                // Bitmask checks
                if (mask & excludedMask) != 0 { continue }
                if (mask & requiredMask) != requiredMask { continue }

                // Green check
                let packed = packedWords[i]
                if greenMask != 0 && (packed & greenMask) != greenValue { continue }

                // Yellow position check
                if !checkYellowPositions(packed: packed, yellow: yellowConstraints) { continue }

                let originalIndex = sortedIndices[i]
                results.append(allWordleWords[originalIndex])
            }
        }

        return results
    }

    // MARK: - Index Selection

    private func determineSearchRanges(
        green: [Int: Character],
        excludedMask: UInt32
    ) -> [(start: Int, count: Int)] {
        // Best case: both first and second letter known
        if let first = green[0], let second = green[1],
           let firstAscii = Word.asciiValue(for: first),
           let secondAscii = Word.asciiValue(for: second) {
            let firstIdx = Int(firstAscii - 97)
            let secondIdx = Int(secondAscii - 97)
            if firstIdx >= 0 && firstIdx < 26 && secondIdx >= 0 && secondIdx < 26 {
                let bigramKey = firstIdx * 26 + secondIdx
                let range = bigramIndex[bigramKey]
                return range.count > 0 ? [range] : []
            }
        }

        // Second best: only first letter known
        if let first = green[0], let firstAscii = Word.asciiValue(for: first) {
            let firstIdx = Int(firstAscii - 97)
            if firstIdx >= 0 && firstIdx < 26 {
                let range = firstLetterIndex[firstIdx]
                return range.count > 0 ? [range] : []
            }
        }

        // Only second letter known: search all bigrams with that second letter
        if let second = green[1], let secondAscii = Word.asciiValue(for: second) {
            let secondIdx = Int(secondAscii - 97)
            if secondIdx >= 0 && secondIdx < 26 {
                var ranges: [(start: Int, count: Int)] = []
                for firstIdx in 0..<26 {
                    // Skip if first letter is excluded
                    let letterBit: UInt32 = 1 << firstIdx
                    if (excludedMask & letterBit) != 0 { continue }

                    let bigramKey = firstIdx * 26 + secondIdx
                    let range = bigramIndex[bigramKey]
                    if range.count > 0 {
                        ranges.append(range)
                    }
                }
                return ranges
            }
        }

        // Fallback: search all non-excluded first letters
        return (0..<26).compactMap { firstIdx -> (start: Int, count: Int)? in
            let letterBit: UInt32 = 1 << firstIdx
            if (excludedMask & letterBit) != 0 { return nil }
            let range = firstLetterIndex[firstIdx]
            return range.count > 0 ? range : nil
        }
    }

    // MARK: - Yellow Position Checking

    @inline(__always)
    private func checkYellowPositions(packed: UInt64, yellow: [(UInt8, UInt8)]) -> Bool {
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
