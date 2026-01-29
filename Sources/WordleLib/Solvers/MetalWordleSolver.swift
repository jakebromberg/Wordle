import Foundation

#if canImport(Metal)
import Metal
import MetalKit

/// GPU-accelerated solver using Metal compute shaders.
///
/// Strategy: Process all words in parallel on the GPU.
/// Each GPU thread evaluates one word against constraints.
/// Results are collected using atomic operations.
///
/// Note: GPU is most beneficial for very large word lists or complex constraints.
/// For small lists (~8500 words), CPU may be faster due to kernel launch overhead.
public final class MetalWordleSolver: @unchecked Sendable {

    /// Metal device
    private let device: MTLDevice

    /// Command queue
    private let commandQueue: MTLCommandQueue

    /// Compute pipeline
    private let pipeline: MTLComputePipelineState

    /// Buffers
    private let packedWordsBuffer: MTLBuffer
    private let letterMasksBuffer: MTLBuffer
    private let resultIndicesBuffer: MTLBuffer
    private let resultCountBuffer: MTLBuffer
    private let constraintsBuffer: MTLBuffer

    /// Word count
    private let wordCount: Int

    /// Original words for output
    public let allWordleWords: [Word]

    /// Constraint structure matching shader layout
    private struct GPUConstraints {
        var excludedMask: UInt32
        var requiredMask: UInt32
        var greenMask: UInt64
        var greenValue: UInt64
        var yellowCount: UInt32
        var padding: UInt32  // Alignment padding
        var yellowBytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
        var yellowForbidden: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    }

    /// Metal shader source code
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Constraints {
        uint excludedMask;
        uint requiredMask;
        ulong greenMask;
        ulong greenValue;
        uint yellowCount;
        uint padding;
        uchar yellowBytes[8];
        uchar yellowForbidden[8];
    };

    kernel void filterWords(
        device const ulong* packedWords [[buffer(0)]],
        device const uint* letterMasks [[buffer(1)]],
        device atomic_uint* resultCount [[buffer(2)]],
        device ushort* resultIndices [[buffer(3)]],
        constant Constraints& constraints [[buffer(4)]],
        uint idx [[thread_position_in_grid]],
        uint gridSize [[threads_per_grid]]
    ) {
        // Bounds check
        if (idx >= gridSize) return;

        uint mask = letterMasks[idx];
        ulong packed = packedWords[idx];

        // Excluded check
        if ((mask & constraints.excludedMask) != 0) return;

        // Required check
        if ((mask & constraints.requiredMask) != constraints.requiredMask) return;

        // Green check
        if (constraints.greenMask != 0) {
            if ((packed & constraints.greenMask) != constraints.greenValue) return;
        }

        // Yellow position check
        for (uint j = 0; j < constraints.yellowCount; j++) {
            uchar ascii = constraints.yellowBytes[j];
            uchar forbidden = constraints.yellowForbidden[j];

            uchar byte0 = uchar(packed & 0xFF);
            uchar byte1 = uchar((packed >> 8) & 0xFF);
            uchar byte2 = uchar((packed >> 16) & 0xFF);
            uchar byte3 = uchar((packed >> 24) & 0xFF);
            uchar byte4 = uchar((packed >> 32) & 0xFF);

            if ((forbidden & 0x01) != 0 && byte0 == ascii) return;
            if ((forbidden & 0x02) != 0 && byte1 == ascii) return;
            if ((forbidden & 0x04) != 0 && byte2 == ascii) return;
            if ((forbidden & 0x08) != 0 && byte3 == ascii) return;
            if ((forbidden & 0x10) != 0 && byte4 == ascii) return;
        }

        // Word passed all checks - add to results
        uint slot = atomic_fetch_add_explicit(resultCount, 1, memory_order_relaxed);
        if (slot < 8506) {  // Bounds check for results buffer
            resultIndices[slot] = ushort(idx);
        }
    }
    """

    // MARK: - Initialization

    public init?(words: [Word]) {
        // Get Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return nil
        }
        self.device = device

        // Create command queue
        guard let commandQueue = device.makeCommandQueue() else {
            print("Failed to create command queue")
            return nil
        }
        self.commandQueue = commandQueue

        self.allWordleWords = words
        self.wordCount = words.count

        // Build packed word data
        var packedWords: [UInt64] = []
        var letterMasks: [UInt32] = []
        packedWords.reserveCapacity(words.count)
        letterMasks.reserveCapacity(words.count)

        for word in words {
            var packed: UInt64 = 0
            packed |= UInt64(word[0])
            packed |= UInt64(word[1]) << 8
            packed |= UInt64(word[2]) << 16
            packed |= UInt64(word[3]) << 24
            packed |= UInt64(word[4]) << 32
            packedWords.append(packed)
            letterMasks.append(word.letterMask)
        }

        // Create buffers
        guard let packedBuffer = device.makeBuffer(
            bytes: packedWords,
            length: packedWords.count * MemoryLayout<UInt64>.stride,
            options: .storageModeShared
        ) else {
            print("Failed to create packed words buffer")
            return nil
        }
        self.packedWordsBuffer = packedBuffer

        guard let masksBuffer = device.makeBuffer(
            bytes: letterMasks,
            length: letterMasks.count * MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        ) else {
            print("Failed to create letter masks buffer")
            return nil
        }
        self.letterMasksBuffer = masksBuffer

        // Result buffers
        guard let resultIdxBuffer = device.makeBuffer(
            length: words.count * MemoryLayout<UInt16>.stride,
            options: .storageModeShared
        ) else {
            print("Failed to create result indices buffer")
            return nil
        }
        self.resultIndicesBuffer = resultIdxBuffer

        guard let resultCntBuffer = device.makeBuffer(
            length: MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        ) else {
            print("Failed to create result count buffer")
            return nil
        }
        self.resultCountBuffer = resultCntBuffer

        guard let constBuffer = device.makeBuffer(
            length: MemoryLayout<GPUConstraints>.stride,
            options: .storageModeShared
        ) else {
            print("Failed to create constraints buffer")
            return nil
        }
        self.constraintsBuffer = constBuffer

        // Compile shader
        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            guard let function = library.makeFunction(name: "filterWords") else {
                print("Failed to find kernel function")
                return nil
            }
            self.pipeline = try device.makeComputePipelineState(function: function)
        } catch {
            print("Failed to create pipeline: \(error)")
            return nil
        }
    }

    public convenience init?(words: [String]) {
        let wordObjects = words.compactMap(Word.init)
        self.init(words: wordObjects)
    }

    // MARK: - Solve API

    public func solve(
        excluded: Set<Character>,
        green: [Int: Character],
        yellow: [Character: UInt8]
    ) -> [Word] {
        // Build constraints
        let placedLetters = Set(green.values)
        let effectiveExcluded = excluded.subtracting(placedLetters)
        let required = placedLetters.union(yellow.keys)

        var excludedMask: UInt32 = 0
        for char in effectiveExcluded {
            if let bit = Word.bit(for: char) {
                excludedMask |= bit
            }
        }

        var requiredMask: UInt32 = 0
        for char in required {
            if let bit = Word.bit(for: char) {
                requiredMask |= bit
            }
        }

        var greenMask: UInt64 = 0
        var greenValue: UInt64 = 0
        for (pos, char) in green {
            guard let ascii = Word.asciiValue(for: char), pos >= 0, pos < 5 else { continue }
            let shift = pos * 8
            greenMask |= 0xFF << shift
            greenValue |= UInt64(ascii) << shift
        }

        var yellowBytes: [UInt8] = []
        var yellowForbidden: [UInt8] = []
        for (char, forbidden) in yellow {
            if let ascii = Word.asciiValue(for: char) {
                yellowBytes.append(ascii)
                yellowForbidden.append(forbidden)
            }
        }

        // Pad to 8 elements
        while yellowBytes.count < 8 {
            yellowBytes.append(0)
            yellowForbidden.append(0)
        }

        // Create GPU constraints struct
        var constraints = GPUConstraints(
            excludedMask: excludedMask,
            requiredMask: requiredMask,
            greenMask: greenMask,
            greenValue: greenValue,
            yellowCount: UInt32(min(yellow.count, 8)),
            padding: 0,
            yellowBytes: (yellowBytes[0], yellowBytes[1], yellowBytes[2], yellowBytes[3],
                         yellowBytes[4], yellowBytes[5], yellowBytes[6], yellowBytes[7]),
            yellowForbidden: (yellowForbidden[0], yellowForbidden[1], yellowForbidden[2], yellowForbidden[3],
                             yellowForbidden[4], yellowForbidden[5], yellowForbidden[6], yellowForbidden[7])
        )

        // Copy constraints to buffer
        memcpy(constraintsBuffer.contents(), &constraints, MemoryLayout<GPUConstraints>.stride)

        // Reset result count
        let resultCountPtr = resultCountBuffer.contents().bindMemory(to: UInt32.self, capacity: 1)
        resultCountPtr.pointee = 0

        // Create command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return []
        }

        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(packedWordsBuffer, offset: 0, index: 0)
        encoder.setBuffer(letterMasksBuffer, offset: 0, index: 1)
        encoder.setBuffer(resultCountBuffer, offset: 0, index: 2)
        encoder.setBuffer(resultIndicesBuffer, offset: 0, index: 3)
        encoder.setBuffer(constraintsBuffer, offset: 0, index: 4)

        // Dispatch threads
        let threadGroupSize = min(pipeline.maxTotalThreadsPerThreadgroup, 256)

        encoder.dispatchThreads(
            MTLSize(width: wordCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: threadGroupSize, height: 1, depth: 1)
        )

        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Read results
        let resultCount = Int(resultCountPtr.pointee)
        let resultIndicesPtr = resultIndicesBuffer.contents().bindMemory(to: UInt16.self, capacity: wordCount)

        var results: [Word] = []
        results.reserveCapacity(resultCount)

        for i in 0..<resultCount {
            let wordIndex = Int(resultIndicesPtr[i])
            if wordIndex < allWordleWords.count {
                results.append(allWordleWords[wordIndex])
            }
        }

        return results
    }
}

#else

/// Fallback for platforms without Metal
public final class MetalWordleSolver: @unchecked Sendable {
    public let allWordleWords: [Word]

    public init?(words: [Word]) {
        print("Metal is not available on this platform")
        return nil
    }

    public convenience init?(words: [String]) {
        let wordObjects = words.compactMap(Word.init)
        self.init(words: wordObjects)
    }

    public func solve(
        excluded: Set<Character>,
        green: [Int: Character],
        yellow: [Character: UInt8]
    ) -> [Word] {
        return []
    }
}

#endif
