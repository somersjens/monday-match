import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// The helix rewoven into a QR code of light. Every filament loop becomes two
/// neighbouring horizontal lines, running across and back, so together they
/// fill a square of evenly spaced lines; the shader only lets the dark
/// modules glow. Coordinates match `WelcomeLightGeometry`'s normalized space,
/// and the Metal shader mirrors `point` exactly.
enum WelcomeLightCode {
    /// What the code encodes. It isn't connected to anything yet.
    static let message = "Stop Swiping"
    /// The width and height of the module grid.
    static let side = 1.3
    /// Lines run a little past the grid, so their turns are never lit.
    static let reach = 0.54
    static let lineCount = 2 * 2 * WelcomeLightGeometry.strandCount
    static let morphDuration = 1.6

    /// Row-major modules from the top-left, 1 for dark, without quiet zone.
    static let modules: [UInt8] = matrix.modules
    static let size: Int = matrix.size
    static var isAvailable: Bool { size > 0 }

    static func point(u: Double, ring: Int, strand: Int, seconds: Double) -> (point: CGPoint, local: CGPoint) {
        let phase = (u + 0.5) * WelcomeLightGeometry.tau
        let h = asin(0.995 * cos(phase)) / asin(0.995)
        let pass = tanh(sin(phase) / 0.04)
        let spacing = side / Double(lineCount)
        let pair = Double(strand * 2 + ring)
        let local = CGPoint(x: -h * side * reach, y: -side / 2 + (2 * pair + 1) * spacing - pass * spacing / 2)
        // A slow sway keeps the code alive without blurring its modules.
        let yaw = 0.16 * sin(seconds * 0.45)
        let pitch = 0.07 * sin(seconds * 0.33 + 1.1)
        let breathe = 1 + 0.01 * sin(seconds * 1.3)
        let z = local.x * sin(yaw) + local.y * sin(pitch)
        let perspective = breathe / (1 - z * 0.30)
        return (CGPoint(x: local.x * cos(yaw) * perspective, y: local.y * cos(pitch) * perspective), local)
    }

    /// Rows fill from the top down, each strand with its own small delay.
    static func strandAmount(_ amount: Double, u: Double, ring: Int, strand: Int) -> Double {
        guard amount > 0 else { return 0 }
        let row = Double(strand * 2 + ring) / Double(lineCount / 2 - 1)
        let jitter = 0.10 * (0.5 + 0.5 * sin(u * WelcomeLightGeometry.tau + Double(ring * WelcomeLightGeometry.strandCount + strand) * 0.37))
        return WelcomeLightLock.ease(amount * 1.55 - 0.45 * row - jitter)
    }

    static func isDark(local: CGPoint) -> Bool {
        let column = Int(floor((local.x / side + 0.5) * Double(size)))
        let row = Int(floor((local.y / side + 0.5) * Double(size)))
        guard (0..<size).contains(column), (0..<size).contains(row) else { return false }
        return modules[row * size + column] == 1
    }

    private static let matrix: (size: Int, modules: [UInt8]) = {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(message.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let image = CIContext(options: [.useSoftwareRenderer: true]).createCGImage(output, from: output.extent)
        else { return (0, []) }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 255, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return (0, []) }
        // The generator adds a quiet zone; the light needs only the modules.
        let dark = pixels.indices.filter { pixels[$0] < 128 }
        guard !dark.isEmpty else { return (0, []) }
        var minX = width, maxX = 0, minY = height, maxY = 0
        for index in dark {
            minX = min(minX, index % width); maxX = max(maxX, index % width)
            minY = min(minY, index / width); maxY = max(maxY, index / width)
        }
        let size = max(maxX - minX, maxY - minY) + 1
        var modules = [UInt8](repeating: 0, count: size * size)
        for row in 0..<size {
            for column in 0..<size {
                let x = minX + column, y = minY + row
                guard x < width, y < height else { continue }
                modules[row * size + column] = pixels[y * width + x] < 128 ? 1 : 0
            }
        }
        return (size, modules)
    }()
}
