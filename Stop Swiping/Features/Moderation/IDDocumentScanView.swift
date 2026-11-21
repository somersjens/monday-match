import AVFoundation
import Combine
import SwiftUI
import UIKit

/// How far a live document scan is.
enum IDDocumentScanPhase: Equatable {
    case preparing
    /// No zone in view yet.
    case searching
    /// Lines of `<<<` are in view but don't read cleanly yet.
    case holdStill
}

enum IDDocumentScanOutcome: Equatable {
    case read(MachineReadableZone)
    case failed(String)

    var isRead: Bool {
        if case .read = self { return true }
        return false
    }
}

@MainActor
final class IDDocumentScanViewModel: ObservableObject {
    @Published private(set) var camera: IDDocumentCamera?
    @Published private(set) var phase = IDDocumentScanPhase.preparing
    @Published private(set) var outcome: IDDocumentScanOutcome?
    @Published private(set) var needsCameraPermission = false

    /// Long enough for a careful try; after that, a tip helps more than waiting.
    static let timeout: Duration = .seconds(60)

    private var reader = MachineReadableZoneReader()
    private var lastZoneLineSeen: ContinuousClock.Instant?
    private var startTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var generation = UUID()

    func start() {
        stop()
        outcome = nil
        phase = .preparing
        needsCameraPermission = false
        reader = MachineReadableZoneReader()
        lastZoneLineSeen = nil
        let token = generation
        startTask = Task { [weak self] in
            let authorized: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: authorized = true
            case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
            default: authorized = false
            }
            guard !Task.isCancelled, let self, token == self.generation else { return }
            guard authorized else {
                self.needsCameraPermission = AVCaptureDevice.authorizationStatus(for: .video) == .denied
                self.outcome = .failed(L10n("Camera access is required to scan your document. Allow camera access in Settings, then try again."))
                return
            }
            let camera = IDDocumentCamera(frameAspect: IDDocumentScanScreen<EmptyView>.frameAspect) { [weak self] update in
                Task { @MainActor [weak self] in
                    guard let self, token == self.generation, self.outcome == nil else { return }
                    switch update {
                    case .lines(let lines): self.observe(lines)
                    case .failed(let message): self.finish(.failed(message))
                    }
                }
            }
            self.camera = camera
            self.phase = .searching
            camera.start()
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: Self.timeout)
                guard !Task.isCancelled, let self, token == self.generation, self.outcome == nil else { return }
                self.finish(.failed(L10n("The lines of <<< couldn’t be read. Make sure they’re sharp, well lit and free of glare, then try again.")))
            }
        }
    }

    /// One frame's lines. "Hold still" stays a moment after the zone was
    /// last seen, so the text doesn't flicker between frames.
    func observe(_ lines: [String]) {
        guard outcome == nil else { return }
        if let zone = reader.observe(lines: lines) {
            finish(.read(zone))
            return
        }
        let now = ContinuousClock.now
        if lines.filter(MachineReadableZone.looksLikeZoneLine).count >= 2 { lastZoneLineSeen = now }
        let recent = lastZoneLineSeen.map { now - $0 < .seconds(1.2) } ?? false
        phase = recent ? .holdStill : .searching
    }

    func interrupt() {
        guard outcome == nil else { return }
        finish(.failed(L10n("The camera was interrupted. Please try again.")))
    }

    func stop() {
        generation = UUID()
        startTask?.cancel()
        startTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        camera?.stop()
        camera = nil
    }

    private func finish(_ outcome: IDDocumentScanOutcome) {
        stop()
        self.outcome = outcome
    }
}

/// Scans the machine-readable zone of a passport or ID card live, like the
/// photo check scans a face: no photo to take, the camera reads until two
/// frames agree. Only the read zone leaves this screen.
struct IDDocumentScanView: View {
    let onRead: (MachineReadableZone) -> Void

    @StateObject private var viewModel = IDDocumentScanViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasCompleted = false

    var body: some View {
        IDDocumentScanScreen(
            phase: viewModel.phase,
            outcome: viewModel.outcome,
            needsCameraPermission: viewModel.needsCameraPermission,
            onCancel: close,
            onRetry: { viewModel.start() },
            onSettings: {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        ) {
            if let camera = viewModel.camera {
                CameraPreview(session: camera.session, mirrored: false)
            } else {
                Color.black.opacity(0.35)
            }
        }
        .interactiveDismissDisabled()
        .sensoryFeedback(.selection, trigger: viewModel.phase) { _, phase in phase == .holdStill }
        .sensoryFeedback(trigger: viewModel.outcome) { _, outcome in
            switch outcome {
            case .read: .success
            case .failed: .warning
            case nil: nil
            }
        }
        .soundFeedback(trigger: viewModel.outcome) { _, outcome in
            switch outcome {
            case .read: .seal
            case .failed: .rejection
            case nil: nil
            }
        }
        .task { viewModel.start() }
        // Read: the seal lands with its sound, then the scan closes by itself.
        .task(id: viewModel.outcome) {
            guard case .read(let zone) = viewModel.outcome else { return }
            try? await Task.sleep(for: .milliseconds(1300))
            guard !Task.isCancelled, !hasCompleted else { return }
            hasCompleted = true
            onRead(zone)
            dismiss()
        }
        .onDisappear { viewModel.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || (phase == .inactive && viewModel.camera != nil) { viewModel.interrupt() }
        }
    }

    private func close() {
        guard !hasCompleted else { return }
        hasCompleted = true
        // A document already read counts, even when closed before it moves on.
        if case .read(let zone) = viewModel.outcome { onRead(zone) }
        viewModel.stop()
        dismiss()
    }
}

/// Pure presentation, shared by the live screen and rendered UI checks. The
/// frame is shaped like a card held across the phone; the corners light up
/// violet once lines of `<<<` are in view and cyan once they are read.
struct IDDocumentScanScreen<CameraContent: View>: View {
    let phase: IDDocumentScanPhase
    let outcome: IDDocumentScanOutcome?
    let needsCameraPermission: Bool
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onSettings: () -> Void
    @ViewBuilder let cameraContent: () -> CameraContent

    /// Between an ID card (1.59) and a passport's photo page (1.42).
    static var frameAspect: CGFloat { 1.5 }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isFailed: Bool { outcome != nil && outcome?.isRead == false }

    var body: some View {
        GeometryReader { geometry in
            let resultSpace: CGFloat = isFailed ? 140 : 0
            let width = max(0, min(geometry.size.width - 56, 460,
                                   max(200, geometry.size.height - 260 - resultSpace) * Self.frameAspect))
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 32) {
                        scanFrame
                            .frame(width: width, height: width / Self.frameAspect)
                        status
                    }
                    .frame(maxWidth: OnboardingTheme.contentWidth)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
                    .frame(minHeight: max(0, geometry.size.height - 64 - resultSpace), alignment: .center)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                if isFailed { footer }
            }
        }
        .background {
            ZStack {
                OnboardingTheme.background
                RadialGradient(colors: [OnboardingTheme.blue.opacity(0.17), .clear],
                               center: .init(x: 0.5, y: 0.38), startRadius: 15, endRadius: 320)
                RadialGradient(colors: [OnboardingTheme.violet.opacity(0.08), .clear],
                               center: .bottomLeading, startRadius: 0, endRadius: 260)
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        HStack {
            Spacer()
            BrandCrossButton(accessibilityLabel: L10n("Cancel scan"), action: onCancel)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private var cornerColor: Color {
        if outcome?.isRead == true { return OnboardingTheme.cyan }
        if isFailed { return OnboardingTheme.pink.opacity(0.7) }
        return phase == .holdStill ? OnboardingTheme.violet : .white.opacity(0.45)
    }

    private var scanFrame: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let radius = min(size.width, size.height) * 0.09
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            ZStack {
                shape
                    .fill(OnboardingTheme.blue.opacity(0.10))
                    .padding(-12)
                    .blur(radius: 22)
                Group {
                    if let outcome {
                        shape.fill(.white.opacity(0.035))
                            .overlay {
                                if outcome.isRead {
                                    // The same seal as a verified photo.
                                    Image(systemName: "checkmark.seal.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, OnboardingTheme.cyan)
                                        .font(.system(size: 64, weight: .semibold))
                                        .shadow(color: OnboardingTheme.cyan.opacity(0.7), radius: 16)
                                        .transition(reduceMotion ? .opacity
                                                    : .scale(scale: 0.5).combined(with: .opacity))
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 50, weight: .light))
                                        .foregroundStyle(OnboardingTheme.pink)
                                }
                            }
                    } else {
                        cameraContent()
                            .frame(width: size.width, height: size.height)
                            .clipped()
                            .overlay(alignment: .bottom) { zoneGuide(size: size) }
                            .overlay { if !reduceMotion { ScanSweep() } }
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipShape(shape)
                .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 1))
                .animation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.35), value: outcome)
                .accessibilityElement()
                .accessibilityLabel(L10n("Live rear camera preview"))

                DocumentCorners(radius: radius + 8)
                    .stroke(cornerColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .shadow(color: cornerColor.opacity(outcome?.isRead == true || phase == .holdStill ? 0.7 : 0), radius: 8)
                    .padding(-8)
                    .animation(.easeInOut(duration: 0.25), value: cornerColor)
                    .accessibilityHidden(true)
            }
            .frame(width: size.width, height: size.height)
        }
    }

    /// Where the lines of `<<<` go: a quiet band along the frame's bottom.
    private func zoneGuide(size: CGSize) -> some View {
        let height = size.height * 0.3
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(.white.opacity(phase == .holdStill ? 0.0 : 0.35),
                          style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            .background {
                VStack(alignment: .leading, spacing: height * 0.12) {
                    ForEach(0..<2, id: \.self) { _ in
                        Text(verbatim: String(repeating: "<", count: 30))
                            .font(.system(size: max(9, height * 0.2), weight: .medium, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.3)
                    }
                }
                .foregroundStyle(.white.opacity(phase == .holdStill ? 0 : 0.3))
                .padding(.horizontal, 12)
            }
            .frame(height: height)
            .padding(.horizontal, size.width * 0.05)
            .padding(.bottom, size.height * 0.07)
            .animation(.easeInOut(duration: 0.25), value: phase)
            .accessibilityHidden(true)
    }

    private var title: String {
        switch outcome {
        case .read: return L10n("Document read")
        case .failed: return L10n("Couldn’t read your document")
        case nil:
            switch phase {
            case .preparing: return L10n("Preparing your camera…")
            case .searching: return L10n("Hold the lines of <<< inside the frame")
            case .holdStill: return L10n("Hold still…")
            }
        }
    }

    private var status: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(OnboardingTheme.primaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: title)
                .accessibilityAddTraits(.isHeader)
            if case .failed(let message) = outcome {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(OnboardingTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else if outcome == nil {
                Text(L10n("Only your initials and dates are sent, never the photo."))
                    .font(.subheadline)
                    .foregroundStyle(OnboardingTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 320)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button(needsCameraPermission ? L10n("Open Settings") : L10n("Try again"),
                   action: needsCameraPermission ? onSettings : onRetry)
                .buttonStyle(GlowButtonStyle())
            Button(needsCameraPermission ? L10n("Try again") : L10n("Back"),
                   action: needsCameraPermission ? onRetry : onCancel)
                .buttonStyle(QuietButtonStyle())
        }
        .frame(maxWidth: OnboardingTheme.controlWidth)
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
    }
}

/// Four rounded corner brackets around the scan frame.
private struct DocumentCorners: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let length = min(rect.width, rect.height) * 0.16
        let r = min(radius, min(rect.width, rect.height) / 4)
        var path = Path()
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY), 1, 1),
            (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
            (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
            (CGPoint(x: rect.minX, y: rect.maxY), 1, -1),
        ]
        for (corner, dx, dy) in corners {
            path.move(to: CGPoint(x: corner.x, y: corner.y + dy * (r + length)))
            path.addArc(tangent1End: corner, tangent2End: CGPoint(x: corner.x + dx * r, y: corner.y), radius: r)
            path.addLine(to: CGPoint(x: corner.x + dx * (r + length), y: corner.y))
        }
        return path
    }
}

/// A soft line sweeping up and down while the camera reads.
private struct ScanSweep: View {
    @State private var down = false

    var body: some View {
        GeometryReader { geometry in
            LinearGradient(colors: [.clear, OnboardingTheme.cyan.opacity(0.55), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 2)
                .shadow(color: OnboardingTheme.cyan.opacity(0.6), radius: 6)
                .offset(y: down ? geometry.size.height * 0.9 : geometry.size.height * 0.1)
                .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: down)
                .onAppear { down = true }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
