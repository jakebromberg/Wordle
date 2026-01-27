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

    @Flag(name: .long, help: "Output results as JSON to a file.")
    var json: Bool = false

    @Option(name: [.short, .customLong("output")], help: "Output file path for JSON (default: results.json).")
    var output: String = "results.json"

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
            results = await solver.solve(excluded: excludedSet, green: greenDict, yellow: yellowSet)
        case .bitmask:
            let solver = BitmaskWordleSolver(words: words)
            results = await solver.solve(excluded: excludedSet, green: greenDict, yellow: yellowSet)
        case .position:
            let solver = PositionAwareWordleSolver(words: words)
            results = await solver.solve(excluded: excludedSet, green: greenDict, yellow: yellowSet)
        case .adaptive:
            let solver = AdaptiveWordleSolver(words: words)
            // Convert Set<Character> to [Character: UInt8] with no position constraints
            let yellowDict = Dictionary(uniqueKeysWithValues: yellowSet.map { ($0, UInt8(0)) })
            results = await solver.solve(excluded: excludedSet, green: greenDict, yellow: yellowDict)
        case .composable:
            let solver = ComposableWordleSolver(words: words)
            results = await solver.solve(excluded: excludedSet, green: greenDict, yellow: yellowSet)
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        if verbose {
            print("Found \(results.count) possible words in \(String(format: "%.4f", elapsed * 1000))ms:")
        }

        if json {
            try exportJSON(results: results, to: output, elapsed: elapsed)
        } else {
            for word in results.prefix(20) {
                print(word.raw)
            }
            if results.count > 20 {
                print("... and \(results.count - 20) more")
            }
        }
    }

    private func exportJSON(results: [Word], to path: String, elapsed: Double) throws {
        let output = SolveOutput(
            count: results.count,
            elapsedMs: elapsed * 1000,
            constraints: ConstraintsOutput(
                excluded: excluded,
                green: green,
                yellow: yellow
            ),
            words: results.map(\.raw)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(output)

        let url = URL(fileURLWithPath: path)
        try data.write(to: url)
        print("Wrote \(results.count) results to \(path)")
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

// MARK: - JSON Output Types

private struct SolveOutput: Encodable {
    let count: Int
    let elapsedMs: Double
    let constraints: ConstraintsOutput
    let words: [String]
}

private struct ConstraintsOutput: Encodable {
    let excluded: String
    let green: String
    let yellow: String
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

    @Flag(name: .long, help: "Output results as JSON.")
    var json: Bool = false

    @Flag(name: .long, help: "Output results as CSV.")
    var csv: Bool = false

    @Option(name: [.short, .customLong("output")], help: "Output file path (default: benchmark.json or benchmark.csv).")
    var output: String?

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
        let parallelOriginalSolver = ParallelOriginalSolver(words: words)
        let bitmaskSolver = BitmaskWordleSolver(words: words)
        let simdSolver = SIMDWordleSolver(words: words)
        let adaptiveSolver = AdaptiveWordleSolver(words: words)
        let composableSolver = ComposableWordleSolver(words: words)
        let turboSolver = TurboWordleSolver(words: words)
        let simdTurboSolver = SIMDTurboSolver(words: words)

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

        var allResults: [BenchmarkResult] = []

        for scenario in scenarios {
            if !json && !csv {
                print("Scenario: \(scenario.name)")
                print("-" + String(repeating: "-", count: scenario.name.count))
            }

            // Warm up
            _ = await originalSolver.solve(
                excluded: scenario.excluded,
                green: scenario.green,
                yellow: scenario.yellow
            )

            let staticFilter = staticFilters[scenario.name]!

            let solvers: [(String, () async -> Int)] = [
                ("Original", {
                    let results = await originalSolver.solve(
                        excluded: scenario.excluded,
                        green: scenario.green,
                        yellow: scenario.yellow
                    )
                    return results.count
                }),
                ("Original (Parallel)", {
                    let results = await parallelOriginalSolver.solve(
                        excluded: scenario.excluded,
                        green: scenario.green,
                        yellow: scenario.yellow
                    )
                    return results.count
                }),
                ("Bitmask (Async)", {
                    let results = await bitmaskSolver.solve(
                        excluded: scenario.excluded,
                        green: scenario.green,
                        yellow: scenario.yellow
                    )
                    return results.count
                }),
                ("SIMD", {
                    let yellowDict = Dictionary(uniqueKeysWithValues: scenario.yellow.map { ($0, UInt8(0)) })
                    let results = simdSolver.solve(
                        excluded: scenario.excluded,
                        green: scenario.green,
                        yellow: yellowDict
                    )
                    return results.count
                }),
                ("Adaptive", {
                    let yellowDict = Dictionary(uniqueKeysWithValues: scenario.yellow.map { ($0, UInt8(0)) })
                    let results = await adaptiveSolver.solve(
                        excluded: scenario.excluded,
                        green: scenario.green,
                        yellow: yellowDict
                    )
                    return results.count
                }),
                ("Static (Macro)", {
                    let results = composableSolver.solve(filter: staticFilter)
                    return results.count
                }),
                ("Turbo (Indexed)", {
                    let yellowDict = Dictionary(uniqueKeysWithValues: scenario.yellow.map { ($0, UInt8(0)) })
                    let results = turboSolver.solve(
                        excluded: scenario.excluded,
                        green: scenario.green,
                        yellow: yellowDict
                    )
                    return results.count
                }),
                ("SIMD Turbo", {
                    let yellowDict = Dictionary(uniqueKeysWithValues: scenario.yellow.map { ($0, UInt8(0)) })
                    let results = simdTurboSolver.solve(
                        excluded: scenario.excluded,
                        green: scenario.green,
                        yellow: yellowDict
                    )
                    return results.count
                }),
            ]

            for (name, run) in solvers {
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
                let minTime = sorted.first!
                let maxTime = sorted.last!

                let result = BenchmarkResult(
                    scenario: scenario.name,
                    solver: name,
                    avgUs: avg,
                    medianUs: median,
                    minUs: minTime,
                    maxUs: maxTime,
                    resultCount: resultCount
                )
                allResults.append(result)

                if !json && !csv {
                    print("  \(name.padding(toLength: 24, withPad: " ", startingAt: 0)) "
                        + "avg: \(String(format: "%8.2f", avg))µs  "
                        + "med: \(String(format: "%8.2f", median))µs  "
                        + "min: \(String(format: "%8.2f", minTime))µs  "
                        + "max: \(String(format: "%8.2f", maxTime))µs  "
                        + "results: \(resultCount)")
                }
            }
            if !json && !csv {
                print()
            }
        }

        // Export results
        if json {
            try exportBenchmarkJSON(results: allResults, wordCount: words.count)
        } else if csv {
            try exportBenchmarkCSV(results: allResults, wordCount: words.count)
        }
    }

    private func exportBenchmarkJSON(results: [BenchmarkResult], wordCount: Int) throws {
        let output = BenchmarkOutput(
            wordCount: wordCount,
            iterations: iterations,
            results: results
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(output)

        let path = self.output ?? "benchmark.json"
        let url = URL(fileURLWithPath: path)
        try data.write(to: url)
        print("Wrote benchmark results to \(path)")
    }

    private func exportBenchmarkCSV(results: [BenchmarkResult], wordCount: Int) throws {
        var lines: [String] = []
        lines.append("scenario,solver,avg_us,median_us,min_us,max_us,result_count")

        for result in results {
            lines.append("\(result.scenario),\(result.solver),\(result.avgUs),\(result.medianUs),\(result.minUs),\(result.maxUs),\(result.resultCount)")
        }

        let csvContent = lines.joined(separator: "\n")
        let path = self.output ?? "benchmark.csv"
        let url = URL(fileURLWithPath: path)
        try csvContent.write(to: url, atomically: true, encoding: .utf8)
        print("Wrote benchmark results to \(path)")
    }
}

// MARK: - Benchmark Output Types

private struct BenchmarkResult: Encodable {
    let scenario: String
    let solver: String
    let avgUs: Double
    let medianUs: Double
    let minUs: Double
    let maxUs: Double
    let resultCount: Int
}

private struct BenchmarkOutput: Encodable {
    let wordCount: Int
    let iterations: Int
    let results: [BenchmarkResult]
}
