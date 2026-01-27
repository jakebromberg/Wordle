import ArgumentParser
import Foundation
import WordleLib

@main
struct Wordle: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wordle",
        abstract: "A high-performance Wordle solver.",
        subcommands: [Solve.self, Benchmark.self],
        defaultSubcommand: Solve.self
    )
}

// MARK: - Solve Command

struct Solve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Find words matching the given constraints."
    )

    @Option(name: [.short, .customLong("excluded")], help: "Gray letters not in the word (e.g., \"qxz\").")
    var excluded: String = ""

    @Option(name: [.short, .customLong("green")], help: "Green letters at positions (e.g., \"0:s,4:e\").")
    var green: String = ""

    @Option(name: [.short, .customLong("yellow")], help: "Yellow letters in wrong positions (e.g., \"ae\").")
    var yellow: String = ""

    @Option(name: [.short, .customLong("solver")], help: "Solver implementation to use.")
    var solver: SolverType = .adaptive

    @Flag(name: .shortAndLong, help: "Show detailed timing information.")
    var verbose: Bool = false

    func run() async throws {
        let wordStrings = try WordList.loadBundled()
        let words = wordStrings.compactMap(Word.init)

        let excludedSet = Set(excluded)
        let greenDict = parseGreen(green)
        let yellowSet = Set(yellow)

        if verbose {
            print("Loaded \(words.count) words")
            print("Constraints:")
            print("  Excluded: \(String(excludedSet.sorted()))")
            print("  Green: \(greenDict.sorted(by: { $0.key < $1.key }).map { "\($0.key):\($0.value)" }.joined(separator: ", "))")
            print("  Yellow: \(String(yellowSet.sorted()))")
            print("  Solver: \(solver.rawValue)")
            print()
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let results: [Word]

        switch solver {
        case .original:
            let solver = OriginalWordleSolver(words: words)
            results = await solver.getSolutions(
                excludedChars: excludedSet,
                correctlyPlacedChars: greenDict,
                correctLettersInWrongPlaces: yellowSet
            )
        case .bitmask:
            let solver = BitmaskWordleSolver(words: words)
            results = await solver.getSolutions(
                excludedChars: excludedSet,
                correctlyPlacedChars: greenDict,
                correctLettersInWrongPlaces: yellowSet
            )
        case .position:
            let solver = PositionAwareWordleSolver(words: words)
            results = solver.solve(excluded: excludedSet, green: greenDict, yellow: yellowSet)
        case .adaptive:
            let solver = AdaptiveWordleSolver(words: words)
            results = await solver.solve(excluded: excludedSet, green: greenDict, yellow: yellowSet)
        case .composable:
            let solver = ComposableWordleSolver(words: words)
            results = solver.solve(excluded: excludedSet, green: greenDict, yellow: yellowSet)
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        if verbose {
            print("Found \(results.count) possible words in \(String(format: "%.4f", elapsed * 1000))ms:")
        }

        for word in results.prefix(20) {
            print(word.raw)
        }
        if results.count > 20 {
            print("... and \(results.count - 20) more")
        }
    }

    private func parseGreen(_ input: String) -> [Int: Character] {
        guard !input.isEmpty else { return [:] }
        var result: [Int: Character] = [:]
        for pair in input.split(separator: ",") {
            let parts = pair.split(separator: ":")
            if parts.count == 2,
               let pos = Int(parts[0]),
               let char = parts[1].first {
                result[pos] = char
            }
        }
        return result
    }
}

enum SolverType: String, ExpressibleByArgument, CaseIterable {
    case adaptive
    case bitmask
    case position
    case original
    case composable

    static var allValueStrings: [String] {
        allCases.map(\.rawValue)
    }
}

// MARK: - Benchmark Command

struct Benchmark: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run performance benchmarks across all solvers."
    )

    @Option(name: [.short, .customLong("iterations")], help: "Number of iterations per benchmark.")
    var iterations: Int = 50

    @Flag(name: .shortAndLong, help: "Show only summary table.")
    var summary: Bool = false

    func run() async throws {
        let wordStrings = try WordList.loadBundled()
        let words = wordStrings.compactMap(Word.init)

        print("Wordle Solver Performance Benchmark")
        print("====================================")
        print("Word count: \(words.count)")
        print("Iterations: \(iterations)")
        print()

        let scenarios: [(name: String, excluded: Set<Character>, green: [Int: Character], yellow: Set<Character>)] = [
            ("No constraints", [], [:], []),
            ("Excluded only", Set("qxzjv"), [:], []),
            ("Green only", [], [0: "s", 4: "e"], []),
            ("Yellow only", [], [:], Set("aei")),
            ("Mixed constraints", Set("qxz"), [0: "s"], Set("a")),
            ("Heavy constraints", Set("qxzjvwkfbp"), [0: "s", 2: "a", 4: "e"], Set("r")),
        ]

        let originalSolver = OriginalWordleSolver(words: words)
        let bitmaskSolver = BitmaskWordleSolver(words: words)
        let positionSolver = PositionAwareWordleSolver(words: words)
        let adaptiveSolver = AdaptiveWordleSolver(words: words)
        let composableSolver = ComposableWordleSolver(words: words)

        // Pre-computed static filters using compile-time macros
        let staticFilters: [String: StaticWordleFilter] = [
            "No constraints": StaticWordleFilter(),
            "Excluded only": StaticWordleFilter(
                excludedMask: #letterMask("qxzjv")
            ),
            "Green only": StaticWordleFilter(
                requiredMask: #letterMask("se"),
                green: [(0, #ascii("s")), (4, #ascii("e"))]
            ),
            "Yellow only": StaticWordleFilter(
                requiredMask: #letterMask("aei")
            ),
            "Mixed constraints": StaticWordleFilter(
                excludedMask: #letterMask("qxz"),
                requiredMask: #letterMask("sa"),
                green: [(0, #ascii("s"))]
            ),
            "Heavy constraints": StaticWordleFilter(
                excludedMask: #letterMask("qxzjvwkfbp"),
                requiredMask: #letterMask("saer"),
                green: [(0, #ascii("s")), (2, #ascii("a")), (4, #ascii("e"))]
            ),
        ]

        for scenario in scenarios {
            print("Scenario: \(scenario.name)")
            print("-" + String(repeating: "-", count: scenario.name.count))

            // Warm up
            _ = await originalSolver.getSolutions(
                excludedChars: scenario.excluded,
                correctlyPlacedChars: scenario.green,
                correctLettersInWrongPlaces: scenario.yellow
            )

            let solvers: [(String, () async -> Int)] = [
                ("Original", {
                    let results = await originalSolver.getSolutions(
                        excludedChars: scenario.excluded,
                        correctlyPlacedChars: scenario.green,
                        correctLettersInWrongPlaces: scenario.yellow
                    )
                    return results.count
                }),
                ("Bitmask", {
                    let results = bitmaskSolver.solve(
                        excluded: scenario.excluded,
                        green: scenario.green,
                        yellow: scenario.yellow
                    )
                    return results.count
                }),
                ("Bitmask (TaskGroup)", {
                    let results = await bitmaskSolver.solveAsync(
                        excluded: scenario.excluded,
                        green: scenario.green,
                        yellow: scenario.yellow
                    )
                    return results.count
                }),
                ("PositionAware", {
                    let results = positionSolver.solve(
                        excluded: scenario.excluded,
                        green: scenario.green,
                        yellow: scenario.yellow
                    )
                    return results.count
                }),
                ("PositionAware (GCD)", {
                    let results = positionSolver.solveParallel(
                        excluded: scenario.excluded,
                        green: scenario.green,
                        yellow: scenario.yellow
                    )
                    return results.count
                }),
                ("PositionAware (Task)", {
                    let results = await positionSolver.solveAsync(
                        excluded: scenario.excluded,
                        green: scenario.green,
                        yellow: scenario.yellow
                    )
                    return results.count
                }),
                ("Adaptive", {
                    let results = await adaptiveSolver.solve(
                        excluded: scenario.excluded,
                        green: scenario.green,
                        yellow: scenario.yellow
                    )
                    return results.count
                }),
                ("Composable", {
                    let results = composableSolver.solve(
                        excluded: scenario.excluded,
                        green: scenario.green,
                        yellow: scenario.yellow
                    )
                    return results.count
                }),
                ("Composable (Async)", {
                    let results = await composableSolver.solveAsync(
                        excluded: scenario.excluded,
                        green: scenario.green,
                        yellow: scenario.yellow
                    )
                    return results.count
                }),
                ("Custom Filter", {
                    let filter = WordleFilter(
                        excluded: scenario.excluded,
                        green: scenario.green,
                        yellow: scenario.yellow
                    )
                    let results = composableSolver.solve(filter: filter)
                    return results.count
                }),
            ]

            let staticFilter = staticFilters[scenario.name]!
            let allSolvers = solvers + [
                ("Static (Macro)", {
                    let results = composableSolver.solve(filter: staticFilter)
                    return results.count
                })
            ]

            for (name, run) in allSolvers {
                var times: [Double] = []
                var resultCount = 0

                for _ in 0..<iterations {
                    let start = CFAbsoluteTimeGetCurrent()
                    resultCount = await run()
                    let elapsed = CFAbsoluteTimeGetCurrent() - start
                    times.append(elapsed * 1_000_000)
                }

                let avg = times.reduce(0, +) / Double(times.count)
                let sorted = times.sorted()
                let median = sorted[sorted.count / 2]
                let min = sorted.first!
                let max = sorted.last!

                print("  \(name.padding(toLength: 22, withPad: " ", startingAt: 0)) "
                    + "avg: \(String(format: "%8.2f", avg))µs  "
                    + "med: \(String(format: "%8.2f", median))µs  "
                    + "min: \(String(format: "%8.2f", min))µs  "
                    + "max: \(String(format: "%8.2f", max))µs  "
                    + "results: \(resultCount)")
            }
            print()
        }
    }
}
