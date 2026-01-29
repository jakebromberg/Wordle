import Foundation

/// Solver using precomputed bitsets for constraint intersection.
///
/// Strategy: Precompute bitsets for each constraint type at init time.
/// Query becomes O(1) bitwise AND operations instead of iterating through words.
///
/// Memory: ~160KB for all bitsets (26 excluded + 26×5 green + 26 contains)
///
/// Uses ContiguousArray internally for guaranteed contiguous storage and
/// faster iteration (avoids Objective-C bridging checks).
public final class BitsetWordleSolver: @unchecked Sendable {

    /// Number of UInt64s needed to represent all words as bits
    private let bitsetSize: Int

    /// Words for output (ContiguousArray for faster indexed access)
    public var allWordleWords: [Word] {
        Array(_allWordleWords)
    }
    private let _allWordleWords: ContiguousArray<Word>

    // MARK: - Precomputed Bitsets (ContiguousArray for performance)

    /// excludedBitsets[letter]: words that DON'T contain letter (for excluded constraint)
    /// Bit i is set if word i does NOT contain the letter
    private let excludedBitsets: ContiguousArray<ContiguousArray<UInt64>>

    /// greenBitsets[position][letter]: words with letter at position
    /// Bit i is set if word i has the letter at that position
    private let greenBitsets: ContiguousArray<ContiguousArray<ContiguousArray<UInt64>>>

    /// containsBitsets[letter]: words that contain letter (for yellow/required)
    /// Bit i is set if word i contains the letter
    private let containsBitsets: ContiguousArray<ContiguousArray<UInt64>>

    /// All 1s bitset (all words valid)
    private let allOnesBitset: ContiguousArray<UInt64>

    // MARK: - Initialization

    public init(words: [Word]) {
        self._allWordleWords = ContiguousArray(words)

        // Calculate bitset size (ceil(wordCount / 64))
        let wordCount = words.count
        self.bitsetSize = (wordCount + 63) / 64

        // Initialize all bitsets
        let zeroBitset = ContiguousArray<UInt64>(repeating: 0, count: bitsetSize)
        var allOnes = ContiguousArray<UInt64>(repeating: UInt64.max, count: bitsetSize)
        // Clear unused bits in last element
        let usedBits = wordCount % 64
        if usedBits > 0 {
            allOnes[bitsetSize - 1] = (1 << usedBits) - 1
        }
        self.allOnesBitset = allOnes

        // Build excludedBitsets (words NOT containing letter)
        var excluded = ContiguousArray<ContiguousArray<UInt64>>()
        excluded.reserveCapacity(26)
        for _ in 0..<26 { excluded.append(zeroBitset) }

        // Build containsBitsets (words containing letter)
        var contains = ContiguousArray<ContiguousArray<UInt64>>()
        contains.reserveCapacity(26)
        for _ in 0..<26 { contains.append(zeroBitset) }

        // Build greenBitsets (words with letter at position)
        var green = ContiguousArray<ContiguousArray<ContiguousArray<UInt64>>>()
        green.reserveCapacity(5)
        for _ in 0..<5 {
            var posArray = ContiguousArray<ContiguousArray<UInt64>>()
            posArray.reserveCapacity(26)
            for _ in 0..<26 { posArray.append(zeroBitset) }
            green.append(posArray)
        }

        for (wordIndex, word) in words.enumerated() {
            let bitsetIndex = wordIndex / 64
            let bitPosition = wordIndex % 64
            let bit: UInt64 = 1 << bitPosition

            // Process each letter in the word
            for pos in 0..<5 {
                let letterIndex = Int(word[pos] - 97)  // 'a' = 97
                if letterIndex >= 0 && letterIndex < 26 {
                    green[pos][letterIndex][bitsetIndex] |= bit
                }
            }

            // Process letter mask for contains/excluded
            for letterIndex in 0..<26 {
                let letterBit: UInt32 = 1 << letterIndex
                if (word.letterMask & letterBit) != 0 {
                    // Word contains this letter
                    contains[letterIndex][bitsetIndex] |= bit
                } else {
                    // Word does NOT contain this letter (good for excluded)
                    excluded[letterIndex][bitsetIndex] |= bit
                }
            }
        }

        self.excludedBitsets = excluded
        self.containsBitsets = contains
        self.greenBitsets = green
    }

    public convenience init(words: [String]) {
        let wordObjects = words.compactMap(Word.init)
        self.init(words: wordObjects)
    }

    // MARK: - Solve API

    public func solve(
        excluded: Set<Character>,
        green: [Int: Character],
        yellow: [Character: UInt8]
    ) -> [Word] {
        // Start with all words valid
        var result = allOnesBitset

        // Handle placed letters (green letters shouldn't be excluded)
        let placedLetters = Set(green.values)
        let effectiveExcluded = excluded.subtracting(placedLetters)

        // Apply excluded constraints (AND with "doesn't contain" bitsets)
        for letter in effectiveExcluded {
            guard let ascii = Word.asciiValue(for: letter) else { continue }
            let letterIndex = Int(ascii - 97)
            if letterIndex >= 0 && letterIndex < 26 {
                andBitsets(&result, excludedBitsets[letterIndex])
            }
        }

        // Apply green constraints (AND with "has letter at position" bitsets)
        for (pos, letter) in green {
            guard let ascii = Word.asciiValue(for: letter),
                  pos >= 0 && pos < 5 else { continue }
            let letterIndex = Int(ascii - 97)
            if letterIndex >= 0 && letterIndex < 26 {
                andBitsets(&result, greenBitsets[pos][letterIndex])
            }
        }

        // Apply yellow constraints (must contain letter)
        for (letter, forbidden) in yellow {
            guard let ascii = Word.asciiValue(for: letter) else { continue }
            let letterIndex = Int(ascii - 97)
            if letterIndex >= 0 && letterIndex < 26 {
                // Must contain the letter
                andBitsets(&result, containsBitsets[letterIndex])

                // Must NOT have letter at forbidden positions
                for pos in 0..<5 {
                    if (forbidden & (1 << pos)) != 0 {
                        // Letter cannot be at this position
                        // AND with NOT(greenBitsets[pos][letter])
                        andNotBitsets(&result, greenBitsets[pos][letterIndex])
                    }
                }
            }
        }

        // Extract matching words from bitset
        return extractWords(from: result)
    }

    // MARK: - Bitset Operations

    @inline(__always)
    private func andBitsets(_ a: inout ContiguousArray<UInt64>, _ b: ContiguousArray<UInt64>) {
        for i in 0..<bitsetSize {
            a[i] &= b[i]
        }
    }

    @inline(__always)
    private func andNotBitsets(_ a: inout ContiguousArray<UInt64>, _ b: ContiguousArray<UInt64>) {
        for i in 0..<bitsetSize {
            a[i] &= ~b[i]
        }
    }

    private func extractWords(from bitset: ContiguousArray<UInt64>) -> [Word] {
        var results: [Word] = []
        results.reserveCapacity(bitset.reduce(0) { $0 + $1.nonzeroBitCount })

        for (chunkIndex, chunk) in bitset.enumerated() {
            var bits = chunk
            let baseIndex = chunkIndex * 64

            while bits != 0 {
                let trailingZeros = bits.trailingZeroBitCount
                let wordIndex = baseIndex + trailingZeros
                if wordIndex < _allWordleWords.count {
                    results.append(_allWordleWords[wordIndex])
                }
                bits &= bits - 1  // Clear lowest set bit
            }
        }

        return results
    }
}
