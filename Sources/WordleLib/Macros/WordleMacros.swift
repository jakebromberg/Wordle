import Foundation

// MARK: - Macro Declarations

/// Computes a 26-bit letter bitmask at compile time.
///
/// Each bit represents whether a letter is present:
/// - Bit 0 = 'a', Bit 1 = 'b', ..., Bit 25 = 'z'
///
/// Usage:
/// ```swift
/// let mask = #letterMask("xyz")  // Expands to: 46137344 as UInt32
/// ```
///
/// This is equivalent to calling `ExcludedLetterFilter.buildMask(from: Set("xyz"))`
/// but computed at compile time with zero runtime overhead.
@freestanding(expression)
public macro letterMask(_ letters: String) -> UInt32 = #externalMacro(module: "WordleMacros", type: "LetterMaskMacro")

/// Computes a position bitmask at compile time.
///
/// Each bit represents a position (0-4):
/// - Bit 0 = position 0, Bit 1 = position 1, ..., Bit 4 = position 4
///
/// Usage:
/// ```swift
/// let mask = #positionMask(0, 2)  // Expands to: 0b00101 as UInt8
/// ```
///
/// This is useful for yellow letter position constraints.
@freestanding(expression)
public macro positionMask(_ positions: Int...) -> UInt8 = #externalMacro(module: "WordleMacros", type: "PositionMaskMacro")

/// Computes the ASCII value of a lowercase letter at compile time.
///
/// Usage:
/// ```swift
/// let ascii = #ascii("a")  // Expands to: 97 as UInt8
/// ```
@freestanding(expression)
public macro ascii(_ char: String) -> UInt8 = #externalMacro(module: "WordleMacros", type: "AsciiMacro")
