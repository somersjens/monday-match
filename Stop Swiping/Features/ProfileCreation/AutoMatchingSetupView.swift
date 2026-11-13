import PhotosUI
import SwiftUI
import UIKit

/// Two-step setup: matching preferences, then an optional verified photo.
struct AutoMatchingSetupView: View {
    @ObservedObject var viewModel: ProfileCreationViewModel
    @ObservedObject var locationService: LocationService
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pickerItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var isLoadingPhoto = false
    @State private var photoError: String?
    @State private var saveFailed = false
    @State private var appearanceMode: PartnerPreferenceScale.Mode = .own

    @State private var path: [Route] = []

    private enum Route: Hashable {
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
            setupPage(isFinalStep: false)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .photo:
                        setupPage(isFinalStep: true)
                    case .exclusions:
                        exclusionsPage
                    case .edit(let step):
                        editor(for: step)
                    }
                }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: loadSavedPhoto)
        .onChange(of: pickerItem) { _, item in
            if let item { loadPhoto(from: item) }
        }
    }

    // MARK: - Pages

    private func setupPage(isFinalStep: Bool) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(
                        title: L10n("Auto matching"),
                        subtitle: isFinalStep
                            ? L10n("Add and verify a photo, or join without one.")
                            : L10n("Set your preferences. We propose matches for you."),
                        backLabel: isFinalStep ? L10n("Back") : L10n("Back to home"),
                        onBack: { if isFinalStep { path.removeLast() } else { onFinish() } }
                    )
                    if isFinalStep {
                        photoCard
                        if settings.photoID != nil {
                            PhotoVerificationSection(
                                photo: viewModel.autoMatchingReferencePhoto,
                                receipt: viewModel.autoMatchingPhotoVerification,
                                onComplete: viewModel.recordAutoMatchingPhotoVerification
                            )
                            .padding(18)
                            .onboardingSurface(cornerRadius: 24)
                            .disabled(isLoadingPhoto)

                            Button(L10n("Continue without a photo"), action: removePhoto)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(OnboardingTheme.secondaryText)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .disabled(isLoadingPhoto)
                        }
                        partnerVerificationCard
                    } else {
                        minimumMatchCard
                        dealbreakersCard
                        appearanceScale
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

            bottomBar(isFinalStep: isFinalStep)
        }
        .background { OnboardingTheme.background.ignoresSafeArea() }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .animation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion), value: settings)
    }

    private func header(title: String, subtitle: String, backLabel: String, onBack: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(OnboardingTheme.primaryText)
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

    private var photoCard: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.white.opacity(0.06))
                    if let photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                    } else if isLoadingPhoto {
                        ProgressView()
                    } else {
                        Image(systemName: "person.crop.square.badge.camera")
                            .font(.system(size: 28, weight: .regular))
                            .foregroundStyle(LinearGradient(
                                colors: [OnboardingTheme.cyan, OnboardingTheme.violet],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                    }
                }
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            photo == nil ? AnyShapeStyle(.white.opacity(0.14)) : AnyShapeStyle(OnboardingTheme.accentGradient),
                            style: StrokeStyle(lineWidth: 1, dash: photo == nil ? [4, 4] : [])
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(photo == nil ? L10n("Upload a photo of yourself") : L10n("Your photo"))
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.primaryText)
                    Text(photo == nil
                         ? L10n("Use a recent, sharp photo of yourself, with exactly one face.")
                         : L10n("Used as the reference for your live face scan. Tap to change it."))
                        .font(.footnote)
                        .foregroundStyle(OnboardingTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let photoError {
                        Text(photoError)
                            .font(.system(.caption, weight: .medium))
                            .foregroundStyle(OnboardingTheme.pink)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoadingPhoto)
        .onboardingSurface(cornerRadius: 24)
        .accessibilityLabel(photo == nil ? L10n("Upload a photo of yourself") : L10n("Change your photo"))
    }

    private var appearanceScale: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n("Appearance"))
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(OnboardingTheme.primaryText)
                .accessibilityAddTraits(.isHeader)

            Text(L10n("Rate your own appearance and set the minimum score you’re looking for in a partner."))
                .font(.footnote)
                .foregroundStyle(OnboardingTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            PartnerPreferenceScale(
                levels: AppearanceRating.descendingScores.map { "\($0) · \(AppearanceRating.description(for: $0))" },
                ownIndex: settings.ownAttractiveness.map { AppearanceRating.range.upperBound - $0 },
                partnerLimitIndex: settings.partnerMinimumAttractiveness.map { AppearanceRating.range.upperBound - $0 },
                mode: $appearanceMode,
                onSelectOwn: { viewModel.setOwnAttractiveness(AppearanceRating.range.upperBound - $0) },
                onSelectPartnerLimit: { viewModel.setPartnerMinimumAttractiveness(AppearanceRating.range.upperBound - $0) },
                subject: .appearance
            )
        }
    }

    private var minimumMatchCard: some View {
        card(title: L10n("Minimum match"), value: "\(settings.minimumMatchPercent)%") {
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
                    Label(L10n("Who is excluded?"), systemImage: "exclamationmark.shield")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OnboardingTheme.primaryText)
                    Spacer(minLength: 0)
                    chevron
                }
                Text(viewModel.dealbreakers.heading)
                    .font(.footnote)
                    .foregroundStyle(OnboardingTheme.secondaryText)
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

    private var partnerVerificationCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n("Only photo-verified matches"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                Text(L10n("Your matches must have verified their photo. You can join without a photo yourself."))
                    .font(.footnote)
                    .foregroundStyle(OnboardingTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            GlowToggle(isOn: settings.requiresVerifiedPartnerPhoto, label: L10n("Only photo-verified matches")) {
                viewModel.setRequiresVerifiedPartnerPhoto(!settings.requiresVerifiedPartnerPhoto)
            }
        }
        .padding(18)
        .onboardingSurface(cornerRadius: 24)
    }

    private func bottomBar(isFinalStep: Bool) -> some View {
        VStack(spacing: 8) {
            if saveFailed {
                Text(L10n("Auto matching couldn’t be saved. Try again."))
                    .font(.system(.footnote, weight: .medium))
                    .foregroundStyle(OnboardingTheme.pink)
            } else if !settings.isReady {
                Text(L10n("Set both appearance scores to continue."))
                    .font(.footnote)
                    .foregroundStyle(OnboardingTheme.tertiaryText)
            } else if isFinalStep && settings.photoID != nil && !viewModel.hasVerifiedAutoMatchingPhoto {
                Text(L10n("Verify your photo, or continue without one."))
                    .font(.footnote)
                    .foregroundStyle(OnboardingTheme.tertiaryText)
            }

            Button(isFinalStep ? L10n("Join auto matching") : L10n("Final step")) {
                saveFailed = false
                if !isFinalStep, let missingAppearanceSide {
                    appearanceMode = missingAppearanceSide
                    return
                }
                if isFinalStep {
                    saveFailed = !viewModel.joinAutoMatching()
                    if !saveFailed { onFinish() }
                } else {
                    path.append(.photo)
                }
            }
            .buttonStyle(GlowButtonStyle())
            .disabled((!settings.isReady && (isFinalStep || missingAppearanceSide == nil)) || isLoadingPhoto || (isFinalStep && settings.photoID != nil && !viewModel.hasVerifiedAutoMatchingPhoto))
        }
        .frame(maxWidth: OnboardingTheme.controlWidth)
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
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

    // MARK: - Photo

    private func removePhoto() {
        if let error = viewModel.removeAutoMatchingPhoto() {
            photoError = error
        } else {
            photo = nil
            photoError = nil
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
            if let error = viewModel.setAutoMatchingPhoto(data) {
                photoError = error
            } else {
                photo = viewModel.autoMatchingPhoto.flatMap { UIImage(data: $0) }
            }
        }
    }
}
