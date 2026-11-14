import SwiftUI

/// Live light filaments, drawn without video or image sequences.
struct WelcomeLightAnimation: View {
    /// Reweaves the heart into a padlock or a double helix. Purely visual;
    /// access rules live in the profile-creation model.
    var form = WelcomeLightForm.heart
    /// Each change gives the lock a small tug.
    var lockPulse = 0
    /// Rewinds the helix into a QR code. Drawn by the Metal renderer only.
    var showsCode = false
    /// The code the helix turns into.
    var code: WelcomeLightCode.Matrix?
    /// Opens on the finished light instead of drawing it in.
    var skipsEntrance = false
    /// Stops drawing while something covers the light.
    var isPaused = false
    /// Ambient light behind a form can draw less often than the main artwork.
    var framesPerSecond = 60
    /// Entrance travel in the same normalized space as the helix geometry.
    var helixEntryDistance = 0.0
    /// Turns the helix into the match heart. Drawn by the Metal renderer only.
    var match: WelcomeLightMatch.Request?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var startDate = Date()
    @State private var pausedAt: Date?
    @State private var lockMotion = WelcomeLightLock.Motion()
    @State private var helixStartedAt = 0.0

    var body: some View {
        Group {
            if WelcomeLightMetalView.isAvailable {
                WelcomeLightMetalView(reduceMotion: reduceMotion, isActive: isRunning,
                                      form: form, lockPulse: lockPulse, showsCode: showsCode,
                                      skipsEntrance: skipsEntrance, framesPerSecond: framesPerSecond,
                                      helixEntryDistance: helixEntryDistance, match: match, code: code)
            } else {
                TimelineView(.animation(
                    minimumInterval: 1.0 / Double(framesPerSecond),
                    paused: reduceMotion || !isRunning
                )) { timeline in
                    Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                        let entrance = WelcomeLightEntrance.Frame(
                            elapsed: timeline.date.timeIntervalSince(startDate), reduceMotion: reduceMotion)
                        let lock = lockMotion.pose(at: timeline.date.timeIntervalSinceReferenceDate)
                        let arrival = form == .helix && helixEntryDistance > 0
                            ? WelcomeLightHelix.Arrival(
                                elapsed: timeline.date.timeIntervalSince(startDate) - helixStartedAt,
                                distance: helixEntryDistance,
                                startSeconds: WelcomeLightHelix.Arrival.motionSeconds(
                                    atPresentation: helixStartedAt, reduceMotion: reduceMotion),
                                reduceMotion: reduceMotion)
                            : .settled
                        WelcomeLightRenderer.draw(in: &context, size: size, entrance: entrance,
                                                  lock: lock, arrival: arrival)
                    }
                }
                .onChange(of: FormInput(form: form, pulse: lockPulse), initial: true) { _, input in
                    if input.form == .helix && !lockMotion.pose(at: Date().timeIntervalSinceReferenceDate).isHelix {
                        helixStartedAt = Date().timeIntervalSince(startDate)
                    }
                    lockMotion.update(form: input.form, pulse: input.pulse,
                                      now: Date().timeIntervalSinceReferenceDate, animated: !reduceMotion)
                }
            }
        }
        .background {
            // The atmosphere is static and independent of the animation clock.
            GeometryReader { proxy in
                RadialGradient(
                    stops: [
                        .init(color: Color(red: 0.018, green: 0.035, blue: 0.32).opacity(0.85), location: 0),
                        .init(color: Color(red: 0.012, green: 0.025, blue: 0.24).opacity(0.65), location: 0.5),
                        .init(color: .clear, location: 1)
                    ],
                    center: .center, startRadius: 0,
                    endRadius: min(proxy.size.width, proxy.size.height) / 2
                )
            }
        }
        .onAppear {
            if skipsEntrance { startDate = Date().addingTimeInterval(-WelcomeLightEntrance.duration - 1) }
            if form == .helix { helixStartedAt = Date().timeIntervalSince(startDate) }
        }
        .onChange(of: reduceMotion || !isRunning, initial: true) { _, paused in
            if paused {
                if pausedAt == nil { pausedAt = Date() }
            } else if let pause = pausedAt {
                startDate = startDate.addingTimeInterval(Date().timeIntervalSince(pause))
                pausedAt = nil
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var isRunning: Bool { scenePhase == .active && !isPaused }

    private struct FormInput: Equatable {
        let form: WelcomeLightForm
        let pulse: Int
    }
}

private enum WelcomeLightRenderer {
    static let cyan = Color(red: 0.20, green: 0.81, blue: 1)
    static let blue = Color(red: 0.16, green: 0.32, blue: 1)
    static let violet = Color(red: 0.61, green: 0.30, blue: 1)
    static let pink = Color(red: 0.95, green: 0.35, blue: 0.85)

    private struct Filament {
        let path: Path
        let color: Color
        let highlighted: Bool
        let lightPhase: Double
        let opacity: Double
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, entrance: WelcomeLightEntrance.Frame,
                     lock: WelcomeLightLock.Pose, arrival: WelcomeLightHelix.Arrival) {
        let elapsed = entrance.loopElapsed
        let frame = WelcomeLightGeometry.Frame(elapsed: elapsed, flowElapsed: entrance.flowElapsed)
        let scale = min(size.width, size.height) * 0.43
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        context.blendMode = .plusLighter
        var dust = context
        dust.opacity *= entrance.dustOpacity
        drawDust(in: &dust, center: center, scale: scale, elapsed: entrance.flowElapsed)

        var filaments: [Filament] = []
        for ring in 0..<2 {
            let contour = WelcomeLightGeometry.contour(ring: ring, frame: frame)
            for strand in 0..<WelcomeLightGeometry.strandCount {
                let filament = Double(strand) / Double(WelcomeLightGeometry.strandCount)
                let sheet = strand / 20
                let lane = strand % 20
                let localPoints = contour.map { sample in
                    let heart = WelcomeLightGeometry.point(on: sample, ring: ring, filament: filament, frame: frame, transport: entrance.reveal, streamStrength: entrance.streamStrength)
                    guard lock.amount > 0 else { return heart }
                    let u = sample.angle / WelcomeLightGeometry.tau
                    let k = WelcomeLightLock.strandAmount(lock.amount, u: u, instance: ring * WelcomeLightGeometry.strandCount + strand)
                    let seconds = WelcomeLightMotionClock.time(entrance.flowElapsed)
                    let locked = lock.isHelix
                        ? WelcomeLightHelix.point(u: u, ring: ring, strand: strand, seconds: seconds, arrival: arrival).point
                        : WelcomeLightLock.point(u: u, ring: ring, strand: strand, seconds: seconds, pose: lock)
                    return CGPoint(x: heart.x + (locked.x - heart.x) * k, y: heart.y + (locked.y - heart.y) * k)
                }
                let ordered = Array(localPoints.dropFirst(WelcomeLightGeometry.entranceStartSample)) + Array(localPoints.prefix(WelcomeLightGeometry.entranceStartSample))
                let points = ordered.map { screenPoint($0, center: center, scale: scale) }
                let heartPath = smoothClosedPath(points)
                if entrance.reveal > 0 {
                    filaments.append(Filament(
                        path: entrance.reveal >= 1 ? heartPath : heartPath.trimmedPath(from: 0, to: entrance.reveal),
                        color: strandColor(filament: filament, ring: ring),
                        highlighted: lane == 5 && sheet != 1,
                        lightPhase: Double(sheet) * 1.9 + Double(ring) * 0.8 + Double(lane) * 0.035,
                        opacity: sheet == 0 ? 0.54 : 0.40
                    ))
                }
                if entrance.inletOpacity > 0.0001 {
                    let tip = ordered[0]
                    let tangent = CGVector(dx: ordered[1].x-ordered[ordered.count-1].x,
                                           dy: ordered[1].y-ordered[ordered.count-1].y)
                    var path = Path()
                    for index in 0...128 {
                        let point = WelcomeLightEntrance.inletPoint(Double(index)/128, tip: tip, tangent: tangent,
                                                                    strand: ring*WelcomeLightGeometry.strandCount+strand, transport: entrance.reveal)
                        let screen = screenPoint(point, center: center, scale: scale)
                        if index == 0 { path.move(to: screen) } else { path.addLine(to: screen) }
                    }
                    let reveal = min(max((entrance.reveal+WelcomeLightEntrance.inletLength)/WelcomeLightEntrance.inletLength, 0), 1)
                    filaments.append(Filament(
                        path: path.trimmedPath(
                            from: min(max((entrance.reveal-1+WelcomeLightEntrance.inletLength)/WelcomeLightEntrance.inletLength,0),1),
                            to: reveal), color: strandColor(filament: filament, ring: ring),
                        highlighted: lane == 5 && sheet != 1,
                        lightPhase: Double(sheet)*1.9+Double(ring)*0.8+Double(lane)*0.035,
                        opacity: (sheet == 0 ? 0.54 : 0.40)*entrance.inletOpacity))
                }
            }
        }

        // A diffuse blue veil under the fine threads gives the bundles depth.
        // All glow passes are shared, keeping the number of offscreen layers low.
        context.drawLayer { glow in
            glow.addFilter(.blur(radius: 9))
            for filament in filaments {
                glow.stroke(filament.path, with: .color(filament.color.opacity(0.04)), lineWidth: 2.2)
            }
        }
        context.drawLayer { glow in
            glow.addFilter(.blur(radius: 2.2))
            for filament in filaments where filament.highlighted {
                glow.stroke(filament.path, with: light(on: filament, center: center, clock: frame.clock, opacity: filament.opacity*0.9), lineWidth: 2.5)
            }
        }
        for filament in filaments {
            context.stroke(
                filament.path,
                with: light(on: filament, center: center, clock: frame.clock, opacity: filament.highlighted ? filament.opacity*1.5 : filament.opacity),
                style: StrokeStyle(lineWidth: filament.highlighted ? 0.75 : 0.34, lineCap: .round, lineJoin: .round)
            )
        }
        if entrance.reveal >= 1 {
            var sparks = context
            sparks.opacity *= 1-entrance.headGlow
            drawSparks(in: &sparks, center: center, scale: scale, frame: frame)
        }
    }

    /// Periodic cubic interpolation keeps tangents continuous at every join,
    /// including the closing segment at the top of each ring/heart.
    private static func smoothClosedPath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        let count = points.count
        path.move(to: first)
        for index in 0..<count {
            let previous = points[(index + count - 1) % count]
            let start = points[index]
            let end = points[(index + 1) % count]
            let next = points[(index + 2) % count]
            path.addCurve(
                to: end,
                control1: CGPoint(x: start.x + (end.x - previous.x) / 6, y: start.y + (end.y - previous.y) / 6),
                control2: CGPoint(x: end.x - (next.x - start.x) / 6, y: end.y - (next.y - start.y) / 6)
            )
        }
        path.closeSubpath()
        return path
    }

    /// Highlights travel along the ribbons and fade between them. A constant
    /// stroke color made the old animation read as a rigid neon outline.
    private static func light(on filament: Filament, center: CGPoint, clock: Double, opacity: Double) -> GraphicsContext.Shading {
        let color = filament.color
        return .conicGradient(
            Gradient(stops: [
                .init(color: color.opacity(opacity * 0.14), location: 0),
                .init(color: color.opacity(opacity * 0.40), location: 0.17),
                .init(color: color.opacity(opacity), location: 0.30),
                .init(color: Color(red: 0.55, green: 0.84, blue: 1).opacity(opacity), location: 0.36),
                .init(color: color.opacity(opacity * 0.48), location: 0.46),
                .init(color: color.opacity(opacity * 0.18), location: 0.64),
                .init(color: color.opacity(opacity * 0.72), location: 0.82),
                .init(color: color.opacity(opacity * 0.14), location: 1)
            ]),
            center: center, angle: .radians(-2 * clock + filament.lightPhase)
        )
    }

    private static func strandColor(filament: Double, ring: Int) -> Color {
        let sheet = min(Int(filament * 3), 2)
        switch sheet {
        case 0: return cyan
        case 1: return ring == 0 ? blue : Color(red: 0.32, green: 0.55, blue: 1)
        default: return ring == 0 ? violet : pink
        }
    }

    private static func drawDust(in context: inout GraphicsContext, center: CGPoint, scale: Double, elapsed: Double) {
        for index in 0..<160 {
            let particle = WelcomeLightGeometry.particle(index: index, elapsed: elapsed)
            let position = screenPoint(particle.position, center: center, scale: scale)
            let rect = CGRect(x: position.x, y: position.y, width: particle.diameter, height: particle.diameter)
            context.fill(Path(ellipseIn: rect), with: .color(
                (index % 9 == 0 ? cyan : blue).opacity(particle.opacity)
            ))
        }
    }

    private static func drawSparks(
        in context: inout GraphicsContext, center: CGPoint, scale: Double,
        frame: WelcomeLightGeometry.Frame
    ) {
        for ring in 0..<2 {
            let contour = WelcomeLightGeometry.contour(ring: ring, frame: frame)
            // Each spark follows a continuous interpolated position on the ribbon.
            for index in 0..<9 {
                let seed = Double(index) * 2.399963 + Double(ring) * 0.73
                let travel = (seed + frame.clock / WelcomeLightGeometry.tau * 2) * Double(contour.count)
                let shimmer = pow(0.5 + 0.5 * sin(frame.clock * 3 + seed), 3)
                let wrapped = travel - floor(travel / Double(contour.count)) * Double(contour.count)
                let sampleIndex = Int(wrapped)
                let fraction = wrapped - Double(sampleIndex)
                let a = WelcomeLightGeometry.point(on: contour[sampleIndex], ring: ring, filament: 0.5, frame: frame)
                let b = WelcomeLightGeometry.point(on: contour[(sampleIndex + 1) % contour.count], ring: ring, filament: 0.5, frame: frame)
                let location = screenPoint(CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction), center: center, scale: scale)
                context.fill(
                    Path(ellipseIn: CGRect(x: location.x - 3, y: location.y - 3, width: 6, height: 6)),
                    with: .radialGradient(Gradient(colors: [cyan.opacity(0.25 + shimmer * 0.4), .clear]), center: location, startRadius: 0, endRadius: 3)
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: location.x - 0.5, y: location.y - 0.5, width: 1, height: 1)),
                    with: .color(.white.opacity(0.20 + shimmer * 0.6))
                )
            }
        }
    }

    private static func screenPoint(_ point: CGPoint, center: CGPoint, scale: Double) -> CGPoint {
        CGPoint(x: center.x + point.x * scale, y: center.y + point.y * scale)
    }
}
