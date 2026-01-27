import Foundation

/// Original solver using only the `WordleWord` protocol methods.
/// Useful as a correctness baseline and for understanding the algorithm.
public final class OriginalWordleSolver<W: WordleWord>: WordleSolver where W.Position == Int {
    public let allWordleWords: [W]

    public init(words: [W]) {
        self.allWordleWords = words
    }

    public func solve(
        excluded: Set<Character>,
        green: [Int: Character],
        yellow: Set<Character>
    ) async -> [W] {
        // Letters that are placed (green) should not be excluded
        let placedLetters = Set(green.values)
        let effectiveExcluded = excluded.subtracting(placedLetters)

        // All letters that must appear somewhere
        let requiredLetters = placedLetters.union(yellow)

        return allWordleWords.filter { word in
            matches(word: word, excluded: effectiveExcluded, required: requiredLetters, green: green)
        }
    }

    @inline(__always)
    private func matches(word: W, excluded: Set<Character>, required: Set<Character>, green: [Int: Character]) -> Bool {
        // Check no excluded letters are present
        for char in excluded {
            if word.contains(char) { return false }
        }

        // Check all required letters are present
        for char in required {
            if !word.contains(char) { return false }
        }

        // Check green letters are at correct positions
        for (position, char) in green {
            if !word.containsLetter(letter: char, atPosition: position) {
                return false
            }
        }

        return true
    }
}

/// Parallel version of the original solver using TaskGroup with strided access.
/// Each task processes every Nth word for better load balancing.
public final class ParallelOriginalSolver<W: WordleWord & Sendable>: WordleSolver where W.Position == Int {
    public let allWordleWords: [W]
    private let taskCount: Int

    public init(words: [W], taskCount: Int = 8) {
        self.allWordleWords = words
        self.taskCount = taskCount
    }

    public func solve(
        excluded: Set<Character>,
        green: [Int: Character],
        yellow: Set<Character>
    ) async -> [W] {
        // Letters that are placed (green) should not be excluded
        let placedLetters = Set(green.values)
        let effectiveExcluded = excluded.subtracting(placedLetters)

        // All letters that must appear somewhere
        let requiredLetters = placedLetters.union(yellow)

        let words = allWordleWords
        let count = words.count
        let stride = taskCount

        return await withTaskGroup(of: [W].self) { group in
            for taskIndex in 0..<taskCount {
                group.addTask {
                    var results: [W] = []
                    var index = taskIndex
                    while index < count {
                        let word = words[index]
                        if self.matches(word: word, excluded: effectiveExcluded, required: requiredLetters, green: green) {
                            results.append(word)
                        }
                        index += stride
                    }
                    return results
                }
            }

            var allResults: [W] = []
            for await taskResults in group {
                allResults.append(contentsOf: taskResults)
            }
            return allResults
        }
    }

    @inline(__always)
    private func matches(word: W, excluded: Set<Character>, required: Set<Character>, green: [Int: Character]) -> Bool {
        // Check no excluded letters are present
        for char in excluded {
            if word.contains(char) { return false }
        }

        // Check all required letters are present
        for char in required {
            if !word.contains(char) { return false }
        }

        // Check green letters are at correct positions
        for (position, char) in green {
            if !word.containsLetter(letter: char, atPosition: position) {
                return false
            }
        }

        return true
    }
}
