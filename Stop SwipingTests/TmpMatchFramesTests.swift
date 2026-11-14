import XCTest
import Metal
import UIKit
@testable import Stop_Swiping

/// Temporary: renders the helix exit for visual review.
final class TmpMatchFramesTests: XCTestCase {
    func testRenderMatchFrames() throws {
        let resources = try XCTUnwrap(WelcomeLightMetalRenderer.resources)
        let size = CGSize(width: 393*2, height: 825*2)
        let times: [Double] = [0, 0.2, 0.4, 0.6, 0.8, 1.0, 1.2, 1.4]
        var frames: [UIImage] = []
        for elapsed in times {
            var uniforms = WelcomeLightUniforms(presentationElapsed: 40 + elapsed, size: size, pixelScale: 2)
            uniforms.lock = SIMD4(1, 0, 0, 1)
            uniforms.apply(WelcomeLightMatch.pose(elapsed: elapsed, isMatch: true), layout: .match)
            let width = Int(size.width), height = Int(size.height)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
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
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            texture.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
                                provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            // The part of the frame that is on screen, down to just below the helix.
            frames.append(UIImage(cgImage: image.cropping(to: CGRect(x: 150, y: 224, width: 486, height: 1000))!))
        }
        let w: CGFloat = 195, h = w * frames[0].size.height / frames[0].size.width
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let data = UIGraphicsImageRenderer(size: CGSize(width: w * CGFloat(frames.count), height: h), format: format).pngData { context in
            for (index, frame) in frames.enumerated() {
                frame.draw(in: CGRect(x: CGFloat(index) * w, y: 0, width: w, height: h))
                UIColor.white.withAlphaComponent(0.25).setStroke()
                context.stroke(CGRect(x: CGFloat(index) * w, y: 0, width: w, height: h))
            }
        }
        try data.write(to: URL(fileURLWithPath: "/private/tmp/claude-501/-Users-jenssomers--claude-spares-spare-qMOcN1/b55d1535-8153-438c-ac8f-ae1975d833ac/scratchpad/match/exit.png"))
    }
}
