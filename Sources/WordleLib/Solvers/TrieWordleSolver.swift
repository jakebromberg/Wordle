import Foundation

/// Solver using a trie (prefix tree) with aggregated bitmasks for pruning.
///
/// Strategy: Store words in a trie structure where each node contains:
/// - Children for each letter
/// - Aggregated letterMask for all words in subtree (enables early pruning)
/// - Word indices at leaf level
///
/// Pruning: If a subtree's aggregated mask shows it contains an excluded letter,
/// or doesn't contain all required letters, skip the entire subtree.
public final class TrieWordleSolver: @unchecked Sendable {

    /// Trie node with aggregated masks for pruning
    private final class TrieNode {
        /// Children indexed by letter (0-25 for a-z)
        var children: [TrieNode?] = Array(repeating: nil, count: 26)

        /// Aggregated letterMask of ALL words in this subtree
        /// Enables pruning: if (subtreeMask & excludedMask) != 0, skip subtree
        var subtreeMask: UInt32 = 0

        /// Word indices stored at this node (for complete words)
        var wordIndices: [Int] = []

        /// Count of words in this subtree (for capacity hints)
        var subtreeCount: Int = 0
    }

    /// Root of the trie
    private let root: TrieNode

    /// Original words for output
    public let allWordleWords: [Word]

    /// Packed words for fast green checking
    private let packedWords: [UInt64]

    // MARK: - Initialization

    public init(words: [Word]) {
        self.allWordleWords = words
        self.root = TrieNode()

        // Build packed words array
        var packed: [UInt64] = []
        packed.reserveCapacity(words.count)
        for word in words {
            packed.append(Self.pack(word))
        }
        self.packedWords = packed

        // Insert all words into trie
        for (index, word) in words.enumerated() {
            insert(word: word, index: index)
        }

        // Propagate subtree masks up the trie
        propagateMasks(node: root)
    }

    public convenience init(words: [String]) {
        let wordObjects = words.compactMap(Word.init)
        self.init(words: wordObjects)
    }

    // MARK: - Trie Construction

    private func insert(word: Word, index: Int) {
        var node = root

        for pos in 0..<5 {
            let letterIndex = Int(word[pos] - 97)
            guard letterIndex >= 0 && letterIndex < 26 else { return }

            if node.children[letterIndex] == nil {
                node.children[letterIndex] = TrieNode()
            }
            node = node.children[letterIndex]!
        }

        // Store word index at leaf
        node.wordIndices.append(index)
    }

    private func propagateMasks(node: TrieNode) {
        var mask: UInt32 = 0
        var count = node.wordIndices.count

        // Aggregate masks from words at this node
        for index in node.wordIndices {
            mask |= allWordleWords[index].letterMask
        }

        // Recursively propagate from children
        for child in node.children {
            if let child = child {
                propagateMasks(node: child)
                mask |= child.subtreeMask
                count += child.subtreeCount
            }
        }

        node.subtreeMask = mask
        node.subtreeCount = count
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

        // Build green constraints array (letter at each position, or -1 if not specified)
        var greenLetters: [Int] = Array(repeating: -1, count: 5)
        for (pos, char) in green {
            if let ascii = Word.asciiValue(for: char), pos >= 0 && pos < 5 {
                greenLetters[pos] = Int(ascii - 97)
            }
        }

        let yellowConstraints: [(UInt8, UInt8)] = yellow.compactMap { char, forbidden in
            guard let ascii = Word.asciiValue(for: char) else { return nil }
            return (ascii, forbidden)
        }

        var results: [Word] = []
        results.reserveCapacity(root.subtreeCount / 4)

        // Traverse trie with pruning
        traverseTrie(
            node: root,
            depth: 0,
            greenLetters: greenLetters,
            excludedMask: excludedMask,
            requiredMask: requiredMask,
            yellowConstraints: yellowConstraints,
            results: &results
        )

        return results
    }

    // MARK: - Trie Traversal

    private func traverseTrie(
        node: TrieNode,
        depth: Int,
        greenLetters: [Int],
        excludedMask: UInt32,
        requiredMask: UInt32,
        yellowConstraints: [(UInt8, UInt8)],
        results: inout [Word]
    ) {
        // Pruning check: if subtree can't possibly satisfy constraints, skip it
        // Note: We check if subtree COULD contain valid words
        // If subtree contains any excluded letter that's not in required, that's OK
        // because individual words might not have it

        // Check if subtree has all required letters
        if (node.subtreeMask & requiredMask) != requiredMask {
            return  // Subtree doesn't have all required letters
        }

        // At leaf level (depth 5), check words
        if depth == 5 {
            for index in node.wordIndices {
                let word = allWordleWords[index]

                // Final checks
                if (word.letterMask & excludedMask) != 0 { continue }
                if (word.letterMask & requiredMask) != requiredMask { continue }

                // Yellow position check
                let packed = packedWords[index]
                if !checkYellowPositions(packed: packed, yellow: yellowConstraints) { continue }

                results.append(word)
            }
            return
        }

        // Determine which children to explore
        let greenLetter = greenLetters[depth]

        if greenLetter >= 0 {
            // Only explore the child matching the green constraint
            if let child = node.children[greenLetter] {
                traverseTrie(
                    node: child,
                    depth: depth + 1,
                    greenLetters: greenLetters,
                    excludedMask: excludedMask,
                    requiredMask: requiredMask,
                    yellowConstraints: yellowConstraints,
                    results: &results
                )
            }
        } else {
            // Explore all non-excluded children
            for letterIndex in 0..<26 {
                // Skip if this letter is excluded (and not a required letter placed elsewhere)
                let letterBit: UInt32 = 1 << letterIndex
                if (excludedMask & letterBit) != 0 { continue }

                // Skip if yellow constraint forbids this letter at this position
                let ascii = UInt8(letterIndex + 97)
                var forbidden = false
                for (yellowAscii, yellowForbidden) in yellowConstraints {
                    if ascii == yellowAscii && (yellowForbidden & (1 << depth)) != 0 {
                        forbidden = true
                        break
                    }
                }
                if forbidden { continue }

                if let child = node.children[letterIndex] {
                    traverseTrie(
                        node: child,
                        depth: depth + 1,
                        greenLetters: greenLetters,
                        excludedMask: excludedMask,
                        requiredMask: requiredMask,
                        yellowConstraints: yellowConstraints,
                        results: &results
                    )
                }
            }
        }
    }

    // MARK: - Helpers

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
