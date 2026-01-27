import Foundation

/// A Wordle word stored in CPU-friendly form for fast queries.
public struct Word: WordleWord {
    public typealias Position = Int

    public let raw: String

    /// Lowercase ASCII bytes (always length 5 for Wordle).
    @usableFromInline let bytes: (UInt8, UInt8, UInt8, UInt8, UInt8)

    /// 26-bit mask: bit i is set if word contains letter ('a' + i).
    public let letterMask: UInt32

    /// Failable initializer—returns nil if not exactly 5 lowercase a–z.
    public init?(_ word: String) {
        let utf8 = Array(word.utf8)
        guard utf8.count == 5 else { return nil }

        var mask: UInt32 = 0
        for byte in utf8 {
            guard byte >= ASCII.lowerA, byte <= ASCII.lowerZ else { return nil }
            mask |= 1 << (byte - ASCII.lowerA)
        }

        self.raw = word
        self.bytes = (utf8[0], utf8[1], utf8[2], utf8[3], utf8[4])
        self.letterMask = mask
    }

    // MARK: - WordleWord Conformance

    public func contains(_ letter: Character) -> Bool {
        guard let bit = Self.bit(for: letter) else { return false }
        return (letterMask & bit) != 0
    }

    public func containsLetter(letter: Character, atPosition position: Position) -> Bool {
        guard let ascii = Self.asciiValue(for: letter),
              position >= 0, position <= 4 else { return false }
        return self[position] == ascii
    }

    // MARK: - Fast-Path Helpers (Public for Composable Filters)

    /// Direct byte access by position (0–4). No bounds checking.
    @inlinable
    public subscript(position: Int) -> UInt8 {
        switch position {
        case 0: return bytes.0
        case 1: return bytes.1
        case 2: return bytes.2
        case 3: return bytes.3
        case 4: return bytes.4
        default: fatalError("Position out of range: \(position)")
        }
    }

    /// Convert a Character to its bit position in the mask.
    @inlinable
    public static func bit(for char: Character) -> UInt32? {
        guard let ascii = asciiValue(for: char) else { return nil }
        return 1 << (ascii - ASCII.lowerA)
    }

    /// Convert a Character to its lowercase ASCII value.
    @inlinable
    public static func asciiValue(for char: Character) -> UInt8? {
        guard let scalar = char.unicodeScalars.first,
              scalar.isASCII else { return nil }
        let value = UInt8(scalar.value)
        // Handle uppercase by converting to lowercase
        let lower = (value >= 65 && value <= 90) ? value + 32 : value
        guard lower >= ASCII.lowerA, lower <= ASCII.lowerZ else { return nil }
        return lower
    }
}
