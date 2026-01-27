import Testing
@testable import WordleLib

@Suite("Solver Correctness Tests")
struct CorrectnessTests {
    let words: [Word]
    let wordStrings: [String]

    init() throws {
        wordStrings = try WordList.loadBundled()
        words = wordStrings.compactMap(Word.init)
    }

    // MARK: - Solver Consistency Tests

    struct TestScenario: CustomStringConvertible {
        let name: String
        let excluded: Set<Character>
        let green: [Int: Character]
        let yellow: Set<Character>

        var description: String { name }
    }

    static let scenarios: [TestScenario] = [
        TestScenario(name: "No constraints", excluded: [], green: [:], yellow: []),
        TestScenario(name: "Excluded only", excluded: Set("qxzjv"), green: [:], yellow: []),
        TestScenario(name: "Green only", excluded: [], green: [0: "s", 4: "e"], yellow: []),
        TestScenario(name: "Yellow only", excluded: [], green: [:], yellow: Set("aei")),
        TestScenario(name: "Mixed constraints", excluded: Set("qxz"), green: [0: "s"], yellow: Set("a")),
        TestScenario(name: "Heavy constraints", excluded: Set("qxzjvwkfbp"), green: [0: "s", 2: "a", 4: "e"], yellow: Set("r")),
    ]

    @Test("All solvers produce same results", arguments: scenarios)
    func allSolversProduceSameResults(scenario: TestScenario) async throws {
        let naive2Solver = OriginalWordleSolver(words: words)
        let opt2Solver = BitmaskWordleSolver(words: words)
        let ultraSolver = PositionAwareWordleSolver(words: words)

        let naive2Results = await naive2Solver.solve(
            excluded: scenario.excluded,
            green: scenario.green,
            yellow: scenario.yellow
        )

        let opt2Results = await opt2Solver.solve(
            excluded: scenario.excluded,
            green: scenario.green,
            yellow: scenario.yellow
        )

        let ultraResults = await ultraSolver.solve(
            excluded: scenario.excluded,
            green: scenario.green,
            yellow: scenario.yellow
        )

        let naive2Set = Set(naive2Results.map(\.raw))
        let opt2Set = Set(opt2Results.map(\.raw))
        let ultraSet = Set(ultraResults.map(\.raw))

        #expect(naive2Set == opt2Set, "OriginalWordleSolver != BitmaskWordleSolver")
        #expect(naive2Set == ultraSet, "OriginalWordleSolver != PositionAwareWordleSolver")
    }

    // MARK: - PositionAwareWordleSolver Specific Tests

    @Test("PositionAwareWordleSolver respects position bitmask")
    func ultraWordleSolverWithPositionBitmask() throws {
        let solver = PositionAwareWordleSolver(words: words)

        // Test with position bitmask: 'a' cannot be at positions 0 or 1 (bitmask 0b00011)
        let results = solver.solveSync(
            excluded: [],
            green: [:],
            yellowPositions: ["a": 0b00011]
        )

        for word in results {
            #expect(word.contains("a"), "\(word.raw) doesn't contain 'a'")
            #expect(!word.containsLetter(letter: "a", atPosition: 0), "\(word.raw) has 'a' at forbidden position 0")
            #expect(!word.containsLetter(letter: "a", atPosition: 1), "\(word.raw) has 'a' at forbidden position 1")
        }
    }

    @Test("PositionAwareWordleSolver position mask helper")
    func ultraWordleSolverPositionMaskHelper() {
        #expect(PositionAwareWordleSolver.positionMask([0]) == 0b00001)
        #expect(PositionAwareWordleSolver.positionMask([1]) == 0b00010)
        #expect(PositionAwareWordleSolver.positionMask([0, 2]) == 0b00101)
        #expect(PositionAwareWordleSolver.positionMask([0, 1, 2, 3, 4]) == 0b11111)
        #expect(PositionAwareWordleSolver.positionMask(2) == 0b00100)
    }

    // MARK: - Parallel Solver Correctness Tests

    @Test("Parallel solvers produce same results", arguments: scenarios)
    func parallelSolversProduceSameResults(scenario: TestScenario) async throws {
        let solver = PositionAwareWordleSolver(words: words)

        let sequentialResults = solver.solveSync(
            excluded: scenario.excluded,
            green: scenario.green,
            yellow: scenario.yellow
        )

        let gcdResults = solver.solveParallel(
            excluded: scenario.excluded,
            green: scenario.green,
            yellow: scenario.yellow
        )

        let taskGroupResults = await solver.solve(
            excluded: scenario.excluded,
            green: scenario.green,
            yellow: scenario.yellow
        )

        let sequentialSet = Set(sequentialResults.map(\.raw))
        let gcdSet = Set(gcdResults.map(\.raw))
        let taskGroupSet = Set(taskGroupResults.map(\.raw))

        #expect(sequentialSet == gcdSet, "Sequential != GCD Parallel")
        #expect(sequentialSet == taskGroupSet, "Sequential != TaskGroup")
    }

    @Test("Adaptive solver produces same results", arguments: scenarios)
    func adaptiveSolverProducesSameResults(scenario: TestScenario) async throws {
        let adaptiveSolver = AdaptiveWordleSolver(words: words)
        let referenceSolver = OriginalWordleSolver(words: words)

        let adaptiveResults = await adaptiveSolver.solve(
            excluded: scenario.excluded,
            green: scenario.green,
            yellow: scenario.yellow
        )

        let referenceResults = await referenceSolver.solve(
            excluded: scenario.excluded,
            green: scenario.green,
            yellow: scenario.yellow
        )

        let adaptiveSet = Set(adaptiveResults.map(\.raw))
        let referenceSet = Set(referenceResults.map(\.raw))

        #expect(adaptiveSet == referenceSet, "Adaptive != Reference")
    }

    @Test("Adaptive solver helper: forbiddenPositions")
    func adaptiveSolverForbiddenPositionsHelper() {
        #expect(AdaptiveWordleSolver.forbiddenPositions(0) == 0b00001)
        #expect(AdaptiveWordleSolver.forbiddenPositions(1, 2) == 0b00110)
        #expect(AdaptiveWordleSolver.forbiddenPositions(0, 4) == 0b10001)
    }

    @Test("Adaptive solver helper: yellowFromGuess")
    func adaptiveSolverYellowFromGuessHelper() {
        let yellow = AdaptiveWordleSolver.yellowFromGuess([("a", 2), ("e", 3)])
        #expect(yellow["a"] == 0b00100)
        #expect(yellow["e"] == 0b01000)

        // Test combining multiple positions for same letter
        let yellow2 = AdaptiveWordleSolver.yellowFromGuess([("a", 1), ("a", 3)])
        #expect(yellow2["a"] == 0b01010)
    }

    // MARK: - Word Tests

    @Test("Word.contains works correctly")
    func wordContains() throws {
        let word = try #require(Word("hello"))

        #expect(word.contains("h"))
        #expect(word.contains("e"))
        #expect(word.contains("l"))
        #expect(word.contains("o"))
        #expect(!word.contains("x"))
        #expect(!word.contains("z"))
    }

    @Test("Word.containsLetter at position works correctly")
    func wordContainsLetterAtPosition() throws {
        let word = try #require(Word("hello"))

        #expect(word.containsLetter(letter: "h", atPosition: 0))
        #expect(word.containsLetter(letter: "e", atPosition: 1))
        #expect(word.containsLetter(letter: "l", atPosition: 2))
        #expect(word.containsLetter(letter: "l", atPosition: 3))
        #expect(word.containsLetter(letter: "o", atPosition: 4))

        #expect(!word.containsLetter(letter: "h", atPosition: 1))
        #expect(!word.containsLetter(letter: "o", atPosition: 0))
    }

    @Test("Word init validation")
    func wordInitValidation() {
        #expect(Word("hello") != nil)
        #expect(Word("world") != nil)
        #expect(Word("abcde") != nil)

        #expect(Word("hi") == nil)          // Too short
        #expect(Word("toolong") == nil)     // Too long
        #expect(Word("HELLO") == nil)       // Uppercase
        #expect(Word("hel1o") == nil)       // Contains number
        #expect(Word("he!!o") == nil)       // Contains special char
    }

    // MARK: - Specific Constraint Tests

    @Test("Excluded letters are filtered out")
    func excludedLettersAreFiltered() throws {
        let solver = PositionAwareWordleSolver(words: words)
        let results = solver.solveSync(
            excluded: Set("aeiou"),
            green: [:],
            yellow: []
        )

        for word in results {
            #expect(!word.contains("a"), "\(word.raw) contains 'a'")
            #expect(!word.contains("e"), "\(word.raw) contains 'e'")
            #expect(!word.contains("i"), "\(word.raw) contains 'i'")
            #expect(!word.contains("o"), "\(word.raw) contains 'o'")
            #expect(!word.contains("u"), "\(word.raw) contains 'u'")
        }
    }

    @Test("Green letters at correct positions")
    func greenLettersAtCorrectPositions() throws {
        let solver = PositionAwareWordleSolver(words: words)
        let results = solver.solveSync(
            excluded: [],
            green: [0: "s", 4: "e"],
            yellow: []
        )

        for word in results {
            #expect(word.containsLetter(letter: "s", atPosition: 0), "\(word.raw) doesn't have 's' at position 0")
            #expect(word.containsLetter(letter: "e", atPosition: 4), "\(word.raw) doesn't have 'e' at position 4")
        }
    }

    @Test("Yellow letters are present")
    func yellowLettersArePresent() throws {
        let solver = PositionAwareWordleSolver(words: words)
        let results = solver.solveSync(
            excluded: [],
            green: [:],
            yellow: Set("xyz")
        )

        for word in results {
            #expect(word.contains("x"), "\(word.raw) doesn't contain 'x'")
            #expect(word.contains("y"), "\(word.raw) doesn't contain 'y'")
            #expect(word.contains("z"), "\(word.raw) doesn't contain 'z'")
        }
    }

    @Test("Yellow positions are forbidden")
    func yellowPositionsAreForbidden() throws {
        let solver = PositionAwareWordleSolver(words: words)
        // Positions 0 and 1 forbidden = bitmask 0b00011
        let results = solver.solveSync(
            excluded: [],
            green: [:],
            yellowPositions: ["a": 0b00011]
        )

        for word in results {
            #expect(word.contains("a"), "\(word.raw) doesn't contain 'a'")
            #expect(!word.containsLetter(letter: "a", atPosition: 0), "\(word.raw) has 'a' at forbidden position 0")
            #expect(!word.containsLetter(letter: "a", atPosition: 1), "\(word.raw) has 'a' at forbidden position 1")
        }
    }

    @Test("Green overrides excluded")
    func greenOverridesExcluded() throws {
        let solver = PositionAwareWordleSolver(words: words)

        // 's' is both excluded and green at position 0
        // Green should override, so words starting with 's' are allowed
        let results = solver.solveSync(
            excluded: Set("s"),
            green: [0: "s"],
            yellow: []
        )

        #expect(!results.isEmpty, "Should have results when green overrides excluded")
        for word in results {
            #expect(word.containsLetter(letter: "s", atPosition: 0))
        }
    }

    // MARK: - Composable Solver Tests

    @Test("Composable solver produces same results", arguments: scenarios)
    func composableSolverProducesSameResults(scenario: TestScenario) async throws {
        let composableSolver = ComposableWordleSolver(words: words)
        let referenceSolver = OriginalWordleSolver(words: words)

        let composableResults = await composableSolver.solve(
            excluded: scenario.excluded,
            green: scenario.green,
            yellow: scenario.yellow
        )

        let referenceResults = await referenceSolver.solve(
            excluded: scenario.excluded,
            green: scenario.green,
            yellow: scenario.yellow
        )

        let composableSet = Set(composableResults.map(\.raw))
        let referenceSet = Set(referenceResults.map(\.raw))

        #expect(composableSet == referenceSet, "Composable != Reference")
    }

    @Test("Custom filter composition works")
    func customFilterComposition() throws {
        // Build a custom filter using the composable architecture
        let filter = ExcludedLetterFilter(excluded: Set("xyz"))
            && RequiredLetterFilter(required: Set("ae"))
            && GreenLetterFilter(green: [0: "s"])

        let solver = ComposableWordleSolver(words: words)
        let results = solver.solve(filter: filter)

        // Verify all results match constraints
        for word in results {
            #expect(!word.contains("x"), "\(word.raw) contains 'x'")
            #expect(!word.contains("y"), "\(word.raw) contains 'y'")
            #expect(!word.contains("z"), "\(word.raw) contains 'z'")
            #expect(word.contains("a"), "\(word.raw) doesn't contain 'a'")
            #expect(word.contains("e"), "\(word.raw) doesn't contain 'e'")
            #expect(word.containsLetter(letter: "s", atPosition: 0), "\(word.raw) doesn't have 's' at position 0")
        }
    }

    @Test("WordleFilter pre-composed filter works")
    func wordleFilterPreComposed() throws {
        let filter = WordleFilter(
            excluded: Set("qxz"),
            green: [0: "s", 4: "e"],
            yellow: Set("a")
        )

        let solver = ComposableWordleSolver(words: words)
        let results = solver.solve(filter: filter)

        for word in results {
            #expect(!word.contains("q"), "\(word.raw) contains 'q'")
            #expect(!word.contains("x"), "\(word.raw) contains 'x'")
            #expect(!word.contains("z"), "\(word.raw) contains 'z'")
            #expect(word.containsLetter(letter: "s", atPosition: 0))
            #expect(word.containsLetter(letter: "e", atPosition: 4))
            #expect(word.contains("a"))
        }
    }

    // MARK: - Macro-based Filter Tests

    @Test("StaticWordleFilter with compile-time macros works")
    func staticWordleFilterWithMacros() throws {
        // All values computed at compile time via macros
        let filter = StaticWordleFilter(
            excludedMask: #letterMask("qxz"),
            requiredMask: #letterMask("ase"),
            green: [(0, #ascii("s")), (4, #ascii("e"))],
            yellow: [(#ascii("a"), #positionMask(0))]  // 'a' not at position 0
        )

        let solver = ComposableWordleSolver(words: words)
        let results = solver.solve(filter: filter)

        // Verify constraints
        for word in results {
            #expect(!word.contains("q"), "\(word.raw) contains 'q'")
            #expect(!word.contains("x"), "\(word.raw) contains 'x'")
            #expect(!word.contains("z"), "\(word.raw) contains 'z'")
            #expect(word.containsLetter(letter: "s", atPosition: 0))
            #expect(word.containsLetter(letter: "e", atPosition: 4))
            #expect(word.contains("a"))
            #expect(!word.containsLetter(letter: "a", atPosition: 0), "\(word.raw) has 'a' at position 0")
        }
    }

    @Test("StaticWordleFilter produces same results as WordleFilter")
    func staticWordleFilterMatchesWordleFilter() throws {
        // Runtime filter
        let runtimeFilter = WordleFilter(
            excluded: Set("qxz"),
            green: [0: "s", 4: "e"],
            yellowPositions: ["a": 0b00001]  // 'a' not at position 0
        )

        // Compile-time filter (equivalent)
        let staticFilter = StaticWordleFilter(
            excludedMask: #letterMask("qxz"),
            requiredMask: #letterMask("ase"),
            green: [(0, #ascii("s")), (4, #ascii("e"))],
            yellow: [(#ascii("a"), #positionMask(0))]
        )

        let solver = ComposableWordleSolver(words: words)
        let runtimeResults = Set(solver.solve(filter: runtimeFilter).map(\.raw))
        let staticResults = Set(solver.solve(filter: staticFilter).map(\.raw))

        #expect(runtimeResults == staticResults, "Static filter should produce same results as runtime filter")
    }
}
