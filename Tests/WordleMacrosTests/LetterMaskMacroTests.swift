import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(WordleMacros)
import WordleMacros

final class LetterMaskMacroTests: XCTestCase {

    let testMacros: [String: Macro.Type] = [
        "letterMask": LetterMaskMacro.self,
        "positionMask": PositionMaskMacro.self,
        "ascii": AsciiMacro.self
    ]

    // MARK: - #letterMask Tests

    func testLetterMaskSingleLetter() throws {
        assertMacroExpansion(
            #"#letterMask("a")"#,
            expandedSource: "1 as UInt32",
            macros: testMacros
        )
    }

    func testLetterMaskMultipleLetters() throws {
        // 'a' = bit 0 = 1
        // 'b' = bit 1 = 2
        // 'c' = bit 2 = 4
        // Total = 7
        assertMacroExpansion(
            #"#letterMask("abc")"#,
            expandedSource: "7 as UInt32",
            macros: testMacros
        )
    }

    func testLetterMaskXYZ() throws {
        // 'x' = bit 23 = 8388608
        // 'y' = bit 24 = 16777216
        // 'z' = bit 25 = 33554432
        // Total = 58720256
        assertMacroExpansion(
            #"#letterMask("xyz")"#,
            expandedSource: "58720256 as UInt32",
            macros: testMacros
        )
    }

    func testLetterMaskUppercaseConverted() throws {
        // Should handle uppercase by converting to lowercase
        assertMacroExpansion(
            #"#letterMask("ABC")"#,
            expandedSource: "7 as UInt32",
            macros: testMacros
        )
    }

    func testLetterMaskDuplicates() throws {
        // Duplicates should not change the result (bitmask)
        assertMacroExpansion(
            #"#letterMask("aaa")"#,
            expandedSource: "1 as UInt32",
            macros: testMacros
        )
    }

    func testLetterMaskEmpty() throws {
        assertMacroExpansion(
            #"#letterMask("")"#,
            expandedSource: "0 as UInt32",
            macros: testMacros
        )
    }

    // MARK: - #positionMask Tests

    func testPositionMaskSingle() throws {
        assertMacroExpansion(
            "#positionMask(0)",
            expandedSource: "0b00001 as UInt8",
            macros: testMacros
        )
    }

    func testPositionMaskMultiple() throws {
        assertMacroExpansion(
            "#positionMask(0, 2, 4)",
            expandedSource: "0b10101 as UInt8",
            macros: testMacros
        )
    }

    func testPositionMaskAll() throws {
        assertMacroExpansion(
            "#positionMask(0, 1, 2, 3, 4)",
            expandedSource: "0b11111 as UInt8",
            macros: testMacros
        )
    }

    // MARK: - #ascii Tests

    func testAsciiLowercaseA() throws {
        assertMacroExpansion(
            #"#ascii("a")"#,
            expandedSource: "97 as UInt8",
            macros: testMacros
        )
    }

    func testAsciiLowercaseZ() throws {
        assertMacroExpansion(
            #"#ascii("z")"#,
            expandedSource: "122 as UInt8",
            macros: testMacros
        )
    }

    func testAsciiUppercaseConverted() throws {
        assertMacroExpansion(
            #"#ascii("A")"#,
            expandedSource: "97 as UInt8",
            macros: testMacros
        )
    }
}
#endif
