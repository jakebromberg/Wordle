import Foundation

/// A minimal protocol your `Word` type can conform to so solvers can query:
/// - whether a letter exists anywhere in the word
/// - whether a letter is at a specific position
///
/// For Wordle, `Position` is usually `Int` in 0...4, but you can use your own
/// `Word.LetterPosition` enum as long as it is `Hashable`.
public protocol WordleWord {
    associatedtype Position: Hashable

    /// Optional: Keep a string representation for debugging / UI.
    var raw: String { get }

    /// True if the word contains `letter` anywhere.
    func contains(_ letter: Character) -> Bool

    /// True if the word has `letter` at `position`.
    func containsLetter(letter: Character, atPosition position: Position) -> Bool
}
