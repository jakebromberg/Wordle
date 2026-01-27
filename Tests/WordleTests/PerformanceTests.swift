import XCTest
@testable import WordleLib

final class PerformanceTests: XCTestCase {
    var words: [Word]!
    var wordStrings: [String]!

    override func setUpWithError() throws {
        wordStrings = try WordList.loadBundled()
        words = wordStrings.compactMap(Word.init)
    }

    // MARK: - Test Scenarios

    struct TestScenario {
        let name: String
        let excluded: Set<Character>
        let green: [Int: Character]
        let yellow: Set<Character>
    }

    static let scenarios: [TestScenario] = [
        TestScenario(name: "No constraints", excluded: [], green: [:], yellow: []),
        TestScenario(name: "Excluded only", excluded: Set("qxzjv"), green: [:], yellow: []),
        TestScenario(name: "Green only", excluded: [], green: [0: "s", 4: "e"], yellow: []),
        TestScenario(name: "Yellow only", excluded: [], green: [:], yellow: Set("aei")),
        TestScenario(name: "Mixed constraints", excluded: Set("qxz"), green: [0: "s"], yellow: Set("a")),
        TestScenario(name: "Heavy constraints", excluded: Set("qxzjvwkfbp"), green: [0: "s", 2: "a", 4: "e"], yellow: Set("r")),
    ]

    // MARK: - OriginalWordleSolver Performance Tests

    func testOriginalWordleSolver_NoConstraints() async throws {
        let solver = OriginalWordleSolver(words: words)
        let scenario = Self.scenarios[0]

        measure {
            let exp = expectation(description: "solve")
            Task {
                _ = await solver.getSolutions(
                    excludedChars: scenario.excluded,
                    correctlyPlacedChars: scenario.green,
                    correctLettersInWrongPlaces: scenario.yellow
                )
                exp.fulfill()
            }
            wait(for: [exp], timeout: 10)
        }
    }

    func testOriginalWordleSolver_ExcludedOnly() async throws {
        let solver = OriginalWordleSolver(words: words)
        let scenario = Self.scenarios[1]

        measure {
            let exp = expectation(description: "solve")
            Task {
                _ = await solver.getSolutions(
                    excludedChars: scenario.excluded,
                    correctlyPlacedChars: scenario.green,
                    correctLettersInWrongPlaces: scenario.yellow
                )
                exp.fulfill()
            }
            wait(for: [exp], timeout: 10)
        }
    }

    func testOriginalWordleSolver_HeavyConstraints() async throws {
        let solver = OriginalWordleSolver(words: words)
        let scenario = Self.scenarios[5]

        measure {
            let exp = expectation(description: "solve")
            Task {
                _ = await solver.getSolutions(
                    excludedChars: scenario.excluded,
                    correctlyPlacedChars: scenario.green,
                    correctLettersInWrongPlaces: scenario.yellow
                )
                exp.fulfill()
            }
            wait(for: [exp], timeout: 10)
        }
    }

    // MARK: - BitmaskWordleSolver Performance Tests

    func testBitmaskWordleSolver_NoConstraints() async throws {
        let solver = BitmaskWordleSolver(words: words)
        let scenario = Self.scenarios[0]

        measure {
            let exp = expectation(description: "solve")
            Task {
                _ = await solver.getSolutions(
                    excludedChars: scenario.excluded,
                    correctlyPlacedChars: scenario.green,
                    correctLettersInWrongPlaces: scenario.yellow
                )
                exp.fulfill()
            }
            wait(for: [exp], timeout: 10)
        }
    }

    func testBitmaskWordleSolver_ExcludedOnly() async throws {
        let solver = BitmaskWordleSolver(words: words)
        let scenario = Self.scenarios[1]

        measure {
            let exp = expectation(description: "solve")
            Task {
                _ = await solver.getSolutions(
                    excludedChars: scenario.excluded,
                    correctlyPlacedChars: scenario.green,
                    correctLettersInWrongPlaces: scenario.yellow
                )
                exp.fulfill()
            }
            wait(for: [exp], timeout: 10)
        }
    }

    func testBitmaskWordleSolver_HeavyConstraints() async throws {
        let solver = BitmaskWordleSolver(words: words)
        let scenario = Self.scenarios[5]

        measure {
            let exp = expectation(description: "solve")
            Task {
                _ = await solver.getSolutions(
                    excludedChars: scenario.excluded,
                    correctlyPlacedChars: scenario.green,
                    correctLettersInWrongPlaces: scenario.yellow
                )
                exp.fulfill()
            }
            wait(for: [exp], timeout: 10)
        }
    }

    // MARK: - PositionAwareWordleSolver Performance Tests

    func testPositionAwareWordleSolver_NoConstraints() throws {
        let solver = PositionAwareWordleSolver(words: words)
        let scenario = Self.scenarios[0]

        measure {
            _ = solver.solve(
                excluded: scenario.excluded,
                green: scenario.green,
                yellow: scenario.yellow
            )
        }
    }

    func testPositionAwareWordleSolver_ExcludedOnly() throws {
        let solver = PositionAwareWordleSolver(words: words)
        let scenario = Self.scenarios[1]

        measure {
            _ = solver.solve(
                excluded: scenario.excluded,
                green: scenario.green,
                yellow: scenario.yellow
            )
        }
    }

    func testPositionAwareWordleSolver_HeavyConstraints() throws {
        let solver = PositionAwareWordleSolver(words: words)
        let scenario = Self.scenarios[5]

        measure {
            _ = solver.solve(
                excluded: scenario.excluded,
                green: scenario.green,
                yellow: scenario.yellow
            )
        }
    }

    func testPositionAwareWordleSolver_WithYellowPositions() throws {
        let solver = PositionAwareWordleSolver(words: words)

        measure {
            _ = solver.solve(
                excluded: Set("qxz"),
                green: [0: "s"],
                yellowPositions: ["a": 0b00110, "e": 0b01000]  // a not at 1,2; e not at 3
            )
        }
    }
}
