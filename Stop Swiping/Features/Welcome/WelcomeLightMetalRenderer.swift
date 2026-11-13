import SwiftUI
import MetalKit

/// Real-time emissive threads. Only sparse geometry/pose data is bundled;
/// no reference images, sampled frames or video decoder are used at runtime.
struct WelcomeLightMetalView: UIViewRepresentable {
    let reduceMotion: Bool
    let isActive: Bool
    var form = WelcomeLightForm.heart
    var lockPulse = 0
    var showsCode = false
    /// Starts after the entrance, for a light that is shown already formed.
    var skipsEntrance = false
    var framesPerSecond = 60
    var helixEntryDistance = 0.0
    var match: WelcomeLightMatch.Request?

    static var isAvailable: Bool { WelcomeLightMetalRenderer.resources != nil }

    func makeCoordinator() -> WelcomeLightMetalRenderer {
        WelcomeLightMetalRenderer(skipsEntrance: skipsEntrance)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: WelcomeLightMetalRenderer.resources?.device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0.008, 0.012, 0.035, 1)
        view.isOpaque = true
        view.backgroundColor = UIColor(named: "WelcomeBackground")
        view.framebufferOnly = true
        view.preferredFramesPerSecond = framesPerSecond
        view.delegate = context.coordinator
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        if view.preferredFramesPerSecond != framesPerSecond {
            view.preferredFramesPerSecond = framesPerSecond
        }
        context.coordinator.update(reduceMotion: reduceMotion, isActive: isActive)
        context.coordinator.updateForm(form, pulse: lockPulse, showsCode: showsCode,
                                       helixEntryDistance: helixEntryDistance)
        context.coordinator.updateMatch(match)
        view.isPaused = reduceMotion || !isActive
        view.enableSetNeedsDisplay = reduceMotion && isActive
        if view.enableSetNeedsDisplay { view.setNeedsDisplay() }
    }

    static func dismantleUIView(_ view: MTKView, coordinator: WelcomeLightMetalRenderer) {
        view.isPaused = true
        view.delegate = nil
    }
}

/// SIMD vectors keep Swift/Metal uniform alignment explicit.
struct WelcomeLightUniforms {
    var shape: SIMD4<Float>
    var projection: SIMD4<Float>
    var viewport: SIMD4<Float>
    var space: SIMD4<Float>
    var calibration: SIMD4<Float>
    var entrance: SIMD4<Float>
    var stream: SIMD4<Float>
    var lock: SIMD4<Float> = .zero
    var code: SIMD4<Float> = SIMD4(0, Float(WelcomeLightCode.size), 0, 0)
    var helixArrival: SIMD4<Float> = .zero
    var match: SIMD4<Float> = .zero
    var matchLayout: SIMD4<Float> = .zero

    init(elapsed: Double, size: CGSize, pixelScale: Float, flowElapsed: Double? = nil) {
        let frame = WelcomeLightGeometry.Frame(elapsed: elapsed, flowElapsed: flowElapsed)
        shape = SIMD4(Float(frame.deformationClock), Float(frame.heart), Float(frame.separation), Float(WelcomeLightMotionClock.time(flowElapsed ?? elapsed)))
        projection = SIMD4(Float(frame.radius.width), Float(frame.radius.height), Float(frame.rotationCos), Float(frame.rotationSin))
        viewport = SIMD4(Float(size.width), Float(size.height), Float(min(size.width, size.height)) * 0.42, pixelScale)
        space = SIMD4(Float(frame.volume), Float(frame.drift.x), Float(frame.drift.y), 0)
        calibration = SIMD4(Float(frame.screenScale.width), Float(frame.screenScale.height), 0, 0)
        entrance = SIMD4(2, 0, 0, 1)
        stream = SIMD4(0, 0, -10, Float(WelcomeLightGeometry.entranceStartU))
    }

    init(presentationElapsed: Double, size: CGSize, pixelScale: Float, reduceMotion: Bool = false) {
        let state = WelcomeLightEntrance.Frame(elapsed: presentationElapsed, reduceMotion: reduceMotion)
        self.init(elapsed: state.loopElapsed, size: size, pixelScale: pixelScale, flowElapsed: state.flowElapsed)
        entrance = SIMD4(Float(state.reveal), Float(state.inletOpacity), Float(state.headGlow), Float(state.dustOpacity))
        stream = SIMD4(Float(state.reveal), Float(state.streamStrength), Float(state.reveal-1), Float(WelcomeLightGeometry.entranceStartU))
    }

    mutating func apply(_ pose: WelcomeLightLock.Pose) {
        lock = SIMD4(Float(pose.amount), Float(pose.lift), Float(pose.shake), pose.isHelix ? 1 : 0)
        code.x = Float(pose.code)
    }

    mutating func apply(_ arrival: WelcomeLightHelix.Arrival) {
        helixArrival = SIMD4(Float(arrival.travel), Float(arrival.turn), Float(1 - arrival.rungs),
                             Float(arrival.reach * arrival.side))
    }

    mutating func apply(_ pose: WelcomeLightMatch.Pose, layout: WelcomeLightMatch.Layout) {
        match = SIMD4(Float(pose.exit), Float(pose.head), Float(pose.tail), Float(pose.breakAmount))
        matchLayout = SIMD4(Float(layout.scale), Float(layout.offsetY), Float(layout.lineY), 1)
    }
}

final class WelcomeLightMetalResources {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let ribbons: MTLRenderPipelineState
    let particles: MTLRenderPipelineState
    let controls: MTLBuffer
    let compositor: MTLRenderPipelineState
    let inlet: MTLRenderPipelineState
    let travel: MTLBuffer
    let codeModules: MTLBuffer

    init(device: MTLDevice, library: MTLLibrary) throws {
        self.device = device
        guard let queue = device.makeCommandQueue(),
              let controls = device.makeBuffer(
                bytes: WelcomeLightGeometry.heartControlPoints,
                length: MemoryLayout<SIMD2<Float>>.stride * WelcomeLightGeometry.heartControlPoints.count,
                options: .storageModeShared
              ),
              let travel = device.makeBuffer(
                bytes: WelcomeLightGeometry.heartTravel + WelcomeLightEntrance.inletTravel,
                length: MemoryLayout<Float>.stride * (WelcomeLightGeometry.heartTravel.count + WelcomeLightEntrance.inletTravel.count),
                options: .storageModeShared
              ),
              let codeModules = device.makeBuffer(
                bytes: WelcomeLightCode.modules.isEmpty ? [0] : WelcomeLightCode.modules,
                length: max(1, WelcomeLightCode.modules.count),
                options: .storageModeShared
              ) else { throw RendererError.unavailable }
        self.queue = queue
        self.codeModules = codeModules
        self.controls = controls
        self.travel = travel
        func pipeline(vertex: String, fragment: String, composite: Bool = false) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: vertex)
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            let color = descriptor.colorAttachments[0]!
            color.pixelFormat = composite ? .bgra8Unorm : .rgba16Float
            color.isBlendingEnabled = !composite
            color.sourceRGBBlendFactor = .one
            color.destinationRGBBlendFactor = .one
            color.sourceAlphaBlendFactor = .one
            color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
        ribbons = try pipeline(vertex: "welcomeRibbonVertex", fragment: "welcomeRibbonFragment")
        inlet = try pipeline(vertex: "welcomeEntranceVertex", fragment: "welcomeRibbonFragment")
        particles = try pipeline(vertex: "welcomeDustVertex", fragment: "welcomeDustFragment")
        compositor = try pipeline(vertex: "welcomeCompositeVertex", fragment: "welcomeCompositeFragment", composite: true)
    }

    func encode(in encoder: MTLRenderCommandEncoder, uniforms: inout WelcomeLightUniforms) {
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<WelcomeLightUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<WelcomeLightUniforms>.stride, index: 0)
        encoder.setVertexBuffer(controls, offset: 0, index: 1)
        encoder.setVertexBuffer(travel, offset: 0, index: 2)
        encoder.setFragmentBuffer(codeModules, offset: 0, index: 1)
        encoder.setRenderPipelineState(particles)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: 190)
        if uniforms.entrance.y > 0.0001 {
            encoder.setRenderPipelineState(inlet)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: (128+1)*2,
                                   instanceCount: WelcomeLightGeometry.strandCount*2)
        }
        encoder.setRenderPipelineState(ribbons)
        encoder.drawPrimitives(
            type: .triangleStrip, vertexStart: 0,
            vertexCount: (WelcomeLightGeometry.sampleCount + 1) * 2,
            instanceCount: WelcomeLightGeometry.strandCount * 2
        )
    }

    func emissionTexture(size: CGSize) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: max(1, Int(size.width)),
            height: max(1, Int(size.height)), mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget, .shaderRead]
        return device.makeTexture(descriptor: descriptor)
    }

    func render(command: MTLCommandBuffer, target: MTLRenderPassDescriptor, emission: MTLTexture, uniforms: inout WelcomeLightUniforms) {
        let lights = MTLRenderPassDescriptor()
        lights.colorAttachments[0].texture = emission
        lights.colorAttachments[0].loadAction = .clear
        lights.colorAttachments[0].storeAction = .store
        lights.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        guard let lightEncoder = command.makeRenderCommandEncoder(descriptor: lights) else { return }
        encode(in: lightEncoder, uniforms: &uniforms)
        lightEncoder.endEncoding()
        guard let finalEncoder = command.makeRenderCommandEncoder(descriptor: target) else { return }
        finalEncoder.setRenderPipelineState(compositor)
        finalEncoder.setFragmentTexture(emission, index: 0)
        finalEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<WelcomeLightUniforms>.stride, index: 0)
        finalEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        finalEncoder.endEncoding()
    }

    enum RendererError: Error { case unavailable }
}

final class WelcomeLightMetalRenderer: NSObject, MTKViewDelegate {
    static let resources: WelcomeLightMetalResources? = {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        do {
            let library = try device.makeLibrary(source: WelcomeLightShaderSource.code, options: nil)
            return try WelcomeLightMetalResources(device: device, library: library)
        } catch {
            #if DEBUG
            print("Welcome light renderer could not initialize: \(error)")
            #endif
            return nil
        }
    }()

    private var reduceMotion = false
    private var emission: MTLTexture?
    private var presentationElapsed = 0.0
    private var lastDrawTime: Double?
    private var lockMotion = WelcomeLightLock.Motion()
    private var currentForm: WelcomeLightForm?
    private var helixStartedAt = 0.0
    private var helixEntryDistance = 0.0
    private var match: WelcomeLightMatch.Request?
    private var matchStartedAt = 0.0

    init(skipsEntrance: Bool = false) {
        presentationElapsed = skipsEntrance ? WelcomeLightEntrance.duration + 1 : 0
        super.init()
    }

    func update(reduceMotion: Bool, isActive: Bool) {
        if reduceMotion != self.reduceMotion || !isActive { lastDrawTime = nil }
        self.reduceMotion = reduceMotion
    }

    func updateForm(_ form: WelcomeLightForm, pulse: Int, showsCode: Bool, helixEntryDistance: Double = 0) {
        if form != currentForm {
            if form == .helix { helixStartedAt = presentationElapsed }
            currentForm = form
        }
        self.helixEntryDistance = helixEntryDistance
        let now = ProcessInfo.processInfo.systemUptime
        lockMotion.update(form: form, pulse: pulse, now: now, animated: !reduceMotion)
        lockMotion.update(showsCode: showsCode && form == .helix, now: now, animated: !reduceMotion)
    }

    /// A new match starts on this clock. Ending one brings the helix back in
    /// from the sides, as on arrival.
    func updateMatch(_ request: WelcomeLightMatch.Request?) {
        guard request != match else { return }
        if let request, request.id != match?.id { matchStartedAt = presentationElapsed }
        if request == nil, match != nil { helixStartedAt = presentationElapsed }
        match = request
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        if view.isPaused && view.enableSetNeedsDisplay { view.setNeedsDisplay() }
    }

    func draw(in view: MTKView) {
        guard let resources = Self.resources,
              view.drawableSize.width > 0, view.drawableSize.height > 0,
              let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let command = resources.queue.makeCommandBuffer()
        else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if !reduceMotion, let previous = lastDrawTime {
            presentationElapsed += max(0, now-previous)
        }
        lastDrawTime = reduceMotion ? nil : now
        var uniforms = WelcomeLightUniforms(
            presentationElapsed: presentationElapsed, size: view.drawableSize,
            pixelScale: Float(view.drawableSize.width / max(view.bounds.width, 1)), reduceMotion: reduceMotion
        )
        uniforms.apply(lockMotion.pose(at: now))
        if currentForm == .helix, helixEntryDistance > 0 {
            uniforms.apply(WelcomeLightHelix.Arrival(
                elapsed: presentationElapsed - helixStartedAt,
                distance: helixEntryDistance,
                startSeconds: WelcomeLightHelix.Arrival.motionSeconds(atPresentation: helixStartedAt, reduceMotion: reduceMotion),
                reduceMotion: reduceMotion))
        }
        if let match {
            uniforms.apply(WelcomeLightMatch.pose(elapsed: presentationElapsed - matchStartedAt,
                                                  isMatch: match.isMatch, reduceMotion: reduceMotion),
                           layout: .of(isMatch: match.isMatch))
        }
        if emission?.width != Int(view.drawableSize.width) || emission?.height != Int(view.drawableSize.height) {
            emission = resources.emissionTexture(size: view.drawableSize)
        }
        guard let emission else { return }
        resources.render(command: command, target: descriptor, emission: emission, uniforms: &uniforms)
        command.present(drawable)
        command.commit()
    }
}
