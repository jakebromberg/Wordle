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
        yellow: Set<Character>
    ) -> [Word] {
        // Build constraint masks
        let placedLetters = Set(green.values)
        let effectiveExcluded = excluded.subtracting(placedLetters)
        let required = placedLetters.union(yellow)

        let excludedMask = buildMask(from: effectiveExcluded)
        let requiredMask = buildMask(from: required)

        // Build green constraints
        let greenConstraints: [(Int, UInt8)] = green.compactMap { pos, char in
            guard let ascii = Word.asciiValue(for: char) else { return nil }
            return (pos, ascii)
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

                // Check green positions
                var passesGreen = true
                for (pos, ascii) in greenConstraints {
                    if word[pos] != ascii {
                        passesGreen = false
                        break
                    }
                }

                if passesGreen {
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
            var passesGreen = true
            for (pos, ascii) in greenConstraints {
                if word[pos] != ascii {
                    passesGreen = false
                    break
                }
            }

            if passesGreen {
                results.append(word)
            }
        }

        return results
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
