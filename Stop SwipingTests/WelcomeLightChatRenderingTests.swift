import XCTest
import Metal
import simd
import UIKit
import ImageIO
import UniformTypeIdentifiers
import SwiftUI
@testable import Stop_Swiping

@MainActor
final class WelcomeLightChatRenderingTests: XCTestCase {
    func testClosureFlowsIntoFirstTurnWithoutWaitingOrStartupSurge() {
        typealias Chat = WelcomeLightMatch.Chat
        func time(for angle: Double) -> Double {
            var low = 0.0, high = 20.0
            for _ in 0..<60 {
                let middle = (low + high) / 2
                if Chat.orbitAngle(elapsed: middle) < angle { low = middle } else { high = middle }
            }
            return (low + high) / 2
        }
        func speed(at time: Double) -> Double {
            (Chat.orbitAngle(elapsed: time + 0.0001) - Chat.orbitAngle(elapsed: time - 0.0001)) / 0.0002
        }
        for angle in [Double.pi / 2, .pi, 3 * .pi / 2] {
            let first = time(for: angle), next = time(for: angle + 2 * .pi)
            XCTAssertGreaterThan(first, Chat.orbitStart + Chat.orbitRamp,
                                 "The pair must finish accelerating before the first visible crossing.")
            XCTAssertEqual(speed(at: first), speed(at: next), accuracy: 0.00001)
        }
        for elapsed in stride(from: 0.0, through: Chat.orbitStart, by: 1.0 / 60) {
            XCTAssertEqual(Chat.orbitAngle(elapsed: elapsed), 0, accuracy: 1e-10,
                           "The turn must only start in the final part of the closure.")
        }
        // The rings look circular before the morph clock ends. They must
        // already be moving at that point, without a brief speed burst.
        XCTAssertGreaterThan(Chat.orbitAngle(elapsed: Chat.morphDuration * 0.75), 0.05)
        XCTAssertGreaterThan(speed(at: Chat.morphDuration * 0.75), 0.4)
        XCTAssertLessThan(Chat.orbitAngle(elapsed: Chat.morphDuration), .pi / 4)
        let firstCrossing = time(for: .pi / 2)
        var peakSpeed = 0.0, peakAcceleration = 0.0
        for elapsed in stride(from: Chat.orbitStart, through: firstCrossing, by: 1.0 / 240) {
            peakSpeed = max(peakSpeed, speed(at: elapsed))
            peakAcceleration = max(peakAcceleration, abs((speed(at: elapsed + 0.001) - speed(at: elapsed - 0.001)) / 0.002))
        }
        XCTAssertLessThan(peakSpeed, 1.05, "Avoid the previous 1.39 rad/s burst at the start.")
        XCTAssertLessThan(peakAcceleration, 1.7, "Avoid the previous 6.93 rad/s² acceleration spike.")
        for elapsed in stride(from: Chat.orbitStart + Chat.orbitRamp, through: 20, by: 0.1) {
            XCTAssertEqual(Chat.orbitAngle(elapsed: elapsed + Chat.orbitPeriod) - Chat.orbitAngle(elapsed: elapsed),
                           2 * .pi, accuracy: 1e-10)
        }
        let epsilon = 0.0001
        for boundary in [Chat.orbitStart, Chat.orbitStart + Chat.orbitRamp] {
            let incoming = (speed(at: boundary) - speed(at: boundary - epsilon)) / epsilon
            let outgoing = (speed(at: boundary + epsilon) - speed(at: boundary)) / epsilon
            XCTAssertEqual(incoming, outgoing, accuracy: 0.001, "The short acceleration must still meet both phases smoothly.")
        }
    }

    func testChatUsesWelcomeRotationAndDeformationWithoutReturningToAHeart() {
        typealias Chat = WelcomeLightMatch.Chat
        for elapsed in stride(from: 0.0, through: 40, by: 0.1) {
            var uniforms = WelcomeLightUniforms(elapsed: 0, size: CGSize(width: 393, height: 825), pixelScale: 1)
            uniforms.applyChat(elapsed: elapsed)
            let welcome = WelcomeLightGeometry.Frame(elapsed: WelcomeLightGeometry.circleTime + Chat.motionElapsed(elapsed: elapsed))
            XCTAssertEqual(uniforms.chat.y, Float(welcome.deformationClock))
            XCTAssertEqual(uniforms.chat.z, Float(welcome.rotationCos))
            XCTAssertEqual(uniforms.chat.w, Float(welcome.rotationSin))
        }
        XCTAssertEqual(Chat.ringCenterY - Chat.radiusY, -0.88, accuracy: 1e-10)
        XCTAssertEqual((Chat.circle.separation + Chat.circle.radius.width) * Chat.scaleX, 0.97, accuracy: 1e-10)
        for width in [320.0, 393, 430, 620] {
            let center = 310.0
            XCTAssertEqual(MatchChatLayout.ringsBottom(unit: width * 0.42, lightCenterY: center),
                           center + Chat.bottomExtent * width * 0.42, accuracy: 1e-9)
        }
        for height in [80.0, 150, 280, 600] {
            let fade = MatchChatLayout.messageFade(viewportHeight: height, ringsBottom: 420, headerHeight: 64)
            XCTAssertGreaterThanOrEqual(height - fade.clear - fade.gradient, min(112, height * 0.7),
                                        "The keyboard must not leave the newest message behind a transparent mask.")
        }
    }

    func testReopenedConversationHasACompleteUnderlyingHeartForBothTransitions() {
        for transition in [WelcomeLightMatch.Transition.newMatch, .savedMatch] {
            var uniforms = WelcomeLightUniforms(elapsed: 0, size: CGSize(width: 393, height: 825), pixelScale: 1)
            uniforms.apply(.init(id: UUID(), isMatch: true, transition: transition, isChatting: true), elapsed: 0, startSeconds: 0)
            XCTAssertEqual(uniforms.match.y, 1.04, accuracy: 0.00001)
            XCTAssertEqual(uniforms.match.z, Float(WelcomeLightMatch.cuspS), accuracy: 0.00001)
            if transition == .savedMatch { XCTAssertEqual(uniforms.matchMorph.x, 1) }
            uniforms.applyChat(elapsed: 100, reduceMotion: true)
            let still = uniforms.chat
            uniforms.applyChat(elapsed: 200, reduceMotion: true)
            XCTAssertEqual(uniforms.chat, still)
            XCTAssertEqual(uniforms.chat.x, 1)
        }
    }

    func testGPUCircleSeamAndMorphStayContinuousAndInsideTheHeartShoulders() throws {
        let resources = try XCTUnwrap(WelcomeLightMetalRenderer.resources)
        let source = WelcomeLightShaderSource.code + """
        kernel void chatProbe(uint id [[thread_position_in_grid]], constant WelcomeUniforms &p [[buffer(0)]],
                              device float4 *output [[buffer(1)]]) {
            uint instance = id/129;
            float s = matchCuspS + float(id%129)/128.0*(chatRingEnd - matchCuspS);
            float3 q = matchPointAt(s, instance, p);
            output[id*2] = float4(q, 0);
            output[id*2 + 1] = float4(chatRingPoint(s + chatRingEnd - matchCuspS, instance, p) - chatRingPoint(s, instance, p), 0);
        }
        """
        let library = try resources.device.makeLibrary(source: source, options: WelcomeLightMetalResources.compileOptions())
        let pipeline = try resources.device.makeComputePipelineState(function: XCTUnwrap(library.makeFunction(name: "chatProbe")))
        let count = 120 * 129
        let buffer = try XCTUnwrap(resources.device.makeBuffer(length: count * 2 * MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared))
        var previous: [SIMD4<Float>]?
        for elapsed in stride(from: 0.0, through: 10, by: 0.1) {
            var uniforms = makeUniforms(elapsed: elapsed, transition: .newMatch)
            let command = try XCTUnwrap(resources.queue.makeCommandBuffer())
            let encoder = try XCTUnwrap(command.makeComputeCommandEncoder())
            encoder.setComputePipelineState(pipeline)
            encoder.setBytes(&uniforms, length: MemoryLayout<WelcomeLightUniforms>.stride, index: 0)
            encoder.setBuffer(buffer, offset: 0, index: 1)
            encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1))
            encoder.endEncoding()
            command.commit()
            command.waitUntilCompleted()
            XCTAssertNil(command.error)
            let values = buffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: count * 2)
            var points: [SIMD4<Float>] = []
            for index in 0..<count {
                let q = values[index * 2]
                XCTAssertTrue(q.x.isFinite && q.y.isFinite && q.z.isFinite)
                XCTAssertLessThan(simd_length(values[index * 2 + 1]), 0.00002, "The closing weave must meet itself, including its depth.")
                if elapsed >= WelcomeLightMatch.Chat.morphDuration {
                    XCTAssertLessThan(abs(q.x), 1.14)
                    XCTAssertGreaterThan(q.y, -1.02)
                    XCTAssertLessThan(q.y, Float(WelcomeLightMatch.Chat.bottomExtent))
                }
                if let previous { XCTAssertLessThan(simd_distance(q, previous[index]), 0.27, "No frame may jump at the morph or orbit handoff.") }
                points.append(q)
            }
            previous = points
        }
    }

    func testRenderHeartToChatForNewSavedAndReopenedConversations() throws {
        var previews: [UIImage] = []
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let times = [0.0, 0.65, 1.3, 2.0, 2.6, 4.5, 6.0, 8.0]
        for transition in [WelcomeLightMatch.Transition.newMatch, .savedMatch] {
            for elapsed in times {
                let image = try render(makeUniforms(elapsed: elapsed, transition: transition))
                let preview = UIGraphicsImageRenderer(size: CGSize(width: 197, height: 260), format: format).image { _ in
                    UIImage(cgImage: image).draw(in: CGRect(x: 0, y: -95, width: 197, height: 413))
                    ("\(transition) / \(elapsed)s" as NSString).draw(at: CGPoint(x: 5, y: 5), withAttributes: [.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 11)])
                }
                previews.append(preview)
            }
        }
        let sheet = UIGraphicsImageRenderer(size: CGSize(width: 197 * times.count, height: 520), format: format).image { _ in
            for (index, preview) in previews.enumerated() {
                preview.draw(at: CGPoint(x: index % times.count * 197, y: index / times.count * 260))
            }
        }
        let attachment = XCTAttachment(image: sheet)
        attachment.name = "Heart shoulders preserved — new and saved chat"
        attachment.lifetime = .keepAlways
        add(attachment)
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        try XCTUnwrap(sheet.pngData()).write(to: directory.appendingPathComponent("chat-rings-contact-sheet.png"))
        let gifURL = directory.appendingPathComponent("chat-rings-motion.gif")
        let gif = try XCTUnwrap(CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, 100, nil))
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in 0..<100 {
            let image = try render(makeUniforms(elapsed: Double(frame) / 10, transition: .newMatch))
            CGImageDestinationAddImage(gif, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(gif))
        print("CHAT_RINGS_PREVIEW \(directory.path)")
        for transition in [WelcomeLightMatch.Transition.newMatch, .savedMatch] {
            var reopened = makeUniforms(elapsed: 2.6, transition: transition)
            reopened.apply(.init(id: UUID(), isMatch: true, transition: transition, isChatting: true), elapsed: 0, startSeconds: 0)
            let image = try render(reopened)
            XCTAssertEqual(image.width, 393)
        }
        var phone = makeUniforms(elapsed: 2.6, transition: .newMatch)
        phone.viewport = SIMD4(1179, 2475, 1179 * 0.42, 3)
        let fullResolution = try render(phone)
        XCTAssertEqual(fullResolution.width, 1179)
    }

    func testRenderFirstTurnBesideFollowingTurn() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let times = [1.3, 1.7, 1.95, 2.2, 2.6, 2.9, 3.3, 4.0]
        var previews: [UIImage] = []
        for previous in [true, false] {
            for elapsed in times {
                var uniforms = makeUniforms(elapsed: elapsed, transition: .newMatch)
                if previous { uniforms.chat = previousChat(elapsed: elapsed) }
                let image = try render(uniforms)
                previews.append(UIGraphicsImageRenderer(size: CGSize(width: 197, height: 260), format: format).image { _ in
                    UIImage(cgImage: image).draw(in: CGRect(x: 0, y: -95, width: 197, height: 413))
                    ("\(previous ? "voor" : "na") / \(elapsed)s" as NSString).draw(at: CGPoint(x: 5, y: 5),
                        withAttributes: [.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 11)])
                })
            }
        }
        let sheet = UIGraphicsImageRenderer(size: CGSize(width: times.count * 197, height: 520), format: format).image { _ in
            for (index, image) in previews.enumerated() { image.draw(at: CGPoint(x: index % times.count * 197, y: index / times.count * 260)) }
        }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        try XCTUnwrap(sheet.pngData()).write(to: directory.appendingPathComponent("chat-first-turn-comparison.png"))
        let gif = try XCTUnwrap(CGImageDestinationCreateWithURL(directory.appendingPathComponent("chat-first-turn-comparison.gif") as CFURL,
                                                              UTType.gif.identifier as CFString, 288, nil))
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in 0..<288 {
            let elapsed = Double(frame) / 24
            let after = makeUniforms(elapsed: elapsed, transition: .newMatch)
            var before = after
            before.chat = previousChat(elapsed: elapsed)
            let first = try render(before), second = try render(after)
            let comparison = UIGraphicsImageRenderer(size: CGSize(width: 786, height: 500), format: format).image { _ in
                UIImage(cgImage: first).draw(at: CGPoint(x: 0, y: -170))
                UIImage(cgImage: second).draw(at: CGPoint(x: 393, y: -170))
                for (title, x) in [("Vorige aanloop", 12), ("Verbeterde aanloop", 405)] {
                    (title as NSString).draw(at: CGPoint(x: x, y: 12), withAttributes: [.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 15)])
                }
            }
            CGImageDestinationAddImage(gif, try XCTUnwrap(comparison.cgImage),
                                      [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 24]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(gif))
        print("CHAT_FIRST_TURN_PREVIEW \(directory.path)")
    }

    private func previousChat(elapsed: Double) -> SIMD4<Float> {
        let t = max(0, elapsed - 2.2), ramp = 0.4
        let x = min(t / ramp, 1)
        let travel = t < ramp ? ramp * x*x*x*x * (2.5 - 3*x + x*x) : t - ramp / 2
        let frame = WelcomeLightGeometry.Frame(elapsed: WelcomeLightGeometry.circleTime + travel)
        return SIMD4(Float(WelcomeLightMatch.Chat.progress(elapsed: elapsed)), Float(frame.deformationClock), Float(frame.rotationCos), Float(frame.rotationSin))
    }

    func testChatLayoutPreservesHeartPositionAtCompactAndStandardSizes() async throws {
        let language = AppLanguageSettings.shared.language
        defer { AppLanguageSettings.shared.language = language }
        AppLanguageSettings.shared.language = .dutch
        var person = ProfileCreationState(today: .today(), applicationLanguage: "nl")
        person.displayName = "Alex"
        let match = MatchSnapshot(matchedAt: Date(), you: person, them: person, fixedScores: .init(yours: 88, theirs: 90))
        let chat = ChatViewModel(conversation: .init(matchID: match.id, participantName: "Alex", messages: [
            .init(sender: .match, text: "Hoi! Leuk dat we een match hebben."),
            .init(sender: .currentUser, text: "Zullen we samen koffie drinken?")
        ]))
        for size in [CGSize(width: 320, height: 568), CGSize(width: 393, height: 852)] {
            for keyboardHeight in [0.0, 280.0] {
                let visibleSize = CGSize(width: size.width, height: size.height - keyboardHeight)
                let centerY = (size.height - 160) / 2
                let unit = size.width * 0.42
                var uniforms = makeUniforms(elapsed: 2.6, transition: .newMatch)
                uniforms.viewport = SIMD4(Float(size.width), Float(size.width * 2.1), Float(unit), 1)
                let art = try render(uniforms)
                let content = ZStack {
                    OnboardingTheme.background
                    Image(uiImage: UIImage(cgImage: art))
                        .resizable().frame(width: size.width, height: size.width * 2.1)
                        .position(x: size.width / 2, y: centerY)
                    MatchResultOverlay(match: match, report: match.report,
                        frame: .init(center: CGPoint(x: size.width / 2, y: centerY), unit: unit),
                        reveal: .controls, isSaved: false, onShowScores: { _ in }, onShowProfile: {}, onRename: { _ in },
                        onSave: {}, onClose: {}, onDelete: {}, chat: chat, isChatting: true,
                        chatRingsBottom: MatchChatLayout.ringsBottom(unit: unit, lightCenterY: centerY))
                }.frame(width: visibleSize.width, height: visibleSize.height).clipped().preferredColorScheme(.dark)
                let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
                let window = UIWindow(windowScene: scene)
                let host = UIHostingController(rootView: content.ignoresSafeArea())
                window.rootViewController = host
                window.frame = CGRect(origin: .zero, size: visibleSize)
                window.isHidden = false
                host.view.frame = window.bounds
                host.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(250))
                host.view.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(size: visibleSize).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
                let name = "chat-layout-\(Int(size.width))-keyboard-\(Int(keyboardHeight))"
                let attachment = XCTAttachment(image: image)
                attachment.name = name
                attachment.lifetime = .keepAlways
                add(attachment)
                try XCTUnwrap(image.pngData()).write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name + ".png"))
                window.isHidden = true
                window.rootViewController = nil
            }
        }
    }

    private func makeUniforms(elapsed: Double, transition: WelcomeLightMatch.Transition) -> WelcomeLightUniforms {
        var uniforms = WelcomeLightUniforms(elapsed: 0, size: CGSize(width: 393, height: 825), pixelScale: 1)
        uniforms.shape.w = Float(40 + elapsed)
        uniforms.lock = SIMD4(1, 0, 0, 1)
        uniforms.apply(.init(id: UUID(), isMatch: true, transition: transition, isChatting: true), elapsed: 20, startSeconds: 0)
        uniforms.applyChat(elapsed: elapsed)
        return uniforms
    }

    private func render(_ input: WelcomeLightUniforms) throws -> CGImage {
        let resources = try XCTUnwrap(WelcomeLightMetalRenderer.resources)
        let width = Int(input.viewport.x), height = Int(input.viewport.y)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead]
        let texture = try XCTUnwrap(resources.device.makeTexture(descriptor: descriptor))
        let emission = try XCTUnwrap(resources.emissionTexture(size: CGSize(width: width, height: height)))
        let target = MTLRenderPassDescriptor()
        target.colorAttachments[0].texture = texture
        target.colorAttachments[0].loadAction = .clear
        target.colorAttachments[0].storeAction = .store
        let command = try XCTUnwrap(resources.queue.makeCommandBuffer())
        var uniforms = input
        resources.render(command: command, target: target, emission: emission, uniforms: &uniforms)
        command.commit()
        command.waitUntilCompleted()
        XCTAssertNil(command.error)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        XCTAssertGreaterThan(stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 80 }.count, 100)
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
}
