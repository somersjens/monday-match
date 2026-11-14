import XCTest
import Metal
import UIKit
@testable import Stop_Swiping

@MainActor
final class WelcomeLightShareRenderingTests: XCTestCase {
    func testSharingKeepsItsRenderedSizeMovesEvenlyAndAddsNothingBelow() throws {
        let resources = try XCTUnwrap(WelcomeLightMetalRenderer.resources)
        let width = 393, height = 825
        let size = CGSize(width: width, height: height)
        let times = [0.0, 0.16, 0.32, 0.48, 0.72, 0.96, 1.28, 1.6]
        var frames: [UIImage] = []
        var inletLight: [[Int]] = []
        var bounds: [ClosedRange<Int>?] = []
        for elapsed in times {
            var uniforms = WelcomeLightUniforms(presentationElapsed: 40 + elapsed, size: size, pixelScale: 1)
            uniforms.lock = SIMD4(1, 0, 0, 1)
            uniforms.apply(WelcomeLightMatch.pose(elapsed: elapsed, isMatch: true), layout: .match)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            descriptor.storageMode = .shared
            descriptor.usage = [.renderTarget, .shaderRead]
            let texture = try XCTUnwrap(resources.device.makeTexture(descriptor: descriptor))
            let emission = try XCTUnwrap(resources.emissionTexture(size: size))
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
            let litRows = (0..<height).filter { y in
                (100..<293).filter { x in pixels[(y * width + x) * 4] > 80 }.count >= 6
            }
            bounds.append(litRows.first.flatMap { first in litRows.last.map { first...$0 } })
            // The two lower corners must stay clear throughout departure.
            inletLight.append([(-1.0), 1.0].map { side in
                var light = 0
                for y in 590..<690 {
                    for column in 40..<140 {
                        let x = side < 0 ? column : width - column
                        let offset = (y * width + x) * 4
                        light += max(0, Int(pixels[offset]) - 25)
                    }
                }
                return light
            })
            let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
            let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
            frames.append(UIImage(cgImage: image))
        }
        for side in 0..<2 {
            for frame in inletLight.dropFirst() {
                XCTAssertLessThanOrEqual(frame[side], inletLight[0][side] + 200,
                                         "Sharing must not introduce any lower inlets.")
            }
        }
        let initial = try XCTUnwrap(bounds[0])
        let expectedStep = WelcomeLightHelix.Departure.rise * 0.1 * Double(width) * 0.42
        for index in 1...3 {
            let current = try XCTUnwrap(bounds[index])
            // Brightness and glow breathe as the strands turn. Compare both
            // lit edges to their common translation, allowing one glow width;
            // the geometry test separately enforces exact length and speed.
            let translation = Double(index) * expectedStep
            XCTAssertEqual(Double(current.lowerBound), Double(initial.lowerBound) - translation, accuracy: 18,
                           "The leading glow must stay with the constant-speed helix.")
            XCTAssertEqual(Double(current.upperBound), Double(initial.upperBound) - translation, accuracy: 18,
                           "The lower fade must follow the same translation without lingering.")
        }
        XCTAssertNil(bounds.last!, "The helix must leave before the match heart enters.")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let sheet = UIGraphicsImageRenderer(size: CGSize(width: width * 4, height: height * 2), format: format).image { _ in
            for (index, frame) in frames.enumerated() {
                let origin = CGPoint(x: (index % 4) * width, y: (index / 4) * height)
                frame.draw(at: origin)
                ("\(times[index]) s" as NSString).draw(at: CGPoint(x: origin.x + 12, y: origin.y + 12),
                    withAttributes: [.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 16)])
            }
        }
        let attachment = XCTAttachment(image: sheet)
        attachment.name = "Share helix — constant size and speed"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
