import Foundation
import WordleLib

/// Wordle Solver CLI
/// Usage: wordle [command] [options]
///
/// Commands:
///   solve       - Solve with given constraints
///   benchmark   - Run performance benchmarks
///   help        - Show this help message

@main
struct WordleCLI {
    static func main() async {
        let args = CommandLine.arguments.dropFirst()

        guard let command = args.first else {
            printUsage()
            return
        }

        switch command {
        case "solve":
            await runSolve(Array(args.dropFirst()))
        case "benchmark":
            await runBenchmark(Array(args.dropFirst()))
        case "help", "--help", "-h":
            printUsage()
        default:
            print("Unknown command: \(command)")
            printUsage()
        }
    }

    static func printUsage() {
        print("""
        Wordle Solver CLI

        Usage: wordle <command> [options]

        Commands:
          solve       Solve with given constraints
          benchmark   Run performance benchmarks
          help        Show this help message

        Solve Options:
          --excluded, -e <letters>     Gray letters (e.g., "xyz")
          --green, -g <pos:letter>     Green letters (e.g., "0:a,2:c")
          --yellow, -y <letters>       Yellow letters (e.g., "bc")
          --solver, -s <name>          Solver to use:
                                         adaptive (default) - auto-selects fastest
                                         bitmask  - fastest, no yellow positions
                                         position - fast, with yellow positions
                                         original - reference implementation

        Examples:
          wordle solve -e "xyz" -g "0:s,4:e" -y "a"
          wordle benchmark
          wordle benchmark --iterations 100
        """)
    }

    // MARK: - Solve Command

    static func runSolve(_ args: [String]) async {
        var excluded = Set<Character>()
        var green: [Int: Character] = [:]
        var yellow = Set<Character>()
        var solverName = "adaptive"

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--excluded", "-e":
                if i + 1 < args.count {
                    excluded = Set(args[i + 1])
                    i += 1
                }
            case "--green", "-g":
                if i + 1 < args.count {
                    green = parseGreen(args[i + 1])
                    i += 1
                }
            case "--yellow", "-y":
                if i + 1 < args.count {
                    yellow = Set(args[i + 1])
                    i += 1
                }
            case "--solver", "-s":
                if i + 1 < args.count {
                    solverName = args[i + 1]
                    i += 1
                }
            default:
                break
            }
            i += 1
        }

        do {
            let wordStrings = try WordList.loadBundled()
            let words = wordStrings.compactMap(Word.init)

            print("Loaded \(words.count) words")
            print("Constraints:")
            print("  Excluded: \(String(excluded.sorted()))")
            print("  Green: \(green.sorted(by: { $0.key < $1.key }).map { "\($0.key):\($0.value)" }.joined(separator: ", "))")
            print("  Yellow: \(String(yellow.sorted()))")
            print("  Solver: \(solverName)")
            print()

            let startTime = CFAbsoluteTimeGetCurrent()
            let results: [Word]

            switch solverName {
            case "original":
                let solver = OriginalWordleSolver(words: words)
                results = await solver.getSolutions(
                    excludedChars: excluded,
                    correctlyPlacedChars: green,
                    correctLettersInWrongPlaces: yellow
                )
            case "bitmask":
                let solver = BitmaskWordleSolver(words: words)
                results = await solver.getSolutions(
                    excludedChars: excluded,
                    correctlyPlacedChars: green,
                    correctLettersInWrongPlaces: yellow
                )
            case "position":
                let solver = PositionAwareWordleSolver(words: words)
                results = solver.solve(excluded: excluded, green: green, yellow: yellow)
            case "adaptive":
                let solver = AdaptiveWordleSolver(words: words)
                results = await solver.solve(excluded: excluded, green: green, yellow: yellow)
            default:
                print("Unknown solver: \(solverName)")
                return
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            print("Found \(results.count) possible words in \(String(format: "%.4f", elapsed * 1000))ms:")
            for word in results.prefix(20) {
                print("  \(word.raw)")
            }
            if results.count > 20 {
                print("  ... and \(results.count - 20) more")
            }
        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }

    static func parseGreen(_ input: String) -> [Int: Character] {
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

    // MARK: - Benchmark Command

    static func runBenchmark(_ args: [String]) async {
        var iterations = 50

        var i = 0
        while i < args.count {
            if (args[i] == "--iterations" || args[i] == "-i") && i + 1 < args.count {
                iterations = Int(args[i + 1]) ?? iterations
                i += 1
            }
            i += 1
        }

        do {
            let wordStrings = try WordList.loadBundled()
            let words = wordStrings.compactMap(Word.init)

            print("Wordle Solver Performance Benchmark")
            print("====================================")
            print("Word count: \(words.count)")
            print("Iterations: \(iterations)")
            print()

            // Test scenarios
            let scenarios: [(name: String, excluded: Set<Character>, green: [Int: Character], yellow: Set<Character>)] = [
                ("No constraints", [], [:], []),
                ("Excluded only", Set("qxzjv"), [:], []),
                ("Green only", [], [0: "s", 4: "e"], []),
                ("Yellow only", [], [:], Set("aei")),
                ("Mixed constraints", Set("qxz"), [0: "s"], Set("a")),
                ("Heavy constraints", Set("qxzjvwkfbp"), [0: "s", 2: "a", 4: "e"], Set("r")),
            ]

            // Solvers to benchmark
            let originalSolver = OriginalWordleSolver(words: words)
            let bitmaskSolver = BitmaskWordleSolver(words: words)
            let positionSolver = PositionAwareWordleSolver(words: words)
            let adaptiveSolver = AdaptiveWordleSolver(words: words)
            let composableSolver = ComposableWordleSolver(words: words)

            // Pre-computed static filters using compile-time macros
            // These have ZERO runtime mask computation overhead
            let staticFilters: [String: StaticWordleFilter] = [
                // No constraints - pass all words
                "No constraints": StaticWordleFilter(),

                // Excluded only: "qxzjv"
                "Excluded only": StaticWordleFilter(
                    excludedMask: #letterMask("qxzjv")
                ),

                // Green only: [0: "s", 4: "e"]
                "Green only": StaticWordleFilter(
                    requiredMask: #letterMask("se"),
                    green: [(0, #ascii("s")), (4, #ascii("e"))]
                ),

                // Yellow only: "aei" (must contain, no position constraint)
                "Yellow only": StaticWordleFilter(
                    requiredMask: #letterMask("aei")
                ),

                // Mixed: excluded "qxz", green [0: "s"], yellow "a"
                "Mixed constraints": StaticWordleFilter(
                    excludedMask: #letterMask("qxz"),
                    requiredMask: #letterMask("sa"),
                    green: [(0, #ascii("s"))]
                ),

                // Heavy: excluded "qxzjvwkfbp", green [0:"s", 2:"a", 4:"e"], yellow "r"
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

                // Benchmark each solver
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

                // Add static filter benchmark for all scenarios
                // Filter is pre-computed at compile time via macros
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
                        times.append(elapsed * 1_000_000) // microseconds
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

        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }
}
