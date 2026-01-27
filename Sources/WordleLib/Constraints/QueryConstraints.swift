import Foundation

/// Encapsulates all query constraints in a form optimized for repeated matching.
internal struct QueryConstraints: Sendable {
    /// Mask of letters to exclude (with placed letters removed).
    let excludedMask: UInt32

    /// Mask of all letters that must be present (green + yellow).
    let requiredMask: UInt32

    /// Green constraints as (position, ascii) pairs for direct byte comparison.
    let placedConstraints: [(position: Int, ascii: UInt8)]

    init(
        excluded: Set<Character>,
        placed: [Int: Character],
        wrongPlace: Set<Character>
    ) {
        // Build masks
        let placedMask = Self.buildMask(from: placed.values)
        let wrongPlaceMask = Self.buildMask(from: wrongPlace)
        let rawExcludedMask = Self.buildMask(from: excluded)

        // Placed letters override exclusions
        self.excludedMask = rawExcludedMask & ~placedMask
        self.requiredMask = placedMask | wrongPlaceMask

        // Precompute ASCII values for positional checks
        self.placedConstraints = placed.compactMap { position, char in
            guard let ascii = Word.asciiValue(for: char),
                  position >= 0, position <= 4 else { return nil }
            return (position, ascii)
        }
    }

    /// Check if a word satisfies all constraints.
    @inline(__always)
    func matches(_ word: Word) -> Bool {
        // Fast bitmask rejections first
        let mask = word.letterMask

        // Reject if word contains any excluded letter
        if (mask & excludedMask) != 0 { return false }

        // Reject if word is missing any required letter
        if (mask & requiredMask) != requiredMask { return false }

        // Check each green constraint
        for (position, ascii) in placedConstraints {
            if word[position] != ascii { return false }
        }

        return true
    }

    private static func buildMask<S: Sequence>(from chars: S) -> UInt32 where S.Element == Character {
        var mask: UInt32 = 0
        for char in chars {
            if let bit = Word.bit(for: char) {
                mask |= bit
            }
        }
        return mask
    }
}
