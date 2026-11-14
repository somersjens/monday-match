import XCTest
import Metal
import simd
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import Stop_Swiping

@MainActor
final class WelcomeLightSavedMatchRenderingTests: XCTestCase {
    func testCoilIsPhysicallyConsumedThroughTheCuspWithoutTurningTheRemainingHelix() throws {
        let resources = try XCTUnwrap(WelcomeLightMetalRenderer.resources)
        let source = WelcomeLightShaderSource.code + """
        kernel void savedFeedProbe(uint id [[thread_position_in_grid]],
            constant WelcomeUniforms &p [[buffer(0)]], device float4 *output [[buffer(1)]]) {
            uint instance = id/65;
            float u = p.stream.w + float(id%65)/64.0;
            output[id] = float4(savedMatchPoint(u, instance, p).xy, helixPoint(u, instance, p).xy);
        }
        """
        let library = try resources.device.makeLibrary(source: source, options: nil)
        let pipeline = try resources.device.makeComputePipelineState(
            function: try XCTUnwrap(library.makeFunction(name: "savedFeedProbe")))
        let count = WelcomeLightGeometry.strandCount * 2 * 65
        let output = try XCTUnwrap(resources.device.makeBuffer(
            length: count * MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared))
        let capturedSeconds = WelcomeLightHelix.Arrival.motionSeconds(atPresentation: 40, reduceMotion: false)
        for layout in [WelcomeLightMatch.Layout.match, .noMatch] {
            var previous: [SIMD4<Float>]?
            for progress in [0.0, 0.05, 0.2, 0.4, 0.6, 0.9, 1.0] {
                let elapsed = progress * WelcomeLightMatch.Transition.savedMorphDuration
                var uniforms = WelcomeLightUniforms(presentationElapsed: 40 + elapsed,
                    size: CGSize(width: 393, height: 825), pixelScale: 1)
                uniforms.lock = SIMD4(1, 0, 0, 1)
                uniforms.apply(WelcomeLightMatch.pose(elapsed: elapsed,
                    isMatch: layout == .match, transition: .savedMatch), layout: layout, startSeconds: capturedSeconds)
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
                let buffer = output.contents().bindMemory(to: SIMD4<Float>.self, capacity: count)
                let points = Array(UnsafeBufferPointer(start: buffer, count: count))
                let cuspY = Float(-0.62 * layout.scale + layout.offsetY)
                var rotationError: Float = 0
                var lowerMotionError: Float = 0
                for (index, point) in points.enumerated() {
                    let u = Double(uniforms.stream.w) + Double(index % 65) / 64
                    let h = asin(0.995 * cos((u + 0.5) * .pi * 2)) / asin(0.995)
                    let advance = 1 - pow(1 - progress, 1.8)
                    let materialHeight = (h + 1 - 2 * advance) * WelcomeLightHelix.halfHeight
                    if materialHeight > 0.50 {
                        rotationError = max(rotationError, abs(point.x - point.z))
                        if let previous, progress >= 0.4 {
                            lowerMotionError = max(lowerMotionError, point.y - previous[index].y)
                        }
                    }
                }
                XCTAssertLessThan(rotationError, 0.0001, "The remaining coil keeps its phase; only material at the throat curls inward.")
                XCTAssertLessThan(lowerMotionError, 0.0001, "The finite coil must actually move upward as it feeds the heart.")
                // The growing heart starts at the helix tip and shares its
                // slow downward drift; allow the lobes above that same tip.
                XCTAssertGreaterThan(points.map { $0.y }.min()!, -1.55, "No strand may leave above the artwork.")
                if progress == 1 {
                    let xs = points.map { $0.x }, ys = points.map { $0.y }
                    XCTAssertGreaterThan(xs.max()! - xs.min()!, Float(1.8 * layout.scale),
                        "The original material must continue around both lobes, rather than collapsing at the cusp.")
                    XCTAssertGreaterThan(ys.max()!, Float(0.7 * layout.scale + layout.offsetY))
                }
                previous = points
            }
        }
    }

    func testEachFilamentContinuesThroughTheJoinWithMatchingPositionAndVelocity() throws {
        let resources = try XCTUnwrap(WelcomeLightMetalRenderer.resources)
        let source = WelcomeLightShaderSource.code + """
        kernel void joinProbe(uint id [[thread_position_in_grid]],
            constant WelcomeUniforms &p [[buffer(0)]], device float3 *output [[buffer(1)]]) {
            float height = (float(id%3) - 1)*0.0001;
            output[id] = savedMatchRoute(height, float3(0.2, 0, 0.2), 0, id/3, p);
        }
        """
        let library = try resources.device.makeLibrary(source: source, options: nil)
        let pipeline = try resources.device.makeComputePipelineState(function: try XCTUnwrap(library.makeFunction(name: "joinProbe")))
        let count = WelcomeLightGeometry.strandCount * 2 * 3
        let output = try XCTUnwrap(resources.device.makeBuffer(length: count * MemoryLayout<SIMD3<Float>>.stride, options: .storageModeShared))
        for layout in [WelcomeLightMatch.Layout.match, .noMatch] {
            var uniforms = WelcomeLightUniforms(presentationElapsed: 40, size: CGSize(width: 393, height: 825), pixelScale: 1)
            uniforms.lock = SIMD4(1, 0, 0, 1)
            uniforms.apply(WelcomeLightMatch.pose(elapsed: 0.8, isMatch: layout == .match, transition: .savedMatch), layout: layout)
            let command = try XCTUnwrap(resources.queue.makeCommandBuffer())
            let encoder = try XCTUnwrap(command.makeComputeCommandEncoder())
            encoder.setComputePipelineState(pipeline)
            encoder.setBytes(&uniforms, length: MemoryLayout<WelcomeLightUniforms>.stride, index: 0)
            encoder.setBuffer(output, offset: 0, index: 1)
            encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1))
            encoder.endEncoding()
            command.commit()
            command.waitUntilCompleted()
            XCTAssertNil(command.error)
            let points = output.contents().bindMemory(to: SIMD3<Float>.self, capacity: count)
            for instance in 0..<(count / 3) {
                let before = points[instance * 3 + 2], root = points[instance * 3 + 1], after = points[instance * 3]
                let arriving = (before - root) / 0.0001, leaving = (root - after) / 0.0001
                XCTAssertLessThan(simd_length(arriving - leaving), 0.06,
                    "A filament must keep its direction and speed through the cusp instead of stopping there.")
                XCTAssertGreaterThan(simd_length(leaving), 0.5, "The material must travel beyond the cusp.")
            }
        }
    }

    func testSavedMatchKeepsLightOnScreenAndPreservesBothEndpoints() throws {
        let resources = try XCTUnwrap(WelcomeLightMetalRenderer.resources)
        let width = 393, height = 825
        let times = [0.0, 0.15, 0.35, 0.6, 0.9, 1.3, 1.7, 2.2]
        let request = WelcomeLightMatch.Request(id: UUID(), isMatch: true, transition: .savedMatch)
        var frames: [UIImage] = []
        let animation = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(animation, UTType.gif.identifier as CFString, 97, nil))
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)

        func render(_ uniforms: WelcomeLightUniforms) throws -> [UInt8] {
            var uniforms = uniforms
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
            resources.render(command: command, target: target, emission: emission, uniforms: &uniforms)
            command.commit()
            command.waitUntilCompleted()
            XCTAssertNil(command.error)
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            texture.getBytes(&pixels, bytesPerRow: width * 4,
                             from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            return pixels
        }

        for index in 0...96 {
            let elapsed = Double(index) * 0.025
            var baseline = WelcomeLightUniforms(presentationElapsed: 40 + elapsed,
                size: CGSize(width: width, height: height), pixelScale: 1)
            baseline.lock = SIMD4(1, 0, 0, 1)
            var uniforms = baseline
            uniforms.apply(request, elapsed: elapsed,
                startSeconds: WelcomeLightHelix.Arrival.motionSeconds(atPresentation: 40, reduceMotion: false))
            let pixels = try render(uniforms)
            if elapsed == 0 {
                let ordinary = try render(baseline)
                let differences = zip(pixels, ordinary).map { abs(Int($0) - Int($1)) }
                // The ordinary renderer blends through its lock/heart branch;
                // permit only sub-visible rounding at that shader handoff.
                XCTAssertLessThanOrEqual(differences.max()!, 2, "Opening the match must preserve the visible helix.")
                XCTAssertLessThan(Double(differences.reduce(0, +)) / Double(differences.count), 0.01)
            }
            if index == 88 {
                baseline.apply(WelcomeLightMatch.pose(elapsed: WelcomeLightMatch.heartEnd, isMatch: true), layout: .match)
                let ordinary = try render(baseline)
                func bounds(_ data: [UInt8]) -> (Int, Int, Int, Int) {
                    let lit = (0..<(width * height)).filter { data[$0 * 4] > 80 }
                    let xs = lit.map { $0 % width }, ys = lit.map { $0 / width }
                    return (xs.min()!, xs.max()!, ys.min()!, ys.max()!)
                }
                let actual = bounds(pixels), expected = bounds(ordinary)
                for (a, b) in [(actual.0, expected.0), (actual.1, expected.1), (actual.2, expected.2), (actual.3, expected.3)] {
                    XCTAssertEqual(a, b, accuracy: 12, "The transported filaments must settle on the same heart silhouette.")
                }
            }
            let litPixels = (270..<560).reduce(0) { total, y in
                total + (80..<313).filter { x in pixels[(y * width + x) * 4] > 80 }.count
            }
            XCTAssertGreaterThan(litPixels, 100, "The heart area must stay lit throughout the morph at \(elapsed) seconds.")
            let upperLight = (0..<170).reduce(0) { total, y in
                total + (0..<width).filter { x in pixels[(y * width + x) * 4] > 80 }.count
            }
            XCTAssertLessThanOrEqual(upperLight, 4,
                "No strand may travel into the empty area above the heart at \(elapsed) seconds.")
            let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
            let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
            if times.contains(where: { abs($0 - elapsed) < 0.001 }) { frames.append(UIImage(cgImage: image)) }
            let crop = try XCTUnwrap(image.cropping(to: CGRect(x: 0, y: 200, width: width, height: 420)))
            CGImageDestinationAddImage(destination, crop,
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.025]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let previewURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("coil-heart-preview.gif")
        try (animation as Data).write(to: previewURL)
        print("ANIMATION_PREVIEW_PATH=\(previewURL.path)")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let sheet = UIGraphicsImageRenderer(size: CGSize(width: width * 4, height: height * 2), format: format).image { _ in
            for (index, frame) in frames.enumerated() {
                let origin = CGPoint(x: (index % 4) * width, y: (index / 4) * height)
                frame.draw(at: origin)
                ("\(times[index]) s" as NSString).draw(at: CGPoint(x: origin.x + 12, y: origin.y + 24),
                    withAttributes: [.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 18)])
            }
        }
        let sheetURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("coil-heart-frames.png")
        try XCTUnwrap(sheet.pngData()).write(to: sheetURL)
        print("ANIMATION_FRAMES_PATH=\(sheetURL.path)")
        let attachment = XCTAttachment(image: sheet)
        attachment.name = "Saved match — continuous in-place morph"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
