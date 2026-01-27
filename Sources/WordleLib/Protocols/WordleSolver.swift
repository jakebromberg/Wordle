import Foundation

/// Solver interface. Multiple implementations available with different performance characteristics.
public protocol WordleSolver {
    associatedtype W: WordleWord

    /// The full candidate list the solver filters from.
    var allWordleWords: [W] { get }

    /// Filter candidates using Wordle constraints:
    /// - excluded: gray letters not in the word (unless overridden by green)
    /// - green: letters at correct positions
    /// - yellow: letters present but not at guessed positions
    func solve(
        excluded: Set<Character>,
        green: [W.Position: Character],
        yellow: Set<Character>
    ) async -> [W]
}
