# Wordle Solver

A high-performance Wordle solver written in Swift, featuring multiple solver implementations with SIMD acceleration, first-letter indexing, and a composable filter architecture.

## Features

- **Ultra-fast queries**: 27-361µs for any constraint combination
- **Precomputed bitsets**: O(1) constraint intersection via bitwise AND operations
- **SIMD vectorization**: Process 8 words simultaneously with SIMD8<UInt32>
- **Multiple solver backends**: Bitset, Turbo, SIMD, and more for different use cases
- **Composable filters**: Build custom constraint pipelines with type-safe operators
- **Compile-time macros**: Zero-overhead filter construction

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

# Export results
swift run wordle solve -e "qxz" -g "0:s" --json -o results.json
swift run wordle benchmark --csv -o benchmark.csv
```

### Solve Options

| Option | Short | Description | Example |
|--------|-------|-------------|---------|
| `--excluded` | `-e` | Gray letters (not in word) | `-e "qxz"` |
| `--green` | `-g` | Green letters (correct position) | `-g "0:s,4:e"` |
| `--yellow` | `-y` | Yellow letters (wrong position) | `-y "ae"` |
| `--solver` | `-s` | Solver implementation | `-s bitset` |
| `--json` | | Output as JSON | `--json` |
| `--output` | `-o` | Output file path | `-o results.json` |

### Available Solvers

| Name | Description |
|------|-------------|
| `bitset` | Precomputed bitset intersection (default, fastest) |
| `turbo` | Packed words + first-letter indexing |
| `original` | Reference implementation, protocol-based |
| `bitmask` | Bitmask-based filtering |
| `position` | Full yellow position constraint support |
| `composable` | Composable filter architecture |

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

// Create solver (bitset is fastest)
let solver = BitsetWordleSolver(words: words)

// Query with constraints
let results = solver.solve(
    excluded: Set("qxz"),
    green: [0: "s", 4: "e"],
    yellow: ["a": 0b00110]  // 'a' not at positions 1 or 2
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

## Performance

### Optimization Techniques

The solvers use multiple advanced optimization techniques:

| Technique | Description | Benefit |
|-----------|-------------|---------|
| **Bitmask filtering** | 26-bit mask for O(1) letter presence checks | Fast exclusion/required checks |
| **SIMD vectorization** | SIMD8<UInt32> processes 8 words at once | 8x throughput for bitmask ops |
| **Packed words** | 5 letters in 40 bits of a UInt64 | Single-instruction green checks |
| **First-letter index** | Words bucketed by first letter | Search only ~1/26th when green[0] known |
| **Branch-free filtering** | Arithmetic instead of conditionals | No pipeline stalls |

### Benchmark Results

Median times in microseconds (8,506 words, 50 iterations):

| Solver | No constraints | Excluded only | Green only | Yellow only | Mixed | Heavy |
|--------|----------------|---------------|------------|-------------|-------|-------|
| Original | 1305 | 3381 | 1451 | 1558 | 2789 | 4031 |
| Bitmask | 221 | 230 | 332 | 134 | 313 | 80 |
| SIMD | 1438 | 1356 | 373 | 358 | 445 | 250 |
| Turbo | 804 | 636 | 30 | 91 | 88 | 15 |
| **Bitset** | **361** | **275** | **43** | **27** | **37** | **38** |

The **Bitset** solver delivers:
- **27-361µs** for any constraint combination
- **10-100x speedup** over the original implementation
- Fastest in nearly every scenario due to precomputed bitset intersection

### Why Bitset is Fastest

**BitsetWordleSolver** uses precomputed bitsets for O(1) constraint application:

- **Precomputed bitsets**: At init, builds bitsets for each letter (excluded, green, contains)
- **Bitwise intersection**: Query is just `result &= excludedBitset[letter]` for each constraint
- **No iteration**: Constraints applied via AND operations, not word-by-word checks
- **Memory tradeoff**: ~160KB of bitsets for 8,506 words enables O(constraint_count) queries

## Project Structure

```
Sources/
  WordleLib/
    Protocols/
      WordleWord.swift        # Word protocol
      WordleSolver.swift      # Solver protocol
    Models/
      ASCII.swift             # ASCII constants
      Word.swift              # Optimized word representation
    Solvers/
      BitsetWordleSolver.swift        # Default solver (precomputed bitsets)
      OriginalWordleSolver.swift      # Reference implementation
      BitmaskWordleSolver.swift       # Bitmask-based solver
      PositionAwareWordleSolver.swift # Yellow position tracking
      SIMDWordleSolver.swift          # SIMD-accelerated solver
      TurboWordleSolver.swift         # Packed words + first-letter indexing
      BigramWordleSolver.swift        # Two-letter indexing
      TrieWordleSolver.swift          # Trie with bitmask pruning
      ComposableWordleSolver.swift    # Composable filter architecture
    Filters/
      WordFilter.swift        # Filter protocol and basic filters
      CompositeFilters.swift  # AND/OR/NOT composition
    Executors/
      FilterExecutor.swift    # Sequential, GCD, TaskGroup executors
    Constraints/
      QueryConstraints.swift  # Constraint preprocessing
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

## Architecture

### Word Representation

Each word is stored in an optimized format:

```swift
public struct Word {
    let raw: String                              // Original string
    let bytes: (UInt8, UInt8, UInt8, UInt8, UInt8)  // ASCII bytes
    let letterMask: UInt32                       // 26-bit presence mask
}
```

The `letterMask` enables O(1) checks for letter containment:
- Bit 0 set = contains 'a'
- Bit 1 set = contains 'b'
- ...
- Bit 25 set = contains 'z'

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
| `WordleFilter` | Pre-composed filter for standard constraints |
| `StaticWordleFilter` | Macro-optimized with compile-time masks |
| `PassAllFilter` | Identity filter (accepts all words) |

### Composition Operators

```swift
let filter = filterA && filterB  // AND
let filter = filterA || filterB  // OR
let filter = !filterA            // NOT
```

## License

MIT
