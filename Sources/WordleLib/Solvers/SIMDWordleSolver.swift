import Foundation
import simd

/// SIMD-accelerated solver that processes multiple words in parallel using vector instructions.
///
/// Uses SIMD8<UInt32> to check 8 word masks simultaneously, potentially providing
/// up to 8x speedup for bitmask operations on supported hardware.
public final class SIMDWordleSolver: @unchecked Sendable {
    public let allWordleWords: [Word]

    /// Contiguous array of letter masks for SIMD access.
    private let masks: [UInt32]

    public init(words: [Word]) {
        self.allWordleWords = words
        self.masks = words.map(\.letterMask)
    }

    public init(words: [String]) {
        self.allWordleWords = words.compactMap(Word.init)
        self.masks = self.allWordleWords.map(\.letterMask)
    }

    public func solve(
        excluded: Set<Character>,
        green: [Int: Character],
        yellow: [Character: UInt8]
    ) -> [Word] {
        // Build constraint masks
        let placedLetters = Set(green.values)
        let effectiveExcluded = excluded.subtracting(placedLetters)
        let required = placedLetters.union(yellow.keys)

        let excludedMask = buildMask(from: effectiveExcluded)
        let requiredMask = buildMask(from: required)

        // Build green constraints
        let greenConstraints: [(Int, UInt8)] = green.compactMap { pos, char in
            guard let ascii = Word.asciiValue(for: char) else { return nil }
            return (pos, ascii)
        }

        // Build yellow position constraints
        let yellowConstraints: [(UInt8, UInt8)] = yellow.compactMap { char, forbidden in
            guard let ascii = Word.asciiValue(for: char) else { return nil }
            return (ascii, forbidden)
        }

        var results: [Word] = []
        results.reserveCapacity(allWordleWords.count / 4)

        let count = masks.count
        let simdWidth = 8
        let simdCount = count / simdWidth

        // SIMD pass: check 8 masks at a time
        let excludedVec = SIMD8<UInt32>(repeating: excludedMask)
        let requiredVec = SIMD8<UInt32>(repeating: requiredMask)
        let zero = SIMD8<UInt32>.zero

        for i in 0..<simdCount {
            let baseIndex = i * simdWidth

            // Load 8 masks
            let wordMasks = SIMD8<UInt32>(
                masks[baseIndex],
                masks[baseIndex + 1],
                masks[baseIndex + 2],
                masks[baseIndex + 3],
                masks[baseIndex + 4],
                masks[baseIndex + 5],
                masks[baseIndex + 6],
                masks[baseIndex + 7]
            )

            // Check excluded: (mask & excluded) == 0
            let excludedCheck = (wordMasks & excludedVec) .== zero

            // Check required: (mask & required) == required
            let requiredCheck = (wordMasks & requiredVec) .== requiredVec

            // Combine checks
            let passedMask = excludedCheck .& requiredCheck

            // Process words that passed bitmask checks
            for j in 0..<simdWidth where passedMask[j] {
                let wordIndex = baseIndex + j
                let word = allWordleWords[wordIndex]

                if checkPositions(word: word, green: greenConstraints, yellow: yellowConstraints) {
                    results.append(word)
                }
            }
        }

        // Handle remainder (words not divisible by 8)
        let remainder = simdCount * simdWidth
        for i in remainder..<count {
            let mask = masks[i]

            if (mask & excludedMask) != 0 { continue }
            if (mask & requiredMask) != requiredMask { continue }

            let word = allWordleWords[i]
            if checkPositions(word: word, green: greenConstraints, yellow: yellowConstraints) {
                results.append(word)
            }
        }

        return results
    }

    @inline(__always)
    private func checkPositions(
        word: Word,
        green: [(Int, UInt8)],
        yellow: [(UInt8, UInt8)]
    ) -> Bool {
        // Check green positions
        for (pos, ascii) in green {
            if word[pos] != ascii { return false }
        }

        // Check yellow positions (letter must not be at forbidden positions)
        for (ascii, forbidden) in yellow {
            if (forbidden & 0b00001) != 0 && word[0] == ascii { return false }
            if (forbidden & 0b00010) != 0 && word[1] == ascii { return false }
            if (forbidden & 0b00100) != 0 && word[2] == ascii { return false }
            if (forbidden & 0b01000) != 0 && word[3] == ascii { return false }
            if (forbidden & 0b10000) != 0 && word[4] == ascii { return false }
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
