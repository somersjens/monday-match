import XCTest
import MetalKit
@testable import monday_match

@MainActor
final class WelcomeLightMetalTests: XCTestCase {
    func testActualMetalRendererDrawsDistinctHeartAndCirclePoses() throws {
        let resources = try XCTUnwrap(WelcomeLightMetalRenderer.resources, "The real shader must initialize; a Canvas fallback is not this test's renderer.")
        let heart = try render(elapsed: WelcomeLightGeometry.heartTime, resources: resources)
        let circles = try render(elapsed: WelcomeLightGeometry.circleTime, resources: resources)
        for pixels in [heart, circles] {
            let brightPixels = stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 80 }.count
            XCTAssertGreaterThan(brightPixels, 200, "The light field should be visible, not an empty drawable.")
            XCTAssertTrue(stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 255 })
        }
        let difference = zip(heart, circles).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        XCTAssertGreaterThan(difference, 20_000)
    }

    func testRenderedBackgroundEdgesDoNotChangeAtTheLoopBoundary() throws {
        let resources = try XCTUnwrap(WelcomeLightMetalRenderer.resources)
        let times = [0.0, WelcomeLightGeometry.duration - 0.001, WelcomeLightGeometry.duration + 0.001]
        let frames = try times.map { try render(elapsed: $0, resources: resources) }
        let corners = [0, (256 - 1) * 4, (256 * 255) * 4, (256 * 256 - 1) * 4]
        for offset in corners {
            let reference = Array(frames[0][offset..<offset + 4])
            for frame in frames.dropFirst() {
                XCTAssertEqual(Array(frame[offset..<offset + 4]), reference)
            }
        }
    }

    func testRotationAndRibbonFlowKeepAdvancingAcrossTwoLoops() {
        let duration = WelcomeLightGeometry.duration
        var previous = WelcomeLightGeometry.Frame(elapsed: -duration/720)
        for step in 0...1440 {
            let current = WelcomeLightGeometry.Frame(elapsed: Double(step)/720*duration)
            let turn = atan2(
                previous.rotationCos*current.rotationSin - previous.rotationSin*current.rotationCos,
                previous.rotationCos*current.rotationCos + previous.rotationSin*current.rotationSin)
            XCTAssertGreaterThan(turn, 0.004, "Rotation must keep going through the heart and circle, without reversing or stopping.")
            XCTAssertGreaterThan(current.deformationClock, previous.deformationClock)
            XCTAssertLessThanOrEqual(current.volume, 0.24)
            previous = current
        }
    }

    func testAngularVelocityHasNoKinkAtTheHeartOrCircles() {
        let epsilon = 0.0001
        for time in [0, WelcomeLightGeometry.circleTime, WelcomeLightGeometry.duration] {
            let before = WelcomeLightGeometry.Frame(elapsed: time-epsilon)
            let middle = WelcomeLightGeometry.Frame(elapsed: time)
            let after = WelcomeLightGeometry.Frame(elapsed: time+epsilon)
            let incoming = SIMD2((middle.rotationCos-before.rotationCos)/epsilon,
                                 (middle.rotationSin-before.rotationSin)/epsilon)
            let outgoing = SIMD2((after.rotationCos-middle.rotationCos)/epsilon,
                                 (after.rotationSin-middle.rotationSin)/epsilon)
            XCTAssertLessThan(simd_length(incoming-outgoing), 0.001)
            XCTAssertGreaterThan(simd_length(incoming), 0.5)
        }
    }

    func testRenderedLoopClosesForRibbonsLightsAndParticles() throws {
        let resources = try XCTUnwrap(WelcomeLightMetalRenderer.resources)
        let start = try render(elapsed: 0, resources: resources)
        let end = try render(elapsed: WelcomeLightGeometry.duration, resources: resources)
        let difference = zip(start, end).map { abs(Int($0)-Int($1)) }
        XCTAssertLessThanOrEqual(difference.max() ?? 0, 2)
        XCTAssertLessThan(Double(difference.reduce(0, +))/Double(difference.count), 0.01)
    }

    func testEntranceRevealsTheHeartThenRendersExactlyTheExistingLoop() throws {
        let resources = try XCTUnwrap(WelcomeLightMetalRenderer.resources)
        let empty = try render(elapsed: 0, resources: resources, presentation: true)
        let partial = try render(elapsed: WelcomeLightEntrance.traceDuration*0.58, resources: resources, presentation: true)
        let complete = try render(elapsed: WelcomeLightEntrance.traceDuration, resources: resources, presentation: true)
        func brightPixels(_ pixels: [UInt8]) -> Int {
            stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 80 }.count
        }
        XCTAssertEqual(brightPixels(empty), 0)
        XCTAssertGreaterThan(brightPixels(partial), 100)
        XCTAssertGreaterThan(brightPixels(complete), brightPixels(partial))
        for offset in [0.0, 0.3, WelcomeLightGeometry.duration] {
            let time = WelcomeLightEntrance.duration+offset
            let entrance = try render(elapsed: time, resources: resources, presentation: true)
            let loop = try render(elapsed: WelcomeLightEntrance.Frame(elapsed: time).loopElapsed, resources: resources)
            XCTAssertEqual(entrance, loop, "The completed entrance must render the existing loop, not crossfade to another picture.")
        }
    }

    func testAlreadyFormedRightFlankKeepsFlowingDuringTheEntrance() throws {
        let resources = try XCTUnwrap(WelcomeLightMetalRenderer.resources)
        // Both heads are past this region; the rest of the heart is still being
        // formed. A static reveal would produce identical pixels here.
        let first = try render(elapsed: WelcomeLightEntrance.traceDuration*0.62, resources: resources, presentation: true)
        let second = try render(elapsed: WelcomeLightEntrance.traceDuration*0.71, resources: resources, presentation: true)
        var change = 0
        for y in 85..<170 {
            for x in 180..<245 {
                let offset = (y*256+x)*4
                for channel in 0..<3 {
                    change += abs(Int(first[offset+channel])-Int(second[offset+channel]))
                }
            }
        }
        XCTAssertGreaterThan(change, 5_000, "Material already on the heart must keep moving behind the head.")
    }

    func testProjectedRibbonMotionAvoidsThePreviousSpeedAndAccelerationPeaks() throws {
        let resources = try XCTUnwrap(WelcomeLightMetalRenderer.resources)
        let source = WelcomeLightShaderSource.code + #"""
        kernel void projectedMotionProbe(uint id [[thread_position_in_grid]],
          constant WelcomeUniforms &p [[buffer(0)]], device const float2 *controls [[buffer(1)]],
          device const float *travel [[buffer(2)]], device float4 *output [[buffer(3)]]) {
            uint instance = 6+(id/128)*20, sample = id%128;
            float u = p.stream.w+float(sample)/128.0;
            float3 point = ribbonPoint(u,instance,p,controls);
            RibbonVertex v = lightVertex(u,point,
                ribbonPoint(u-0.001,instance,p,controls).xy,
                ribbonPoint(u+0.001,instance,p,controls).xy,
                1,instance,travel[sample*4],p);
            output[id] = float4(point.xy,point.z,v.intensity);
        }
        """#
        let library = try resources.device.makeLibrary(source: source, options: nil)
        let function = try XCTUnwrap(library.makeFunction(name: "projectedMotionProbe"))
        let pipeline = try resources.device.makeComputePipelineState(function: function)
        let count = 6*128
        let output = try XCTUnwrap(resources.device.makeBuffer(
            length: count*MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared))
        func probe(_ time: Double) throws -> [SIMD4<Float>] {
            var uniforms = WelcomeLightUniforms(elapsed: time, size: CGSize(width: 720,height:720), pixelScale: 2)
            let command = try XCTUnwrap(resources.queue.makeCommandBuffer())
            let encoder = try XCTUnwrap(command.makeComputeCommandEncoder())
            encoder.setComputePipelineState(pipeline)
            encoder.setBytes(&uniforms, length: MemoryLayout<WelcomeLightUniforms>.stride, index: 0)
            encoder.setBuffer(resources.controls, offset: 0, index: 1)
            encoder.setBuffer(resources.travel, offset: 0, index: 2)
            encoder.setBuffer(output, offset: 0, index: 3)
            encoder.dispatchThreads(MTLSize(width: count,height:1,depth:1),
                                    threadsPerThreadgroup: MTLSize(width:64,height:1,depth:1))
            encoder.endEncoding()
            command.commit()
            command.waitUntilCompleted()
            XCTAssertNil(command.error)
            let pointer = output.contents().bindMemory(to: SIMD4<Float>.self, capacity: count)
            return Array(UnsafeBufferPointer(start: pointer, count: count))
        }
        let fps = 120.0, dt = 1/fps
        var previous = try probe(-dt), current = try probe(0)
        var speeds: [Double] = []
        var maximumAcceleration = 0.0
        for step in 0...Int(WelcomeLightGeometry.duration*fps) {
            let next = try probe(Double(step+1)*dt)
            var velocity = 0.0, acceleration = 0.0, weight = 0.0
            for index in 0..<count {
                let a = previous[index], b = current[index], c = next[index]
                let w = Double(min(a.w,min(b.w,c.w)))
                if w < 0.006 || abs(b.x)>1.2 || abs(b.y)>1.2 { continue }
                let vx = Double(c.x-a.x)*302.4/(2*dt), vy = Double(c.y-a.y)*302.4/(2*dt)
                let ax = Double(c.x-2*b.x+a.x)*302.4/(dt*dt), ay = Double(c.y-2*b.y+a.y)*302.4/(dt*dt)
                velocity += w*w*(vx*vx+vy*vy)
                acceleration += w*w*(ax*ax+ay*ay)
                weight += w*w
            }
            speeds.append(sqrt(velocity/max(weight,1e-20)))
            maximumAcceleration = max(maximumAcceleration,sqrt(acceleration/max(weight,1e-20)))
            previous = current
            current = next
        }
        speeds.sort()
        let slow = speeds[Int(Double(speeds.count)*0.05)]
        let fast = speeds[Int(Double(speeds.count)*0.95)]
        XCTAssertLessThan(fast/slow, 4, "The previous projected speed ratio was about 6:1.")
        XCTAssertLessThan(speeds.last ?? 0, 270, "The previous visible speed peak was 337 px/s at 720 px.")
        XCTAssertLessThan(maximumAcceleration, 2_500, "The previous acceleration peak exceeded 4,000 px/s².")
    }

    private func render(elapsed: Double, resources: WelcomeLightMetalResources, presentation: Bool = false) throws -> [UInt8] {
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
        var uniforms = presentation
            ? WelcomeLightUniforms(presentationElapsed: elapsed, size: size, pixelScale: 1)
            : WelcomeLightUniforms(elapsed: elapsed, size: size, pixelScale: 1)
        resources.render(command: command, target: target, emission: emission, uniforms: &uniforms)
        command.commit()
        command.waitUntilCompleted()
        XCTAssertNil(command.error)
        var pixels = [UInt8](repeating: 0, count: 256 * 256 * 4)
        texture.getBytes(&pixels, bytesPerRow: 256 * 4, from: MTLRegionMake2D(0, 0, 256, 256), mipmapLevel: 0)
        return pixels
    }
}
