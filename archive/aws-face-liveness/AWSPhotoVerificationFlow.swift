import AVFoundation
import FaceLiveness
import SwiftUI

/// What the server photo check is doing, for the control that starts it.
struct AWSPhotoVerificationState: Equatable {
    var isStarting = false
    var issue: AWSPhotoVerificationIssue?
}

/// Why a check did not go through, in the person's terms: either it is on
/// our side, or this photo is not them. Server and SDK details stay out.
enum AWSPhotoVerificationIssue: Equatable {
    /// The server, AWS or the connection failed. Nothing the person did.
    case serviceUnavailable
    /// The scan ended, but did not confirm the face in this photo.
    case noMatch
    case cameraAccess

    /// `nil` when nothing went wrong from the person's view: they closed the scan.
    init?(_ error: Error) {
        if let error = error as? FaceLivenessDetectionError {
            switch error {
            case .userCancelled:
                return nil
            case .cameraPermissionDenied, .cameraNotAvailable:
                self = .cameraAccess
            case .faceInOvalMatchExceededTimeLimitError, .countdownNoFace,
                 .countdownFaceTooClose, .countdownMultipleFaces:
                self = .noMatch
            default:
                self = .serviceUnavailable
            }
        } else if case AWSPhotoVerificationError.notVerified = error {
            self = .noMatch
        } else {
            self = .serviceUnavailable
        }
    }

    var symbol: String {
        switch self {
        case .serviceUnavailable: "icloud.slash"
        case .noMatch: "person.crop.circle.badge.questionmark"
        case .cameraAccess: "camera.fill"
        }
    }

    var title: String {
        switch self {
        case .serviceUnavailable: L10n("Verification isn’t working right now")
        case .noMatch: L10n("This photo doesn’t match you")
        case .cameraAccess: L10n("Camera access needed")
        }
    }

    var message: String {
        switch self {
        case .serviceUnavailable:
            L10n("That’s on our side, not yours. Please try again in a few minutes.")
        case .noMatch:
            L10n("Choose a clear, recent photo of just you, and keep your face inside the oval during the scan.")
        case .cameraAccess:
            L10n("Allow camera access in Settings to verify your photo.")
        }
    }
}

extension View {
    /// Hosts the server photo check: the consent sheet, the live AWS scan and
    /// the server's verdict. Setting `showsConsent` starts it; a confirmed
    /// match is reported through `onComplete`.
    func awsPhotoVerification(
        photo: ProfilePhoto?,
        service: AWSPhotoVerificationService?,
        isVerified: Bool,
        showsConsent: Binding<Bool>,
        state: Binding<AWSPhotoVerificationState>,
        onComplete: @escaping (PhotoVerificationReceipt) -> Void
    ) -> some View {
        modifier(AWSPhotoVerificationFlow(photo: photo, service: service, isVerified: isVerified,
                                          showsConsent: showsConsent, state: state, onComplete: onComplete))
    }
}

private struct AWSPhotoVerificationFlow: ViewModifier {
    let photo: ProfilePhoto?
    let service: AWSPhotoVerificationService?
    let isVerified: Bool
    @Binding var showsConsent: Bool
    @Binding var state: AWSPhotoVerificationState
    let onComplete: (PhotoVerificationReceipt) -> Void

    @State private var session: AWSPhotoVerificationSession?

    func body(content: Content) -> some View {
        content
            .task(id: photo?.id) {
                // A photo the server already verified, for example after a reinstall.
                guard let photo, let service, !isVerified,
                      (try? await service.photoIsVerified()) == true else { return }
                onComplete(PhotoVerificationReceipt(photoID: photo.id, imageData: photo.imageData, outcome: .match))
            }
            .sheet(isPresented: $showsConsent) { consent }
            .fullScreenCover(item: $session) { session in
                if let service, let photo {
                    AWSPhotoScan(session: session, service: service) { result in
                        self.session = nil
                        switch result {
                        case .success:
                            state.issue = nil
                            onComplete(PhotoVerificationReceipt(photoID: photo.id, imageData: photo.imageData,
                                                                outcome: .match))
                        case .failure(let failure):
                            state.issue = AWSPhotoVerificationIssue(failure)
                        }
                    }
                }
            }
    }

    private var consent: some View {
        AWSVerificationConsentView(
            onBack: { showsConsent = false },
            onAgree: {
                showsConsent = false
                Task { await start() }
            }
        )
        .presentationDetents([.large])
    }

    private func start() async {
        guard let photo, let service else { return }
        state.isStarting = true
        defer { state.isStarting = false }
        var granted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            granted = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard granted else {
            state.issue = .cameraAccess
            return
        }
        do {
            session = try await service.start(photoID: photo.id)
            state.issue = nil
        } catch {
            state.issue = AWSPhotoVerificationIssue(error)
        }
    }
}

private struct AWSPhotoScan: View {
    let session: AWSPhotoVerificationSession
    let service: AWSPhotoVerificationService
    let onComplete: (Result<Void, Error>) -> Void
    @State private var detectorPresented = true
    @State private var scanFinished = false

    /// The onboarding's night colours and rounded titles. The oval, the dark
    /// around it and the flashing colours light your face, so AWS keeps those.
    /// Made once: a new theme on every redraw would redraw the detector.
    private static let livenessTheme: FaceLivenessDetectorTheme = {
        let theme = FaceLivenessDetectorTheme(colorScheme: .dark)
        // The middle of the app's button gradient, so instructions read like its buttons.
        theme.colors.primary = Color(red: 0.31, green: 0.36, blue: 0.90)
        theme.colors.onPrimary = .white
        theme.colors.error = OnboardingTheme.pink
        theme.colors.onError = .white
        theme.colors.background = OnboardingTheme.background
        theme.colors.onBackground = OnboardingTheme.primaryText
        theme.colors.surface = .white.opacity(0.16)
        theme.colors.errorContainer = Color(red: 0.20, green: 0.10, blue: 0.32)
        theme.colors.onErrorContainer = .white
        theme.fonts.title = .system(.title3, design: .rounded, weight: .semibold)
        theme.fonts.title2 = .system(.title2, design: .rounded, weight: .semibold)
        theme.fonts.title3 = .system(.title3, design: .rounded, weight: .semibold)
        theme.fonts.headline = .system(.headline, design: .rounded)
        theme.fonts.caption = .system(.caption, design: .rounded)
        return theme
    }()

    var body: some View {
        Group {
            if detectorPresented {
                // Our consent screen already showed the photosensitivity
                // warning, so the check starts without AWS's own start page.
                FaceLivenessDetectorView(sessionID: session.sessionID,
                                         credentialsProvider: AWSLivenessCredentialProvider(credentials: session.credentials),
                                         region: session.region,
                                         disableStartView: true,
                                         isPresented: $detectorPresented) { result in
                    switch result {
                    case .success: detectorPresented = false; scanFinished = true
                    case .failure(let error): onComplete(.failure(error))
                    }
                }
                .cancelButton { configuration in
                    LivenessCloseButton(action: configuration.cancel)
                        .accessibilityLabel(configuration.accessibilityLabel)
                }
                .faceLivenessDetectorTheme(Self.livenessTheme)
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(OnboardingTheme.cyan)
                    Text(L10n("The server is verifying your photo…"))
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(OnboardingTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background { OnboardingTheme.background.ignoresSafeArea() }
        .preferredColorScheme(.dark)
        .task(id: scanFinished) {
            guard scanFinished else { return }
            do {
                try await service.complete(session)
                onComplete(.success(()))
            } catch {
                if !Task.isCancelled { onComplete(.failure(error)) }
            }
        }
    }
}

/// What the AWS check does, in the onboarding's own look: title top left,
/// back chevron top right, the points in one card and the button below.
struct AWSVerificationConsentView: View {
    let onBack: () -> Void
    let onAgree: () -> Void

    private struct Point: Identifiable {
        let symbol: String
        let title: String
        let text: String
        var id: String { symbol }
    }

    private var points: [Point] {
        [
            Point(symbol: "faceid", title: L10n("The real you, matching your photo"),
                  text: L10n("AWS checks your live video to confirm you’re real and look like your photo, using face biometrics. We only keep the result, not the video or your face data.")),
            Point(symbol: "hand.raised.fill", title: L10n("Always your choice"),
                  text: L10n("Stop anytime or join without a photo. Up to five checks a day."))
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    pointsCard
                    Link(destination: URL(string: "https://docs.aws.amazon.com/rekognition/latest/dg/face-liveness-faq.html")!) {
                        Label(L10n("More about AWS Face Liveness"), systemImage: "arrow.up.right")
                            .labelStyle(TrailingIconLabelStyle())
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(OnboardingTheme.cyan)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .padding(.top, -12)
                    .padding(.leading, 4)
                }
                .frame(maxWidth: OnboardingTheme.contentWidth)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 4) {
                photosensitivityWarning
                    .padding(.bottom, 8)
                Button(L10n("I agree — start verification"), action: onAgree)
                    .buttonStyle(GlowButtonStyle())
                Button(L10n("Not now"), action: onBack)
                    .buttonStyle(QuietButtonStyle())
            }
            .frame(maxWidth: OnboardingTheme.controlWidth)
            .padding(.horizontal, 28)
            .padding(.top, 10)
            .padding(.bottom, OnboardingTheme.controlsBottomPadding)
            .frame(maxWidth: .infinity)
        }
        .background { OnboardingTheme.background.ignoresSafeArea() }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .headerTitle, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n("Photo verification"))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .headerTitleGuide()
                Text(L10n("Verify with AWS in Ireland"))
                    .font(.subheadline)
                    .foregroundStyle(OnboardingTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.accentGradient)
                    .frame(width: 44, height: 44)
                    .background { Circle().fill(.white.opacity(0.08)) }
                    .overlay { Circle().strokeBorder(OnboardingTheme.hairline, lineWidth: 0.5) }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n("Back"))
        }
    }

    /// AWS requires this warning before the check. Its own start page is
    /// skipped, so it stays in view right above the button that starts it.
    private var photosensitivityWarning: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(L10n("Photosensitivity warning"), systemImage: "exclamationmark.triangle.fill")
                .labelStyle(WarningLabelStyle())
                .font(.footnote.weight(.semibold))
                .foregroundStyle(OnboardingTheme.primaryText)
            Text(L10n("The check flashes colors on your screen. Take care if you or your family have epilepsy."))
                .font(.footnote)
                .foregroundStyle(OnboardingTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(OnboardingTheme.pink.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(OnboardingTheme.pink.opacity(0.3), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var pointsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                if index > 0 {
                    Rectangle().fill(OnboardingTheme.hairline).frame(height: 0.5)
                        .padding(.leading, 16)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(point.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(OnboardingTheme.primaryText)
                        Image(systemName: point.symbol)
                            .font(.body)
                            .foregroundStyle(OnboardingTheme.accentGradient)
                            .accessibilityHidden(true)
                    }
                    Text(point.text)
                        .font(.callout)
                        .foregroundStyle(OnboardingTheme.secondaryText)
                        .lineSpacing(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .accessibilityElement(children: .combine)
            }
        }
        .onboardingSurface(cornerRadius: 22)
    }
}

/// The app's round close control, dark so it stays visible on the white
/// light around the oval.
private struct LivenessCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(OnboardingTheme.accentGradient)
                .frame(width: 44, height: 44)
                .background { Circle().fill(OnboardingTheme.background) }
                .overlay { Circle().strokeBorder(.white.opacity(0.14), lineWidth: 0.5) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// The icon right before the title, both on the first line.
private struct WarningLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon
                .foregroundStyle(OnboardingTheme.pink)
                .accessibilityHidden(true)
            configuration.title
        }
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon.imageScale(.small)
        }
    }
}
