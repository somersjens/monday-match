import SwiftUI
import UIKit
import XCTest
@testable import Stop_Swiping

@MainActor
final class FaceVerificationLayoutTests: XCTestCase {
    func testRenderCircularScanAndResultAtPhoneSizes() async throws {
        let cases: [(String, CGFloat, CGFloat, FaceScanSnapshot, FaceVerificationOutcome?)] = [
            ("circle", 393, 852, FaceScanSnapshot(phase: .circling, collectedSectors: [0, 1, 2], targetSector: 3,
                                                  cursor: CGPoint(x: 0.8, y: 0.5), clockwise: true,
                                                  instruction: "Follow the ball with your head"), nil),
            ("compact", 320, 568, FaceScanSnapshot(), nil),
            ("matched", 393, 852, FaceScanSnapshot(phase: .finishing, collectedSectors: Set(0..<8)), .match),
            ("retry", 393, 852, FaceScanSnapshot(phase: .circling, collectedSectors: [0, 1, 2]),
             .failed("Your face was out of view for too long. Please start a new scan."))
        ]
        for (name, width, height, snapshot, outcome) in cases {
            let screen = FaceVerificationScreen(snapshot: snapshot, outcome: outcome, needsCameraPermission: false,
                                                onCancel: {}, onRetry: {}, onSettings: {}, onDone: {}) {
                ZStack {
                    LinearGradient(colors: [.init(white: 0.16), .init(white: 0.05)], startPoint: .top, endPoint: .bottom)
                    Image(systemName: "person.fill")
                        .font(.system(size: 160, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.18))
                }
            }
            // ImageRenderer omits ScrollView's platform content. Host the
            // actual UIKit hierarchy so visual QA sees the live-screen layout.
            // Unit-test hosting can run without an activated scene. A detached
            // window still hosts the UIKit hierarchy for offscreen rendering.
            let window: UIWindow
            if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
                window = UIWindow(windowScene: scene)
                window.frame = scene.effectiveGeometry.coordinateSpace.bounds
            } else {
                window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
            }
            let host = UIHostingController(rootView: screen)
            let container = UIViewController()
            window.rootViewController = container
            window.isHidden = false
            container.addChild(host)
            container.view.addSubview(host.view)
            host.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                host.view.widthAnchor.constraint(equalToConstant: width),
                host.view.heightAnchor.constraint(equalToConstant: height),
                host.view.topAnchor.constraint(equalTo: container.view.topAnchor),
                host.view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor)
            ])
            host.didMove(toParent: container)
            container.view.layoutIfNeeded()
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(120))
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
            let image = renderer.image { _ in
                host.view.drawHierarchy(in: CGRect(x: 0, y: 0, width: width, height: height), afterScreenUpdates: true)
            }
            window.isHidden = true
            window.rootViewController = nil
            XCTAssertEqual(image.size.width, width)
            XCTAssertEqual(image.size.height, height)
            // Avoid reporting a blank platform ScrollView as a successful render.
            let cgImage = try XCTUnwrap(image.cgImage)
            var pixels = [UInt8](repeating: 0, count: 160 * 160 * 4)
            let context = try XCTUnwrap(CGContext(data: &pixels, width: 160, height: 160, bitsPerComponent: 8,
                                                bytesPerRow: 160 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 160, height: 160))
            let litPixels = (35..<120).reduce(0) { total, y in
                total + (15..<145).filter { x in
                    let offset = (y * 160 + x) * 4
                    // The initial state deliberately uses a muted gray camera
                    // placeholder; distinguish it from the navy background.
                    return max(pixels[offset], pixels[offset + 1], pixels[offset + 2]) > 60
                }.count
            }
            XCTAssertGreaterThan(litPixels, 100, "The scan or result content must actually be rendered.")
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("face-verification-\(name).png")
            try XCTUnwrap(image.pngData()).write(to: url)
            print("FACE_VERIFICATION_RENDER \(url.path)")
        }
    }
}
