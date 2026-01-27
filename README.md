# Wordle Solver

A high-performance Wordle solver written in Swift, featuring multiple solver implementations with different performance characteristics and a composable filter architecture.

## Building

```bash
swift build -c release
```

## Running

### CLI Commands

```bash
# Show help
swift run wordle help

# Solve with constraints
swift run wordle solve -e "qxz" -g "0:s,4:e" -y "a"

# Run performance benchmarks
swift run wordle benchmark
swift run wordle benchmark --iterations 100
```

### Solve Options

| Option | Short | Description | Example |
|--------|-------|-------------|---------|
| `--excluded` | `-e` | Gray letters (not in word) | `-e "qxz"` |
| `--green` | `-g` | Green letters (correct position) | `-g "0:s,4:e"` |
| `--yellow` | `-y` | Yellow letters (wrong position) | `-y "ae"` |
| `--solver` | `-s` | Solver implementation | `-s adaptive` |

### Available Solvers

| Name | Description |
|------|-------------|
| `adaptive` | Auto-selects best strategy based on constraints (default) |
| `original` | Reference implementation, protocol-based |
| `bitmask` | Fast bitmask-based, no yellow position tracking |
| `position` | Fast with yellow position constraints |

## Testing

```bash
# Run all tests
swift test

# Run only performance tests
swift test --filter PerformanceTests

# Run only correctness tests
swift test --filter CorrectnessTests

# Run macro tests
swift test --filter WordleMacrosTests
```

## Library Usage

### Basic Usage

```swift
import WordleLib

// Load word list
let words = try WordList.loadBundled().compactMap(Word.init)

// Create solver (adaptive auto-selects best strategy)
let solver = AdaptiveWordleSolver(words: words)

// Query with constraints
let results = await solver.solve(
    excluded: Set("qxz"),
    green: [0: "s", 4: "e"],
    yellow: Set("a")
)
```

### Composable Filter Architecture

Build custom filters using composition:

```swift
let solver = ComposableWordleSolver(words: words)

// Using pre-composed WordleFilter
let results = solver.solve(
    excluded: Set("xyz"),
    green: [0: "s"],
    yellow: Set("ae")
)

// Using custom filter composition with operators
let filter = ExcludedLetterFilter(excluded: Set("xyz"))
    && RequiredLetterFilter(required: Set("ae"))
    && GreenLetterFilter(green: [0: "s"])

let results = solver.solve(filter: filter)

// Using result builder DSL
let results = solver.solve {
    ExcludedLetterFilter(excluded: Set("xyz"))
    RequiredLetterFilter(required: Set("ae"))
    GreenLetterFilter(green: [0: "s"])
}
```

### Compile-Time Macros

Use macros for zero-overhead filter construction:

```swift
// Compute bitmasks at compile time
let filter = StaticWordleFilter(
    excludedMask: #letterMask("qxzjv"),      // Computes UInt32 bitmask
    requiredMask: #letterMask("aer"),
    green: [(0, #ascii("s")), (4, #ascii("e"))],  // Computes ASCII values
    yellow: [(#ascii("a"), #positionMask(0, 1))]  // Position bitmask
)

let results = solver.solve(filter: filter)
```

### Custom Executors

Control execution strategy:

```swift
let solver = ComposableWordleSolver(words: words)
let filter = WordleFilter(excluded: Set("xyz"), green: [0: "s"], yellow: Set("a"))

// Sequential execution
let results = solver.solve(filter: filter, executor: SequentialExecutor())

// Parallel with GCD
let results = solver.solve(filter: filter, executor: GCDParallelExecutor())

// Parallel with TaskGroup (async)
let results = await solver.solveAsync(filter: filter)
```

## Project Structure

```
Sources/
  WordleLib/
    Protocols/
      WordleWord.swift        # Word protocol
      WordleSolver.swift      # Solver protocol
    Models/
      ASCII.swift             # ASCII constants
      Word.swift              # Optimized word representation (bitmask + bytes)
    Solvers/
      OriginalWordleSolver.swift      # Reference implementation
      BitmaskWordleSolver.swift       # Fast bitmask-based solver
      PositionAwareWordleSolver.swift # With yellow position tracking
      AdaptiveWordleSolver.swift      # Auto-selects best strategy
      ComposableWordleSolver.swift    # Composable filter architecture
    Filters/
      WordFilter.swift        # Filter protocol and basic filters
      CompositeFilters.swift  # AND/OR/NOT composition, WordleFilter
    Executors/
      FilterExecutor.swift    # Sequential, GCD, TaskGroup executors
    Constraints/
      QueryConstraints.swift  # Legacy constraint struct
    Macros/
      WordleMacros.swift      # Macro declarations
    WordList.swift            # Word list loader
    Resources/
      words5.txt              # 8,506 five-letter words
  WordleMacros/
    LetterMaskMacro.swift     # Macro implementations
  wordle/
    Wordle.swift              # CLI entry point
Tests/
  WordleTests/
    PerformanceTests.swift    # XCTest performance benchmarks
    CorrectnessTests.swift    # Swift Testing correctness validation
  WordleMacrosTests/
    LetterMaskMacroTests.swift # Macro expansion tests
```

## Performance

The optimized solvers use:
- **Bitmask operations**: 26-bit mask for O(1) letter presence checks
- **Precomputed constraints**: All masks computed once per query
- **Single-pass filtering**: Early exits and no intermediate arrays
- **Byte-level comparisons**: Direct ASCII byte comparison for positions
- **Compile-time macros**: Zero-overhead filter construction

### Benchmark Results

Median times in microseconds (8,506 words, 50 iterations):

| Solver | No constraints | Excluded only | Green only | Yellow only | Mixed | Heavy |
|--------|----------------|---------------|------------|-------------|-------|-------|
| Original | 1083 | 2927 | 1293 | 1224 | 2222 | 3763 |
| Bitmask (Async) | 300 | 210 | 329 | 69 | 231 | 91 |
| Adaptive | 295 | 232 | 293 | 67 | 180 | 87 |
| Static (Macro) | 1328 | 1150 | 339 | 85 | 250 | 92 |

The async solvers provide ~10-40x speedup over the reference implementation. The `Adaptive` solver is recommended for general use as it automatically selects the best strategy based on constraints.

## Architecture

### Filter Protocol

```swift
public protocol WordFilter: Sendable {
    func matches(_ word: Word) -> Bool
}
```

### Available Filters

| Filter | Purpose |
|--------|---------|
| `ExcludedLetterFilter` | Reject words containing excluded letters |
| `RequiredLetterFilter` | Require words to contain specific letters |
| `GreenLetterFilter` | Require letters at specific positions |
| `YellowPositionFilter` | Forbid letters at specific positions |
| `WordleFilter` | Pre-composed filter for standard Wordle constraints |
| `StaticWordleFilter` | Macro-optimized filter with compile-time masks |
| `PassAllFilter` | Identity filter (accepts all words) |

### Composition Operators

```swift
let filter = filterA && filterB  // AND
let filter = filterA || filterB  // OR
let filter = !filterA            // NOT
```
