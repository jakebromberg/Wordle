import Foundation

/// Solver interface. Multiple implementations available with different performance characteristics.
public protocol WordleSolver {
    associatedtype W: WordleWord

    /// The full candidate list the solver filters from.
    var allWordleWords: [W] { get }

    /// Filter candidates using:
    /// - excluded (gray) letters (unless overridden by placed letters)
    /// - correctly placed (green) letters
    /// - correct but unplaced (yellow) letters (presence-only in this API)
    func getSolutions(
        excludedChars: Set<Character>,
        correctlyPlacedChars: [W.Position: Character],
        correctLettersInWrongPlaces: Set<Character>
    ) async -> [W]
}
