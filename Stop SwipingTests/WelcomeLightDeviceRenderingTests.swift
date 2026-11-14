import XCTest
import Metal
import simd
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import Stop_Swiping

@MainActor
final class WelcomeLightDeviceRenderingTests: XCTestCase {
    func testCuspDoesNotAmplifyRoundingAcrossCompilerModesClocksAndOutcomes() throws {
        let resources = try XCTUnwrap(WelcomeLightMetalRenderer.resources)
        let source = WelcomeLightShaderSource.code + """
        kernel void rootBoundsProbe(uint id [[thread_position_in_grid]],
            constant WelcomeUniforms &p [[buffer(0)]], device float3 *output [[buffer(1)]]) {
            float3 root = matchPoint(p.stream.w + matchCuspS, id, p);
            float3 exact = matchPointAt(matchCuspS, id, p);
            float3 after = matchPointAt(savedHeartS(-0.002, p), id, p);
            output[id*3] = root - exact;
            output[id*3 + 1] = (root - after)/0.002;
            output[id*3 + 2] = savedMatchRoute(0.14, float3(0.2, 0.3, 0.2), 0.3, id, p);
        }
        """
        let count = WelcomeLightGeometry.strandCount * 2
        let output = try XCTUnwrap(resources.device.makeBuffer(
            length: count * 3 * MemoryLayout<SIMD3<Float>>.stride, options: .storageModeShared))
        for mode in [MTLMathMode.safe, .fast] {
            let options = WelcomeLightMetalResources.compileOptions()
            options.mathMode = mode
            let library = try resources.device.makeLibrary(source: source, options: options)
            let pipeline = try resources.device.makeComputePipelineState(
                function: try XCTUnwrap(library.makeFunction(name: "rootBoundsProbe")))
            for isMatch in [true, false] {
                let layout = WelcomeLightMatch.Layout.of(isMatch: isMatch)
                for seconds in [0.01, 1.1, 3.2, 7.4, 16.5, 41.9, 120.1, 1000.3] {
                    for start in [Float(WelcomeLightGeometry.entranceStartU), Float(0.3), Float(0.59375006)] {
                        var uniforms = WelcomeLightUniforms(elapsed: 0, size: CGSize(width: 1179, height: 2475), pixelScale: 3)
                        uniforms.shape.w = Float(seconds)
                        uniforms.stream.w = start
                        uniforms.apply(WelcomeLightMatch.pose(elapsed: 0.8, isMatch: isMatch, transition: .savedMatch), layout: layout)
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
                        let points = output.contents().bindMemory(to: SIMD3<Float>.self, capacity: count * 3)
                        var rootError: Float = 0, speed: Float = 0, spur: Float = 0
                        let cuspY = Float(-0.62 * layout.scale + layout.offsetY)
                        for instance in 0..<count {
                            rootError = max(rootError, simd_length(points[instance * 3]))
                            speed = max(speed, simd_length(points[instance * 3 + 1]))
                            let position = points[instance * 3 + 2]
                            XCTAssertTrue(position.x.isFinite && position.y.isFinite && position.z.isFinite)
                            spur = max(spur, abs(position.x), abs(position.y - cuspY))
                        }
                        XCTAssertLessThan(rootError, 0.00001, "A rounded mesh coordinate must resolve to the outgoing heart root.")
                        XCTAssertLessThan(speed, 2, "A GPU boundary-rounding error must not become a 100x or 1000x tangent.")
                        XCTAssertLessThan(spur, 0.4, "The connection must not emit tall stray lines.")
                    }
                }
            }
        }
    }

    private struct Frame {
        let image: CGImage
        let gpuTime: Double
    }

    private func render(_ uniforms: WelcomeLightUniforms) throws -> Frame {
        let resources = try XCTUnwrap(WelcomeLightMetalRenderer.resources)
        let width = Int(uniforms.viewport.x), height = Int(uniforms.viewport.y)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead]
        let texture = try XCTUnwrap(resources.device.makeTexture(descriptor: descriptor))
        let emission = try XCTUnwrap(resources.emissionTexture(size: CGSize(width: width, height: height)))
        let target = MTLRenderPassDescriptor()
        target.colorAttachments[0].texture = texture
        target.colorAttachments[0].loadAction = .clear
        target.colorAttachments[0].storeAction = .store
        let command = try XCTUnwrap(resources.queue.makeCommandBuffer())
        var uniforms = uniforms
        resources.render(command: command, target: target, emission: emission, uniforms: &uniforms)
        command.commit()
        command.waitUntilCompleted()
        XCTAssertNil(command.error)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        return Frame(image: image, gpuTime: command.gpuEndTime - command.gpuStartTime)
    }

    func testPhoneResolutionUsesTheAppRenderPathForAllMatchModes() throws {
        let size = CGSize(width: 1179, height: 2475)
        let times = [0.0, 0.04, 0.10, 0.18, 0.35, 0.65, 1.1, 1.7, 2.2]
        let captured = WelcomeLightHelix.Arrival.motionSeconds(atPresentation: 40, reduceMotion: false)
        var thumbnails: [UIImage] = []
        var totalGPUTime = 0.0, frameCount = 0
        for transition in [WelcomeLightMatch.Transition.savedMatch, .newMatch] {
            for isMatch in [true, false] {
                let request = WelcomeLightMatch.Request(id: UUID(), isMatch: isMatch, transition: transition)
                for elapsed in times {
                    let time = transition == .savedMatch ? elapsed : WelcomeLightMatch.exitDuration + elapsed
                    var uniforms = WelcomeLightUniforms(presentationElapsed: 40 + time, size: size, pixelScale: 3)
                    uniforms.apply(WelcomeLightLock.Pose(amount: 1, lift: 0, shake: 0, isHelix: true))
                    // This is the same request-to-uniform function used by draw(in:).
                    uniforms.apply(request, elapsed: time, startSeconds: captured)
                    let frame = try render(uniforms)
                    totalGPUTime += frame.gpuTime
                    frameCount += 1
                    let crop = try XCTUnwrap(frame.image.cropping(to: CGRect(x: 0, y: 390, width: 1179, height: 1500)))
                    let format = UIGraphicsImageRendererFormat(); format.scale = 1
                    let thumbnail = UIGraphicsImageRenderer(size: CGSize(width: 236, height: 300), format: format).image { _ in
                        UIImage(cgImage: crop).draw(in: CGRect(x: 0, y: 0, width: 236, height: 300))
                        let label = "\(transition) / \(isMatch ? "match" : "no match") / \(elapsed)"
                        (label as NSString).draw(at: CGPoint(x: 4, y: 4), withAttributes: [.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 10)])
                    }
                    thumbnails.append(thumbnail)
                }
            }
        }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let sheet = UIGraphicsImageRenderer(size: CGSize(width: 236 * times.count, height: 300 * 4), format: format).image { _ in
            for (i, frame) in thumbnails.enumerated() {
                frame.draw(at: CGPoint(x: (i % times.count) * 236, y: (i / times.count) * 300))
            }
        }
        let attachment = XCTAttachment(image: sheet)
        attachment.name = "Phone resolution — actual app render path, all match modes"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("DEVICE_RENDER_GPU_MS=\(1000 * totalGPUTime / Double(frameCount))")
    }
}
