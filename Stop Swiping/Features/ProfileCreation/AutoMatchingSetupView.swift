import PhotosUI
import SwiftUI
import UIKit

/// Three-step setup: matching preferences, appearance, then an optional verified photo.
struct AutoMatchingSetupView: View {
    @ObservedObject var viewModel: ProfileCreationViewModel
    @ObservedObject var locationService: LocationService
    var serverVerification: PhotoVerificationService? = nil
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.notificationEngine) private var notificationEngine
    @State private var pickerItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var isLoadingPhoto = false
    @State private var photoError: String?
    @State private var saveFailed = false
    @State private var showsPrivacy = false
    /// Joining opens the data policy first; accepting it continues joining.
    @State private var joinsAfterPrivacy = false
    @State private var showsVerificationScan = false
    @State private var verification = PhotoVerificationState()
    @State private var asksAboutUnverifiedPhoto = false
    @State private var asksToRemoveVerifiedPhoto = false
    @State private var appearanceMode: PartnerPreferenceScale.Mode = .own

    @State private var path: [Route]

    /// `startsOnPhotoStep` opens the last step directly, and
    /// `asksToRemovePhoto` shows the removal prompt over a verified photo,
    /// both for layout renders.
    init(viewModel: ProfileCreationViewModel, locationService: LocationService,
         serverVerification: PhotoVerificationService? = nil, startsOnPhotoStep: Bool = false,
         asksToRemovePhoto: Bool = false, onFinish: @escaping () -> Void) {
        self.viewModel = viewModel
        self.locationService = locationService
        self.serverVerification = serverVerification
        self.onFinish = onFinish
        _path = State(initialValue: startsOnPhotoStep ? [.appearance, .photo] : [])
        _asksToRemoveVerifiedPhoto = State(initialValue: asksToRemovePhoto)
    }

    private enum Stage: Hashable {
        case preferences
        case appearance
        case photo
    }

    private enum Route: Hashable {
        case appearance
        case photo
        case exclusions
        case edit(ProfileCreationStep)
    }

    private var settings: AutoMatchingSettings { viewModel.state.autoMatching }

    private var missingAppearanceSide: PartnerPreferenceScale.Mode? {
        switch (settings.ownAttractiveness, settings.partnerMinimumAttractiveness) {
        case (.some, .none): return .partner
        case (.none, .some): return .own
        default: return nil
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            setupPage(.preferences)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .appearance:
                        setupPage(.appearance)
                    case .photo:
                        setupPage(.photo)
                    case .exclusions:
                        exclusionsPage
                    case .edit(let step):
                        editor(for: step)
                    }
                }
        }
        .preferredColorScheme(.dark)
        // Each page comes forward and steps back like the app's other panels.
        .soundFeedback(trigger: path.count) { old, new in new > old ? .open : .close }
        .sheet(isPresented: $showsPrivacy, onDismiss: continueJoiningAfterPrivacy) {
            PrivacyConsentView(kind: .matching) { viewModel.acceptPrivacy(.matching) }
        }
        .onAppear(perform: loadSavedPhoto)
        .onChange(of: pickerItem) { _, item in
            if let item { loadPhoto(from: item) }
        }
    }

    // MARK: - Pages

    private func subtitle(for stage: Stage) -> String {
        switch stage {
        case .preferences: L10n("We’ll text you when we’ve found the one.")
        case .appearance: L10n("Rate your own appearance and set the minimum score you’re looking for in a partner.")
        case .photo: L10n("Add and verify a photo, or join without one.")
        }
    }

    private func setupPage(_ stage: Stage) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(
                        title: L10n("Auto matching"),
                        subtitle: subtitle(for: stage),
                        backLabel: stage == .preferences ? L10n("Back to home") : L10n("Back"),
                        onBack: { if stage == .preferences { onFinish() } else { path.removeLast() } }
                    )
                    switch stage {
                    case .photo:
                        photoCard
                        photoSettingsCard
                    case .appearance:
                        appearanceScale
                    case .preferences:
                        minimumMatchCard
                        dealbreakersCard
                        if let notificationEngine {
                            NotificationsOffCard(engine: notificationEngine)
                        }
                    }
                }
                .frame(maxWidth: OnboardingTheme.contentWidth)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)

            bottomBar(stage)
        }
        .adaptiveStageHeight()
        .background { OnboardingTheme.background.ignoresSafeArea() }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .animation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion), value: settings)
        .animation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion), value: photoIsVerified)
    }

    private func header(title: String, subtitle: String, backLabel: String, onBack: @escaping () -> Void) -> some View {
        HStack(alignment: .headerTitle, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .headerTitleGuide()
                Text(subtitle)
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
            .accessibilityLabel(backLabel)
        }
    }

    // MARK: - Pieces

    /// Your photo as a match will see it: square, with your name, age and a
    /// distance. It stays greyed out until a live scan verified it; only then
    /// does the match bubble show. The button in the corner starts that scan.
    private var photoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    GeometryReader { proxy in
                        let side = proxy.size.width
                        if let photo {
                            // An unverified photo is still a picker: tap it
                            // to choose another. A verified one only goes
                            // through the cross, which asks first.
                            Group {
                                if photoIsVerified {
                                    ownPhotoCard(photo, side: side)
                                } else {
                                    PhotosPicker(selection: $pickerItem, matching: .images) {
                                        ownPhotoCard(photo, side: side)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isLoadingPhoto || verification.isSaving)
                                    .accessibilityLabel(L10n("Choose another photo"))
                                }
                            }
                                .overlay { if isLoadingPhoto { ProgressView().controlSize(.large) } }
                                .overlay(alignment: .topLeading) {
                                    if !photoIsVerified {
                                        verifyButton(scale: MatchPhotoCardView.detailScale(for: side))
                                            .padding(MatchPhotoCardView.ring + 14 * MatchPhotoCardView.detailScale(for: side))
                                    }
                                }
                                .overlay(alignment: .topTrailing) {
                                    // Same size and column as the back chevron above.
                                    if !asksToRemoveVerifiedPhoto {
                                        removeButton
                                            .offset(y: -16)
                                            .transition(reduceMotion ? .opacity
                                                        : .scale(scale: 0.6).combined(with: .opacity))
                                    }
                                }
                                .overlay {
                                    // Asks right on the photo it is about.
                                    if asksToRemoveVerifiedPhoto {
                                        removalPrompt(side: side)
                                    }
                                }
                                .transition(.opacity)
                        } else {
                            PhotosPicker(selection: $pickerItem, matching: .images) {
                                photoPlaceholder(side: side)
                            }
                            .buttonStyle(.plain)
                            .disabled(isLoadingPhoto)
                            .accessibilityLabel(L10n("Upload a photo of yourself"))
                            .transition(.opacity)
                        }
                    }
                }
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
            if let photoError {
                Text(photoError)
                    .font(.system(.footnote, weight: .medium))
                    .foregroundStyle(OnboardingTheme.pink)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let issue = verification.issue {
                verificationNotice(issue)
                    .padding(.top, 4)
                    .transition(.onboardingReveal(reduceMotion: reduceMotion))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: photo == nil)
        .animation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion),
                   value: verification.issue)
        .animation(.spring(duration: 0.45, bounce: 0.2), value: photoIsVerified)
        .photoVerification(
            photo: viewModel.autoMatchingReferencePhoto,
            service: serverVerification,
            isVerified: photoIsVerified,
            isPresented: $showsVerificationScan,
            state: $verification,
            onComplete: viewModel.recordAutoMatchingPhotoVerification
        )
        .confirmationDialog(L10n("Your photo isn’t verified yet"), isPresented: $asksAboutUnverifiedPhoto,
                            titleVisibility: .visible) {
            Button(L10n("Verify this photo")) { showsVerificationScan = true }
            Button(L10n("Join without a photo")) {
                removePhoto()
                if photo == nil { join() }
            }
            Button(L10n("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n("Only a verified photo is used for auto matching."))
        }
    }

    /// Why the last check did not go through, and what to do about it.
    private func verificationNotice(_ issue: PhotoVerificationIssue) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: issue.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(OnboardingTheme.pink)
                .frame(width: 34, height: 34)
                .background { Circle().fill(OnboardingTheme.pink.opacity(0.14)) }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(issue.title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                Text(issue.message)
                    .font(.footnote)
                    .foregroundStyle(OnboardingTheme.secondaryText)
                if issue == .cameraAccess, let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    Link(L10n("Open Settings"), destination: settingsURL)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(OnboardingTheme.cyan)
                        .padding(.top, 4)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(OnboardingTheme.pink.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(OnboardingTheme.pink.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    /// The photo's switches in one card. Each row slides in once it means
    /// something: the photo's use once there is one, verified-only matching
    /// once you are verified yourself. The data policy is always last.
    private var photoSettingsCard: some View {
        let reveal = AnyTransition.asymmetric(
            insertion: .move(edge: .top).combined(with: .onboardingReveal(reduceMotion: reduceMotion)),
            removal: .opacity
        )
        return VStack(spacing: 0) {
            if settings.photoID != nil {
                VStack(spacing: 0) {
                    toggleRow(title: L10n("Also use for manual matching"),
                              isOn: settings.sharesPhotoWithManualMatching) {
                        viewModel.setSharesPhotoWithManualMatching(!settings.sharesPhotoWithManualMatching)
                    }
                    .disabled(isLoadingPhoto)
                    rowDivider
                }
                .transition(reduceMotion ? .opacity : reveal)
            }
            if photoIsVerified {
                VStack(spacing: 0) {
                    toggleRow(title: L10n("Only match with verified users"),
                              isOn: settings.requiresVerifiedPartnerPhoto) {
                        viewModel.setRequiresVerifiedPartnerPhoto(!settings.requiresVerifiedPartnerPhoto)
                    }
                    rowDivider
                }
                .transition(reduceMotion ? .opacity : reveal)
            }
            toggleRow(title: L10n("Know what happens to your data"),
                      isOn: viewModel.state.hasAcceptedMatchingPrivacy) {
                if viewModel.state.hasAcceptedMatchingPrivacy {
                    viewModel.withdrawMatchingPrivacy()
                } else {
                    showsPrivacy = true
                }
            }
        }
        .padding(.vertical, 4)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onboardingSurface(cornerRadius: 24)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(OnboardingTheme.hairline)
            .frame(height: 0.5)
            .padding(.leading, 16)
    }

    /// The empty square: what makes a good photo, and a tap to pick one.
    /// Everything hangs off one leading edge, like a card: the camera badge
    /// top-left, the title and the tips anchored to the bottom.
    private func photoPlaceholder(side: CGFloat) -> some View {
        let radius = side * 0.11
        let inset = max(20, side * 0.07)
        return VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.08))
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                if isLoadingPhoto {
                    ProgressView()
                } else {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.accentGradient)
                }
            }
            .frame(width: 52, height: 52)
            .accessibilityHidden(true)

            Spacer(minLength: 14)

            Text(L10n("Upload a photo of yourself"))
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(OnboardingTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(height: 1)
                .padding(.vertical, 14)

            VStack(alignment: .leading, spacing: 10) {
                photoTip("sparkles", L10n("Make a good first impression"))
                photoTip("person.fill", L10n("Just you in the picture, no friends or exes"))
                photoTip("sunglasses.fill", L10n("No sunglasses, nothing covering your face"))
                photoTip("hand.point.up.left.fill", L10n("You only get one, so choose wisely"))
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .minimumScaleFactor(0.8)
        .padding(inset)
        .frame(width: side, height: side, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.white.opacity(0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        }
        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    private func photoTip(_ symbol: String, _ text: String) -> some View {
        // Icons share one centre line; the sunglasses are wider than the
        // rest and stick out a little on both sides.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OnboardingTheme.cyan)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(OnboardingTheme.primaryText.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The photo card a match would see. The distance is an example: there
    /// is no match yet.
    private func ownCard(_ photo: UIImage) -> MatchPhotoCard {
        let state = viewModel.state
        return MatchPhotoCard(name: state.displayName.isEmpty ? L10n("You") : state.displayName,
                              age: state.age(on: viewModel.today), photo: photo,
                              isVerified: photoIsVerified, distanceKilometers: 3)
    }

    /// A chosen photo counts once a live scan verified it, or once setup was
    /// completed with it: replacing the photo starts setup over.
    private var photoIsVerified: Bool {
        settings.photoID != nil && (settings.hasCompletedSetup || viewModel.hasVerifiedAutoMatchingPhoto)
    }

    private func verifyButton(scale: CGFloat) -> some View {
        Button { showsVerificationScan = true } label: {
            HStack(spacing: 6 * scale) {
                if verification.isSaving {
                    ProgressView().controlSize(.small).tint(.white)
                }
                Text(L10n("Verify this photo"))
            }
            .font(.system(size: 14 * scale, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14 * scale)
            .padding(.vertical, 9 * scale)
            .background { Capsule().fill(.ultraThinMaterial) }
            .environment(\.colorScheme, .dark)
            .overlay {
                // The light's colours, like the card's own ring.
                Capsule().strokeBorder(AngularGradient(colors: [OnboardingTheme.cyan, OnboardingTheme.blue,
                                                                OnboardingTheme.violet, OnboardingTheme.pink,
                                                                OnboardingTheme.cyan],
                                                       center: .center), lineWidth: 2)
            }
            .shadow(color: OnboardingTheme.blue.opacity(0.6), radius: 10)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(verification.isSaving || isLoadingPhoto)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    private func ownPhotoCard(_ photo: UIImage, side: CGFloat) -> some View {
        MatchPhotoCardView(card: ownCard(photo), average: 100, side: side,
                           dimsPhoto: !photoIsVerified, showsScore: photoIsVerified)
    }

    private func removalPrompt(side: CGFloat) -> some View {
        ConfirmationPrompt(
            side: side,
            symbol: "checkmark.seal.fill",
            title: L10n("Remove your verified photo?"),
            message: L10n("If you remove this picture and you want to add it later, you will need to verify it again."),
            keepTitle: L10n("Keep photo"),
            removeTitle: L10n("Remove photo"),
            onKeep: { setRemovalPrompt(false) },
            onRemove: {
                // One motion: prompt and photo leave together, the empty
                // square fades in where they were.
                withAnimation(removalAnimation) {
                    asksToRemoveVerifiedPhoto = false
                    removePhoto()
                }
            }
        )
        .transition(reduceMotion ? .opacity : .scale(scale: 0.94).combined(with: .opacity))
    }

    /// A red cross on the card's corner, as big as the back chevron and
    /// right under it. A verified photo asks first, because adding it back
    /// means verifying again.
    private var removeButton: some View {
        RedCrossButton(accessibilityLabel: L10n("Remove photo"), action: requestPhotoRemoval)
            .disabled(isLoadingPhoto || verification.isSaving)
    }

    private var appearanceScale: some View {
        PartnerPreferenceScale(
            levels: AppearanceRating.descendingScores.map { "\($0) · \(AppearanceRating.description(for: $0))" },
            ownIndex: settings.ownAttractiveness.map { AppearanceRating.range.upperBound - $0 },
            partnerLimitIndex: settings.partnerMinimumAttractiveness.map { AppearanceRating.range.upperBound - $0 },
            mode: $appearanceMode,
            onSelectOwn: selectOwnAppearance,
            onSelectPartnerLimit: { viewModel.setPartnerMinimumAttractiveness(AppearanceRating.range.upperBound - $0) },
            subject: .appearance
        )
    }

    /// The first own rating moves on to the partner minimum by itself.
    private func selectOwnAppearance(_ index: Int) {
        let needsMinimum = appearanceMode == .own && settings.partnerMinimumAttractiveness == nil
        viewModel.setOwnAttractiveness(AppearanceRating.range.upperBound - index)
        guard needsMinimum else { return }
        Task {
            try? await Task.sleep(for: reduceMotion ? .zero : OnboardingMotion.partnerHandoff)
            guard path.last == .appearance,
                  appearanceMode == .own,
                  settings.partnerMinimumAttractiveness == nil else { return }
            // The scale animates its own ring handoff.
            appearanceMode = .partner
        }
    }

    private var minimumMatchCard: some View {
        card(title: L10n("Minimum match"), value: L10nPercent(settings.minimumMatchPercent)) {
            GlowSlider(
                value: Binding(
                    get: { viewModel.state.autoMatching.minimumMatchPercent },
                    set: { viewModel.setMinimumMatchPercent($0) }
                ),
                scale: SliderScale(bounds: AutoMatchingSettings.minimumScoreRange),
                label: L10n("Minimum match"),
                valueDescription: { L10n("\($0) percent") }
            )
        }
    }

    private var dealbreakersCard: some View {
        Button { path.append(.exclusions) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Text(viewModel.dealbreakers.heading)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OnboardingTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                exclusionLines
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onboardingSurface(cornerRadius: 24)
        .accessibilityHint(L10n("Tap to review and change your exclusions."))
    }

    private var exclusionLines: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.dealbreakers.lines.isEmpty {
                Text(L10n("Your answers don’t rule anyone out."))
                    .foregroundStyle(OnboardingTheme.secondaryText)
            } else {
                ForEach(viewModel.dealbreakers.entries, id: \.step) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(OnboardingTheme.pink)
                            .accessibilityHidden(true)
                        Text(entry.text)
                            .foregroundStyle(OnboardingTheme.primaryText.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .font(.footnote)
    }

    private var exclusionsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(
                    title: L10n("Who is excluded?"),
                    subtitle: L10n("Tap a preference to change who can match with you."),
                    backLabel: L10n("Back"),
                    onBack: { path.removeLast() }
                )
                Text(viewModel.dealbreakers.heading)
                    .font(.body)
                    .foregroundStyle(OnboardingTheme.secondaryText)
                VStack(spacing: 0) {
                    ForEach(MatchDealbreakers.editableSteps) { step in
                        exclusionRow(step)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .onboardingSurface(cornerRadius: 24)
            }
            .frame(maxWidth: OnboardingTheme.contentWidth)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background { OnboardingTheme.background.ignoresSafeArea() }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
    }

    private func exclusionRow(_ step: ProfileCreationStep) -> some View {
        let summary = viewModel.state.summary(for: step, today: viewModel.today)
        let exclusion = viewModel.dealbreakers.entries.first { $0.step == step }?.text
        return Button {
            viewModel.beginEditing(step)
            path.append(.edit(step))
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(step.shortTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OnboardingTheme.primaryText)
                    Text(exclusion ?? summary.compact)
                        .font(.body)
                        .foregroundStyle(OnboardingTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                chevron
            }
            .multilineTextAlignment(.leading)
            .padding(18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if step != MatchDealbreakers.editableSteps.last {
                Rectangle().fill(OnboardingTheme.hairline).frame(height: 0.5).padding(.horizontal, 18)
            }
        }
    }

    private func editor(for step: ProfileCreationStep) -> some View {
        ProfileCreationFlowView(
            viewModel: viewModel,
            locationService: locationService,
            canExitFromFirstStep: true,
            onExit: { path.removeLast() },
            onUnderage: onFinish,
            onComplete: { path.removeAll() }
        )
        .background { OnboardingTheme.background.ignoresSafeArea() }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .onDisappear {
            if viewModel.editingStep != nil { viewModel.cancelEditing() }
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(OnboardingTheme.tertiaryText)
            .accessibilityHidden(true)
    }

    /// A single-line setting with a switch, one row of the photo settings card.
    private func toggleRow(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button(action: action) {
                Text(title)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            GlowToggle(isOn: isOn, label: title, action: action)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }

    private func bottomBar(_ stage: Stage) -> some View {
        let isFinalStep = stage == .photo
        return VStack(spacing: 8) {
            if saveFailed {
                Text(L10n("Auto matching couldn’t be saved. Try again."))
                    .font(.system(.footnote, weight: .medium))
                    .foregroundStyle(OnboardingTheme.pink)
            } else if stage != .preferences && !settings.isReady {
                Text(L10n("Set both appearance scores to continue."))
                    .font(.footnote)
                    .foregroundStyle(OnboardingTheme.tertiaryText)
            }

            Button(primaryTitle(for: stage)) {
                saveFailed = false
                switch stage {
                case .preferences:
                    path.append(.appearance)
                case .appearance:
                    if let missingAppearanceSide {
                        appearanceMode = missingAppearanceSide
                    } else {
                        path.append(.photo)
                    }
                case .photo:
                    join()
                }
            }
            .buttonStyle(GlowButtonStyle())
            .disabled(isPrimaryDisabled(for: stage))

            if isFinalStep {
                Text(L10n("If your future match disputes your height, age, name or picture, you risk losing your account."))
                    .font(.footnote)
                    .foregroundStyle(OnboardingTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: OnboardingTheme.controlWidth)
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .controlsBottomPadding()
        .frame(maxWidth: .infinity)
    }

    private func primaryTitle(for stage: Stage) -> String {
        switch stage {
        case .preferences: L10n("Continue")
        case .appearance: L10n("Final step")
        case .photo: L10n("Join auto matching")
        }
    }

    private func isPrimaryDisabled(for stage: Stage) -> Bool {
        switch stage {
        case .preferences:
            return false
        case .appearance:
            return !settings.isReady && missingAppearanceSide == nil
        case .photo:
            return !settings.isReady || isLoadingPhoto || verification.isSaving
        }
    }

    private func card<Content: View>(
        title: String,
        value: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let value {
                    Text(value)
                        .font(.system(.subheadline, weight: .semibold).monospacedDigit())
                        .foregroundStyle(OnboardingTheme.cyan)
                        .contentTransition(.numericText())
                }
            }
            .accessibilityHidden(true)

            content()
        }
        .padding(18)
        .onboardingSurface(cornerRadius: 24)
    }

    // MARK: - Joining

    /// Opens the data policy first when it wasn't accepted yet, and asks what
    /// to do with a photo that isn't verified.
    private func join() {
        saveFailed = false
        guard viewModel.state.hasAcceptedMatchingPrivacy else {
            joinsAfterPrivacy = true
            showsPrivacy = true
            return
        }
        guard settings.photoID == nil || photoIsVerified else {
            asksAboutUnverifiedPhoto = true
            return
        }
        saveFailed = !viewModel.joinAutoMatching()
        if saveFailed {
            SoundPlayer.shared.play(.rejection)
        } else {
            SoundPlayer.shared.play(.success)
            onFinish()
        }
    }

    private func continueJoiningAfterPrivacy() {
        guard joinsAfterPrivacy else { return }
        joinsAfterPrivacy = false
        if viewModel.state.hasAcceptedMatchingPrivacy { join() }
    }

    // MARK: - Photo

    private func requestPhotoRemoval() {
        if photoIsVerified {
            setRemovalPrompt(true)
        } else {
            removePhoto()
        }
    }

    private var removalAnimation: Animation {
        OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion)
    }

    private func setRemovalPrompt(_ shown: Bool) {
        withAnimation(removalAnimation) { asksToRemoveVerifiedPhoto = shown }
    }

    private func removePhoto() {
        if let error = viewModel.removeAutoMatchingPhoto() {
            photoError = error
        } else {
            photo = nil
            photoError = nil
            verification.issue = nil
            saveFailed = false
        }
    }

    private func loadSavedPhoto() {
        guard photo == nil, let data = viewModel.autoMatchingPhoto else { return }
        photo = UIImage(data: data)
    }

    private func loadPhoto(from item: PhotosPickerItem) {
        isLoadingPhoto = true
        photoError = nil
        Task {
            defer {
                isLoadingPhoto = false
                pickerItem = nil
            }
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                photoError = L10n("That photo couldn’t be opened.")
                return
            }
            if let error = await viewModel.setAutoMatchingPhotoInBackground(data) {
                photoError = error
            } else {
                photo = viewModel.autoMatchingPhoto.flatMap { UIImage(data: $0) }
            }
        }
    }
}

/// Asks before something hard to undo, laid exactly over the photo square
/// it is about: same size, same rounded corners. Removing is the red
/// button, in the corner cross's colour; keeping is the quiet way back.
private struct ConfirmationPrompt: View {
    let side: CGFloat
    let symbol: String
    let title: String
    let message: String
    let keepTitle: String
    let removeTitle: String
    let onKeep: () -> Void
    let onRemove: () -> Void

    private var radius: CGFloat { side * 0.11 }
    private var scale: CGFloat { MatchPhotoCardView.detailScale(for: side) }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }.scrollIndicators(.hidden)
        }
        .frame(width: side, height: side)
        .background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(OnboardingTheme.background)
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(LinearGradient(colors: [OnboardingTheme.blue.opacity(0.18),
                                                      OnboardingTheme.violet.opacity(0.10)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                }
        }
        .overlay {
            // The light's colours, like the photo card's own ring.
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(AngularGradient(colors: [OnboardingTheme.cyan, OnboardingTheme.blue, OnboardingTheme.violet,
                                                       OnboardingTheme.pink, OnboardingTheme.cyan],
                                              center: .center, angle: .degrees(-45)),
                              lineWidth: 2.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var content: some View {
        VStack(spacing: 16 * scale) {
            Image(systemName: symbol)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, OnboardingTheme.cyan)
                .font(.system(size: 30 * scale, weight: .semibold))
                .shadow(color: OnboardingTheme.cyan.opacity(0.6), radius: 12)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(OnboardingTheme.secondaryText)
                    .lineSpacing(2)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 2) {
                Button(removeTitle, action: onRemove)
                    .buttonStyle(DestructiveButtonStyle())
                Button(action: onKeep) {
                    Text(keepTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.primaryText.opacity(0.86))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, max(20, side * 0.07))
        .padding(.top, 20 * scale)
        .padding(.bottom, 8 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The prompt's red choice: the corner cross's colour, filled, shaped like
/// the app's other big buttons.
private struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: OnboardingTheme.buttonHeight)
            .background {
                RoundedRectangle(cornerRadius: 20).fill(OnboardingTheme.destructive)
            }
            .contentShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: OnboardingTheme.destructive.opacity(0.35), radius: 14)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: configuration.isPressed)
    }
}
