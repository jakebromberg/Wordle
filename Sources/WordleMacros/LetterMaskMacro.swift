import SwiftSyntax
import SwiftSyntaxMacros
import SwiftCompilerPlugin

/// Macro that computes a 26-bit letter bitmask at compile time.
/// Usage: `#letterMask("xyz")` expands to the UInt32 bitmask value.
public struct LetterMaskMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        // Get the string literal argument
        guard let argument = node.arguments.first?.expression,
              let stringLiteral = argument.as(StringLiteralExprSyntax.self),
              let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) else {
            throw MacroError.requiresStringLiteral
        }

        let letters = segment.content.text

        // Compute the bitmask at compile time
        var mask: UInt32 = 0
        for char in letters.lowercased() {
            guard let ascii = char.asciiValue, ascii >= 97, ascii <= 122 else {
                throw MacroError.invalidCharacter(char)
            }
            mask |= 1 << (ascii - 97)
        }

        // Return the literal value with explicit type
        return "\(raw: mask) as UInt32"
    }
}

/// Macro that computes a position bitmask at compile time.
/// Usage: `#positionMask(0, 2, 4)` expands to UInt8 bitmask (0b10101).
public struct PositionMaskMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        var mask: UInt8 = 0

        for argument in node.arguments {
            guard let intLiteral = argument.expression.as(IntegerLiteralExprSyntax.self),
                  let position = Int(intLiteral.literal.text),
                  position >= 0, position <= 4 else {
                throw MacroError.invalidPosition
            }
            mask |= 1 << position
        }

        // Return as binary literal for clarity
        let binary = String(mask, radix: 2)
        let padded = String(repeating: "0", count: 5 - binary.count) + binary
        return "0b\(raw: padded) as UInt8"
    }
}

/// Macro that computes ASCII value at compile time.
/// Usage: `#ascii("a")` expands to UInt8 value 97.
public struct AsciiMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        guard let argument = node.arguments.first?.expression,
              let stringLiteral = argument.as(StringLiteralExprSyntax.self),
              let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) else {
            throw MacroError.requiresStringLiteral
        }

        let text = segment.content.text
        guard text.count == 1, let char = text.first else {
            throw MacroError.requiresSingleCharacter
        }

        let lower = char.lowercased().first!
        guard let ascii = lower.asciiValue, ascii >= 97, ascii <= 122 else {
            throw MacroError.invalidCharacter(char)
        }

        return "\(raw: ascii) as UInt8"
    }
}

enum MacroError: Error, CustomStringConvertible {
    case requiresStringLiteral
    case requiresSingleCharacter
    case invalidCharacter(Character)
    case invalidPosition

    var description: String {
        switch self {
        case .requiresStringLiteral:
            return "#letterMask requires a string literal argument"
        case .requiresSingleCharacter:
            return "#ascii requires a single character"
        case .invalidCharacter(let char):
            return "Invalid character '\(char)': only lowercase a-z are allowed"
        case .invalidPosition:
            return "Position must be an integer literal 0-4"
        }
    }
}

@main
struct WordleMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        LetterMaskMacro.self,
        PositionMaskMacro.self,
        AsciiMacro.self
    ]
}
