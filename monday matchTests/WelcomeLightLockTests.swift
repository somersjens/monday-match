import XCTest
import MetalKit
@testable import monday_match

@MainActor
final class WelcomeLightLockTests: XCTestCase {
    private let outlines: [(ring: Int, sheet: Int)] = [(0, 0), (0, 1), (1, 0), (1, 1)]

    func testLockOutlinesAreClosedAndContinuous() {
        for (ring, sheet) in outlines {
            let start = WelcomeLightLock.outline(u: 0, ring: ring, sheet: sheet)
            let end = WelcomeLightLock.outline(u: 1, ring: ring, sheet: sheet)
            XCTAssertEqual(start.x, end.x, accuracy: 1e-9)
            XCTAssertEqual(start.y, end.y, accuracy: 1e-9)
            var previous = start
            for step in 1...2048 {
                let point = WelcomeLightLock.outline(u: Double(step) / 2048, ring: ring, sheet: sheet)
                XCTAssertLessThan(hypot(point.x - previous.x, point.y - previous.y), 0.004,
                                  "Ring \(ring) sheet \(sheet) must not jump at u = \(Double(step) / 2048).")
                previous = point
            }
        }
    }

    func testLockFitsWhereTheHeartIsDrawn() {
        for ring in 0..<2 {
            for strand in stride(from: 0, to: WelcomeLightGeometry.strandCount, by: 7) {
                for step in 0..<256 {
                    let point = WelcomeLightLock.point(u: Double(step) / 256, ring: ring, strand: strand,
                                                       seconds: 4.2, pose: .init(amount: 1, lift: 0, shake: 0))
                    XCTAssertLessThan(abs(point.x), 0.82)
                    XCTAssertLessThan(abs(point.y), 1.0)
                }
            }
        }
        let bodyTop = WelcomeLightLock.bodyTop
        let bodyBottom = WelcomeLightLock.bodyCenter.y + WelcomeLightLock.bodyHalfSize.height
        // One silhouette runs from the shackle's crown down around the body,
        // so the shackle can never appear detached.
        let silhouette = (0..<512).map { WelcomeLightLock.silhouette(Double($0) / 512) }
        XCTAssertLessThan(WelcomeLightLock.silhouette(0).y, bodyTop - 0.5)
        XCTAssertEqual(silhouette.map(\.y).max() ?? 0, bodyBottom, accuracy: 1e-6)
        // The opening is enclosed by the shackle and closed by the body's top edge.
        for step in 0..<256 {
            let point = WelcomeLightLock.opening(Double(step) / 256)
            XCTAssertLessThanOrEqual(point.y, bodyTop + 1e-9)
            XCTAssertLessThanOrEqual(abs(point.x), WelcomeLightLock.shackleInnerRadius + 1e-9)
        }
        XCTAssertEqual(WelcomeLightLock.shackleWeight(y: bodyTop), 0, accuracy: 1e-9)
        XCTAssertEqual(WelcomeLightLock.shackleWeight(y: WelcomeLightLock.shackleCenter.y), 1, accuracy: 1e-9)
        for step in 0..<64 {
            let keyhole = WelcomeLightLock.keyhole(Double(step) / 64)
            XCTAssertLessThan(abs(keyhole.x), WelcomeLightLock.bodyHalfSize.width - WelcomeLightLock.bodyCornerRadius)
            XCTAssertGreaterThan(keyhole.y, bodyTop)
        }
    }

    func testShaderLockGeometryMatchesTheSwiftMirror() throws {
        try assertShaderMatchesSwift(pose: WelcomeLightLock.Pose(amount: 1, lift: 0.03, shake: -0.01)) { u, ring, strand, seconds, pose in
            WelcomeLightLock.point(u: u, ring: ring, strand: strand, seconds: seconds, pose: pose)
        }
    }

    func testShaderHelixGeometryMatchesTheSwiftMirror() throws {
        try assertShaderMatchesSwift(pose: WelcomeLightLock.Pose(amount: 1, lift: 0, shake: 0, isHelix: true)) { u, ring, strand, seconds, _ in
            WelcomeLightHelix.point(u: u, ring: ring, strand: strand, seconds: seconds).point
        }
    }

    func testHelixIsClosedFitsTheLightAndSpins() {
        for ring in 0..<2 {
            for strand in stride(from: 0, to: WelcomeLightGeometry.strandCount, by: 5) {
                let start = WelcomeLightHelix.point(u: 0, ring: ring, strand: strand, seconds: 3).point
                let end = WelcomeLightHelix.point(u: 1, ring: ring, strand: strand, seconds: 3).point
                XCTAssertEqual(start.x, end.x, accuracy: 1e-9)
                XCTAssertEqual(start.y, end.y, accuracy: 1e-9)
                var previous = start
                for step in 1...2048 {
                    let point = WelcomeLightHelix.point(u: Double(step) / 2048, ring: ring, strand: strand, seconds: 3).point
                    XCTAssertLessThan(abs(point.x), 0.82)
                    XCTAssertLessThan(abs(point.y), 1.2)
                    XCTAssertLessThan(hypot(point.x - previous.x, point.y - previous.y), 0.03,
                                      "Ring \(ring) strand \(strand) must not jump at u = \(Double(step) / 2048).")
                    previous = point
                }
            }
        }
        let now = WelcomeLightHelix.point(u: 0.2, ring: 0, strand: 3, seconds: 1)
        let later = WelcomeLightHelix.point(u: 0.2, ring: 0, strand: 3, seconds: 2)
        XCTAssertGreaterThan(hypot(now.point.x - later.point.x, now.point.y - later.point.y), 0.05, "The helix turns about its axis.")
    }

    func testHelixAppearsWholeAndUnweavesBack() {
        var motion = WelcomeLightLock.Motion()
        motion.update(form: .heart, pulse: 0, now: 0, animated: true)
        motion.update(form: .helix, pulse: 0, now: 10, animated: true)
        XCTAssertEqual(motion.pose(at: 10), .init(amount: 1, lift: 0, shake: 0, isHelix: true),
                       "The helix rises into view whole instead of growing out of the heart.")
        XCTAssertFalse(motion.isAnimating(at: 10))

        motion.update(form: .heart, pulse: 0, now: 20, animated: true)
        XCTAssertTrue(motion.pose(at: 20.5).isHelix, "Returning to the heart unweaves the helix.")
        XCTAssertEqual(motion.pose(at: 30), .unlocked)

        var completed = WelcomeLightLock.Motion()
        completed.update(form: .helix, pulse: 0, now: 0, animated: true)
        XCTAssertEqual(completed.pose(at: 0), .init(amount: 1, lift: 0, shake: 0, isHelix: true),
                       "A completed profile opens on the helix without a morph.")
    }

    func testShaderCodeGeometryMatchesTheSwiftMirror() throws {
        try assertShaderMatchesSwift(pose: .init(amount: 1, lift: 0, shake: 0, isHelix: true, code: 1),
                                     probe: "float2 local; output[id] = codePoint(u, instance, p, local).xy;") { u, ring, strand, seconds, _ in
            WelcomeLightCode.point(u: u, ring: ring, strand: strand, seconds: seconds).point
        }
    }

    func testCodeIsARealQRGridFilledWithEvenLines() throws {
        XCTAssertTrue(WelcomeLightCode.isAvailable)
        let size = WelcomeLightCode.size
        XCTAssertEqual(size, 21, "A short message fits a version 1 code.")
        // The three finder patterns: dark outer ring, light gap, dark centre.
        for (row, column) in [(0, 0), (0, size - 7), (size - 7, 0)] {
            XCTAssertEqual(WelcomeLightCode.modules[row * size + column], 1)
            XCTAssertEqual(WelcomeLightCode.modules[(row + 1) * size + column + 1], 0)
            XCTAssertEqual(WelcomeLightCode.modules[(row + 3) * size + column + 3], 1)
        }
        let timing = (8..<(size - 8)).map { WelcomeLightCode.modules[6 * size + $0] }
        XCTAssertEqual(timing, (8..<(size - 8)).map { $0 % 2 == 0 ? 1 : 0 }, "The timing pattern alternates.")

        // Every loop draws two lines across the whole grid, one line apart.
        let spacing = WelcomeLightCode.side / Double(WelcomeLightCode.lineCount)
        var rows = Set<Int>()
        for ring in 0..<2 {
            for strand in 0..<WelcomeLightGeometry.strandCount {
                let start = WelcomeLightCode.point(u: 0, ring: ring, strand: strand, seconds: 2).point
                let end = WelcomeLightCode.point(u: 1, ring: ring, strand: strand, seconds: 2).point
                XCTAssertEqual(start.x, end.x, accuracy: 1e-9)
                XCTAssertEqual(start.y, end.y, accuracy: 1e-9)
                for u in [0.25, 0.75] {
                    let local = WelcomeLightCode.point(u: u, ring: ring, strand: strand, seconds: 2).local
                    rows.insert(Int(((local.y + WelcomeLightCode.side / 2) / spacing).rounded(.down)))
                }
                let left = WelcomeLightCode.point(u: 0.5, ring: ring, strand: strand, seconds: 0).local
                XCTAssertGreaterThan(abs(left.x), WelcomeLightCode.side / 2, "The turns lie outside the grid.")
            }
        }
        XCTAssertEqual(rows, Set(0..<WelcomeLightCode.lineCount))
    }

    func testCodeMorphsSmoothlyAndOnlyFromTheHelix() {
        var motion = WelcomeLightLock.Motion()
        motion.update(form: .helix, pulse: 0, now: 0, animated: true)
        motion.update(showsCode: true, now: 10, animated: true)
        XCTAssertEqual(motion.pose(at: 10 + WelcomeLightCode.morphDuration / 2).code, 0.5, accuracy: 1e-9)
        XCTAssertTrue(motion.isAnimating(at: 10.5))
        XCTAssertEqual(motion.pose(at: 20).code, 1)
        motion.update(showsCode: false, now: 30, animated: true)
        XCTAssertEqual(motion.pose(at: 30.4).code, 1 - 0.4 / WelcomeLightCode.morphDuration, accuracy: 1e-9)
        XCTAssertEqual(motion.pose(at: 40).code, 0)

        XCTAssertEqual(WelcomeLightCode.strandAmount(1, u: 0.3, ring: 1, strand: 59), 1, "Every line arrives.")
        XCTAssertEqual(WelcomeLightCode.strandAmount(0, u: 0.3, ring: 0, strand: 0), 0)
        XCTAssertGreaterThan(WelcomeLightCode.strandAmount(0.5, u: 0.3, ring: 0, strand: 0),
                             WelcomeLightCode.strandAmount(0.5, u: 0.3, ring: 1, strand: 59), "Rows fill from the top.")

        var lock = WelcomeLightLock.Motion()
        lock.update(form: .lock, pulse: 0, now: 0, animated: true)
        lock.update(showsCode: true, now: 1, animated: true)
        XCTAssertEqual(lock.pose(at: 10).code, 0, "Only the helix becomes the code.")
    }

    func testRenderedCodeLightsOnlyItsModules() throws {
        let resources = try XCTUnwrap(WelcomeLightMetalRenderer.resources)
        let helix = try render(lock: .init(amount: 1, lift: 0, shake: 0, isHelix: true), resources: resources)
        let code = try render(lock: .init(amount: 1, lift: 0, shake: 0, isHelix: true, code: 1), resources: resources)
        let difference = zip(helix, code).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        XCTAssertGreaterThan(difference, 50_000, "The code replaces the helix.")
        // The centre of the top-left finder glows; its light ring stays dark.
        let scale = 256 * 0.42
        func brightness(row: Double, column: Double) -> Int {
            let n = Double(WelcomeLightCode.size)
            let x = Int(128 + ((column + 0.5) / n - 0.5) * WelcomeLightCode.side * scale)
            let y = Int(128 + ((row + 0.5) / n - 0.5) * WelcomeLightCode.side * scale)
            let index = (y * 256 + x) * 4
            return Int(code[index]) + Int(code[index + 1]) + Int(code[index + 2])
        }
        XCTAssertGreaterThan(brightness(row: 3, column: 3), brightness(row: 1, column: 3) + 40)
    }

    private func assertShaderMatchesSwift(
        pose: WelcomeLightLock.Pose,
        probe: String = "output[id] = (p.lock.w > 0.5 ? helixPoint(u, instance, p) : lockPoint(u, instance, p)).xy;",
        swiftPoint: (Double, Int, Int, Double, WelcomeLightLock.Pose) -> CGPoint
    ) throws {
        let resources = try XCTUnwrap(WelcomeLightMetalRenderer.resources)
        let source = WelcomeLightShaderSource.code + """
        kernel void lockProbe(uint id [[thread_position_in_grid]],
          constant WelcomeUniforms &p [[buffer(0)]], device float2 *output [[buffer(1)]]) {
            uint instance = (id / 64) * 7;
            float u = float(id % 64) / 64.0;
            \(probe)
        }
        """
        let library = try resources.device.makeLibrary(source: source, options: nil)
        let pipeline = try resources.device.makeComputePipelineState(
            function: try XCTUnwrap(library.makeFunction(name: "lockProbe")))
        let instances = (0..<(WelcomeLightGeometry.strandCount * 2)).filter { $0 % 7 == 0 }
        let count = instances.count * 64
        let output = try XCTUnwrap(resources.device.makeBuffer(
            length: count * MemoryLayout<SIMD2<Float>>.stride, options: .storageModeShared))
        var uniforms = WelcomeLightUniforms(elapsed: 1.3, size: CGSize(width: 256, height: 256), pixelScale: 1)
        uniforms.apply(pose)

        let command = try XCTUnwrap(resources.queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(command.makeComputeCommandEncoder())
        encoder.setComputePipelineState(pipeline)
        encoder.setBytes(&uniforms, length: MemoryLayout<WelcomeLightUniforms>.stride, index: 0)
        encoder.setBuffer(output, offset: 0, index: 1)
        encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1))
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        XCTAssertNil(command.error)

        let results = output.contents().bindMemory(to: SIMD2<Float>.self, capacity: count)
        for (row, instance) in instances.enumerated() {
            for sample in 0..<64 {
                let swift = swiftPoint(
                    Double(sample) / 64,
                    instance / WelcomeLightGeometry.strandCount,
                    instance % WelcomeLightGeometry.strandCount,
                    Double(uniforms.shape.w), pose)
                let metal = results[row * 64 + sample]
                XCTAssertEqual(Double(metal.x), swift.x, accuracy: 2e-3, "instance \(instance), sample \(sample)")
                XCTAssertEqual(Double(metal.y), swift.y, accuracy: 2e-3, "instance \(instance), sample \(sample)")
            }
        }
    }

    func testRenderedLockReplacesTheHeartAndZeroLeavesItUntouched() throws {
        let resources = try XCTUnwrap(WelcomeLightMetalRenderer.resources)
        let heart = try render(lock: .unlocked, resources: resources)
        let explicitZero = try render(lock: .init(amount: 0, lift: 0.05, shake: 0.02), resources: resources)
        let locked = try render(lock: .init(amount: 1, lift: 0, shake: 0), resources: resources)
        XCTAssertEqual(heart, explicitZero, "An unlocked pose must render the landing heart exactly.")
        let brightPixels = stride(from: 0, to: locked.count, by: 4).filter { locked[$0] > 80 }.count
        XCTAssertGreaterThan(brightPixels, 200, "The lock must be drawn by the same light.")
        let difference = zip(heart, locked).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        XCTAssertGreaterThan(difference, 20_000)
    }

    func testLockedLandingKeepsMoving() throws {
        let resources = try XCTUnwrap(WelcomeLightMetalRenderer.resources)
        let pose = WelcomeLightLock.Pose(amount: 1, lift: 0, shake: 0)
        let first = try render(lock: pose, elapsed: 0.5, resources: resources)
        let second = try render(lock: pose, elapsed: 1.5, resources: resources)
        let difference = zip(first, second).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        XCTAssertGreaterThan(difference, 2_000, "The lock should breathe and weave, not freeze.")
    }

    func testMotionAdoptsInitialStateAndThenMorphs() {
        var motion = WelcomeLightLock.Motion()
        motion.update(isLocked: true, pulse: 0, now: 100, animated: true)
        XCTAssertEqual(motion.progress(at: 100), 1, "A locked landing opens already locked.")
        XCTAssertFalse(motion.isAnimating(at: 100))

        motion.update(isLocked: false, pulse: 0, now: 200, animated: true)
        XCTAssertEqual(motion.progress(at: 200), 1, accuracy: 1e-9)
        XCTAssertEqual(motion.progress(at: 200 + WelcomeLightLock.morphDuration / 2), 0.5, accuracy: 1e-9)
        XCTAssertEqual(motion.progress(at: 200 + WelcomeLightLock.morphDuration), 0, accuracy: 1e-9)
        XCTAssertEqual(motion.pose(at: 300), .unlocked)

        motion.update(isLocked: true, pulse: 0, now: 400, animated: false)
        XCTAssertEqual(motion.progress(at: 400), 1, "Reduce Motion switches without a morph.")
    }

    func testPulseJigglesAndSettles() {
        var motion = WelcomeLightLock.Motion()
        motion.update(isLocked: true, pulse: 0, now: 0, animated: true)
        motion.update(isLocked: true, pulse: 1, now: 10, animated: true)
        let during = motion.pose(at: 10.08)
        XCTAssertNotEqual(during.lift, 0)
        XCTAssertNotEqual(during.shake, 0)
        XCTAssertEqual(motion.pose(at: 12), .init(amount: 1, lift: 0, shake: 0))
    }

    private func render(lock: WelcomeLightLock.Pose, elapsed: Double = 0.8, resources: WelcomeLightMetalResources) throws -> [UInt8] {
        let size = CGSize(width: 256, height: 256)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 256, height: 256, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead]
        let texture = try XCTUnwrap(resources.device.makeTexture(descriptor: descriptor))
        let emission = try XCTUnwrap(resources.emissionTexture(size: size))
        let target = MTLRenderPassDescriptor()
        target.colorAttachments[0].texture = texture
        target.colorAttachments[0].loadAction = .clear
        target.colorAttachments[0].storeAction = .store
        let command = try XCTUnwrap(resources.queue.makeCommandBuffer())
        var uniforms = WelcomeLightUniforms(elapsed: elapsed, size: size, pixelScale: 1)
        uniforms.apply(lock)
        resources.render(command: command, target: target, emission: emission, uniforms: &uniforms)
        command.commit()
        command.waitUntilCompleted()
        XCTAssertNil(command.error)
        var pixels = [UInt8](repeating: 0, count: 256 * 256 * 4)
        texture.getBytes(&pixels, bytesPerRow: 256 * 4, from: MTLRegionMake2D(0, 0, 256, 256), mipmapLevel: 0)
        return pixels
    }
}
