import PhotosUI
import SwiftUI
import UIKit

/// What auto matching needs before it can be switched on: a photo, how the
/// user rates their own looks and a partner's, and the lowest match accepted.
struct AutoMatchingSetupView: View {
    @ObservedObject var viewModel: ProfileCreationViewModel
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pickerItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var isLoadingPhoto = false
    @State private var photoError: String?
    @State private var saveFailed = false

    private var settings: AutoMatchingSettings { viewModel.state.autoMatching }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView {
                VStack(spacing: 14) {
                    VStack(spacing: 8) {
                        Text("Auto matching")
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .foregroundStyle(OnboardingTheme.primaryText)
                            .accessibilityAddTraits(.isHeader)
                        Text("We propose matches for you. Add these to join.")
                            .font(.subheadline)
                            .foregroundStyle(OnboardingTheme.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.bottom, 10)

                    photoCard

                    card(
                        title: "How attractive do you find your own appearance?",
                        value: settings.ownAttractiveness.map { "\($0)" }
                    ) {
                        ScaleSelector(
                            label: "How attractive do you find your own appearance?",
                            value: settings.ownAttractiveness,
                            lowLabel: "Not attractive",
                            highLabel: "Very attractive",
                            valueDescription: { "\($0)" },
                            onSelect: { viewModel.setOwnAttractiveness($0) }
                        )
                    }

                    card(
                        title: "How important is appearance in a partner?",
                        value: settings.partnerAppearanceImportance.map { CompatibilityScaleAnswer.importanceTitle($0) }
                    ) {
                        ScaleSelector(
                            label: "How important is appearance in a partner?",
                            value: settings.partnerAppearanceImportance,
                            lowLabel: "Not important",
                            highLabel: "Very important",
                            valueDescription: { "\($0), \(CompatibilityScaleAnswer.importanceTitle($0))" },
                            onSelect: { viewModel.setPartnerAppearanceImportance($0) }
                        )
                    }

                    minimumMatchCard
                    dealbreakersCard
                }
                .frame(maxWidth: OnboardingTheme.controlWidth)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)

            bottomBar
        }
        .background { OnboardingTheme.background.ignoresSafeArea() }
        .animation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion), value: settings)
        .onAppear(perform: loadSavedPhoto)
        .onChange(of: pickerItem) { _, item in
            if let item { loadPhoto(from: item) }
        }
    }

    // MARK: - Pieces

    private var topBar: some View {
        HStack {
            Button(action: onFinish) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .frame(width: 44, height: 44)
                    .background { Circle().fill(.white.opacity(0.08)) }
                    .overlay { Circle().strokeBorder(OnboardingTheme.hairline, lineWidth: 0.5) }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to your profile")
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

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
                    Text(photo == nil ? "Upload a photo of yourself" : "Your photo")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.primaryText)
                    Text(photo == nil
                         ? "A clear, recent photo or screenshot where your face is easy to see."
                         : "Tap to choose a different one.")
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
        .accessibilityLabel(photo == nil ? "Upload a photo of yourself" : "Change your photo")
    }

    private var minimumMatchCard: some View {
        card(title: "Minimum match", value: "\(settings.minimumMatchPercent)%") {
            VStack(alignment: .leading, spacing: 10) {
                GlowSlider(
                    value: Binding(
                        get: { viewModel.state.autoMatching.minimumMatchPercent },
                        set: { viewModel.setMinimumMatchPercent($0) }
                    ),
                    scale: SliderScale(bounds: AutoMatchingSettings.minimumScoreRange),
                    label: "Minimum match",
                    valueDescription: { "\($0) percent" }
                )
                HStack {
                    Text("\(AutoMatchingSettings.minimumScoreRange.lowerBound)%")
                    Spacer()
                    Text("\(AutoMatchingSettings.minimumScoreRange.upperBound)%")
                }
                .font(.system(.footnote, design: .rounded).monospacedDigit())
                .foregroundStyle(OnboardingTheme.tertiaryText)
                .accessibilityHidden(true)

                Text("Only people who match you at least this much are proposed.")
                    .font(.footnote)
                    .foregroundStyle(OnboardingTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var dealbreakersCard: some View {
        let dealbreakers = viewModel.dealbreakers
        return VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(dealbreakers.heading)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.shield")
                    .foregroundStyle(OnboardingTheme.cyan)
            }

            if dealbreakers.lines.isEmpty {
                Text("Your answers don’t rule anyone out.")
                    .font(.subheadline)
                    .foregroundStyle(OnboardingTheme.secondaryText)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(dealbreakers.lines, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(OnboardingTheme.pink)
                                .accessibilityHidden(true)
                            Text(line)
                                .font(.subheadline)
                                .foregroundStyle(OnboardingTheme.primaryText.opacity(0.88))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            Text("Change these through the questions in your profile.")
                .font(.caption)
                .foregroundStyle(OnboardingTheme.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .onboardingSurface(cornerRadius: 24)
        .accessibilityElement(children: .combine)
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if saveFailed {
                Text("Auto matching couldn’t be saved. Try again.")
                    .font(.system(.footnote, weight: .medium))
                    .foregroundStyle(OnboardingTheme.pink)
            } else if !settings.isReady {
                Text("Add a photo and both scores to join.")
                    .font(.footnote)
                    .foregroundStyle(OnboardingTheme.tertiaryText)
            }

            Button(settings.isEnabled ? "Save" : "Join auto matching") {
                saveFailed = !viewModel.joinAutoMatching()
                if !saveFailed { onFinish() }
            }
            .buttonStyle(GlowButtonStyle())
            .disabled(!settings.isReady || isLoadingPhoto)
        }
        .frame(maxWidth: OnboardingTheme.controlWidth)
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private func card<Content: View>(
        title: String,
        value: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
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
                photoError = "That photo couldn’t be opened."
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
