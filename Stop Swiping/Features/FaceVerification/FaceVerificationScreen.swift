import SwiftUI

/// Pure presentation shared by the live screen and rendered UI checks.
struct FaceVerificationScreen<CameraContent: View>: View {
    let snapshot: FaceScanSnapshot
    let outcome: FaceVerificationOutcome?
    let needsCameraPermission: Bool
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onSettings: () -> Void
    let onDone: () -> Void
    @ViewBuilder let cameraContent: () -> CameraContent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isMatched: Bool { outcome == .match }
    var body: some View {
        GeometryReader { geometry in
            let resultSpace: CGFloat = outcome == nil ? 0 : isMatched ? 90 : 140
            let diameter = min(geometry.size.width - 64, 340,
                               max(160, geometry.size.height - 200 - resultSpace))
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 28) {
                        scanCircle
                            .frame(width: diameter, height: diameter)
                        status
                    }
                    .frame(maxWidth: OnboardingTheme.contentWidth)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .frame(minHeight: max(0, geometry.size.height - 64 - resultSpace), alignment: .center)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                if outcome != nil { footer }
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
            Label(L10n("Verify photo"), systemImage: "checkmark.shield")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(OnboardingTheme.secondaryText)
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.white.opacity(0.08)))
                    .overlay(Circle().strokeBorder(OnboardingTheme.hairline, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n("Cancel verification"))
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private var scanCircle: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle()
                    .fill(OnboardingTheme.blue.opacity(0.08))
                    .padding(14)
                    .blur(radius: 20)
                Group {
                    if let outcome {
                        Circle().fill(.white.opacity(0.035))
                            .overlay {
                                Image(systemName: outcome == .match ? "checkmark.shield.fill" : "arrow.clockwise")
                                    .font(.system(size: 58, weight: .light))
                                    .foregroundStyle(outcome == .match ? OnboardingTheme.cyan : OnboardingTheme.pink)
                            }
                    } else {
                        cameraContent()
                            .frame(width: size - 50, height: size - 50)
                            .clipped()
                    }
                }
                .frame(width: size - 50, height: size - 50)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                .accessibilityLabel(L10n("Live front camera preview"))

                FaceScanRing(snapshot: snapshot, isMatched: isMatched)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: snapshot.collectedSectors)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n("Head movement captured"))
                    .accessibilityValue(L10n("\(Int(snapshot.progress * 100)) percent"))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private var status: some View {
        VStack(spacing: 10) {
            Text(outcome?.title ?? snapshot.instruction)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(OnboardingTheme.primaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let outcome, outcome != .match {
                Text(outcome.message)
                    .font(.subheadline)
                    .foregroundStyle(OnboardingTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else if outcome == nil, snapshot.phase == .circling {
                Text("\(Int((snapshot.progress * 100).rounded()))%")
                    .font(.system(size: 14, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(OnboardingTheme.secondaryText)
                    .accessibilityLabel(L10n("\(Int((snapshot.progress * 100).rounded())) percent captured"))
            }
        }
        .frame(maxWidth: 310)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if outcome != nil {
                Button(isMatched ? L10n("Continue") : needsCameraPermission ? L10n("Open Settings") : L10n("Try again"),
                       action: isMatched ? onDone : needsCameraPermission ? onSettings : onRetry)
                    .buttonStyle(GlowButtonStyle())
                if !isMatched {
                    Button(needsCameraPermission ? L10n("Try again") : L10n("Back"),
                           action: needsCameraPermission ? onRetry : onDone)
                        .buttonStyle(QuietButtonStyle())
                }
            }
        }
        .frame(maxWidth: OnboardingTheme.controlWidth)
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
    }
}

struct FaceScanRing: View {
    let snapshot: FaceScanSnapshot
    let isMatched: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var guideAngle = 0.0

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height)
            let radius = diameter / 2 - 18
            ZStack {
                ForEach(0..<40, id: \.self) { index in
                    let sector = Int((Double(index) / 5).rounded()) % FaceCircleChallenge.sectorCount
                    let filled = isMatched || snapshot.collectedSectors.contains(sector)
                    let targeted = snapshot.targetSector == sector
                    Capsule()
                        .fill(filled ? OnboardingTheme.cyan : targeted ? OnboardingTheme.violet : .white.opacity(0.15))
                        .frame(width: filled || targeted ? 4 : 3, height: filled || targeted ? 15 : 11)
                        .shadow(color: filled ? OnboardingTheme.cyan.opacity(0.45) : .clear, radius: 8)
                        .offset(y: -radius)
                        .rotationEffect(.degrees(Double(index) * 9))
                }
                if snapshot.targetSector != nil, !isMatched {
                    ZStack {
                        Circle().fill(OnboardingTheme.violet.opacity(0.22)).frame(width: 48, height: 48)
                        Circle().strokeBorder(OnboardingTheme.violet.opacity(0.65), lineWidth: 2).frame(width: 34, height: 34)
                        Circle().fill(.white).frame(width: 24, height: 24)
                    }
                    .shadow(color: OnboardingTheme.violet.opacity(0.65), radius: 10)
                    // Animate the angle, not x/y: the ball follows the rim
                    // along an arc instead of taking a shortcut across it.
                    .offset(y: -radius)
                    .rotationEffect(.radians(guideAngle))
                }
                if let cursor = snapshot.cursor, snapshot.phase == .circling {
                    let point = FaceCircleChallenge.visualCursor(for: cursor)
                    Circle()
                        .fill(OnboardingTheme.cyan)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                        .shadow(color: OnboardingTheme.cyan.opacity(0.8), radius: 5)
                        .offset(x: point.x * radius, y: point.y * radius)
                        .animation(reduceMotion ? nil : .linear(duration: 0.1), value: point)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityHidden(true)
        .onAppear {
            setInitialGuideAngle(snapshot.targetSector)
        }
        .onChange(of: snapshot.targetSector) { previous, target in
            guard let target else { return }
            guard let previous else {
                setInitialGuideAngle(target)
                return
            }
            let count = FaceCircleChallenge.sectorCount
            // Keep the angle unwrapped, including 7 → 0 and 0 → 7, so it
            // always continues in the requested direction without a full spin.
            let steps = snapshot.clockwise
                ? (target - previous + count) % count
                : -((previous - target + count) % count)
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.5)) {
                guideAngle += Double(steps) * 2 * .pi / Double(count)
            }
        }
    }

    private func setInitialGuideAngle(_ sector: Int?) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            guideAngle = Double(sector ?? 0) * 2 * .pi / Double(FaceCircleChallenge.sectorCount)
        }
    }
}
