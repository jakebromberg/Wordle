import Foundation

/// Original solver using only the `WordleWord` protocol methods.
/// Useful as a correctness baseline and for understanding the algorithm.
public final class OriginalWordleSolver<W: WordleWord>: WordleSolver where W.Position == Int {
    public let allWordleWords: [W]

    public init(words: [W]) {
        self.allWordleWords = words
    }

    public func getSolutions(
        excludedChars: Set<Character>,
        correctlyPlacedChars: [Int: Character],
        correctLettersInWrongPlaces: Set<Character>
    ) async -> [W] {
        // Letters that are placed (green) should not be excluded
        let placedLetters = Set(correctlyPlacedChars.values)
        let effectiveExcluded = excludedChars.subtracting(placedLetters)

        // All letters that must appear somewhere
        let requiredLetters = placedLetters.union(correctLettersInWrongPlaces)

        return allWordleWords.filter { word in
            // Check no excluded letters are present
            for char in effectiveExcluded {
                if word.contains(char) { return false }
            }

            // Check all required letters are present
            for char in requiredLetters {
                if !word.contains(char) { return false }
            }

            // Check green letters are at correct positions
            for (position, char) in correctlyPlacedChars {
                if !word.containsLetter(letter: char, atPosition: position) {
                    return false
                }
            }

            return true
        }
    }
}
