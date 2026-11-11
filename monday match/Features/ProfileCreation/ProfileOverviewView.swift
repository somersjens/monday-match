import SwiftUI

/// Every answer of a completed profile, full screen. Choosing an answer opens
/// that question here; saving or cancelling returns to the overview.
struct ProfileOverviewView: View {
    @ObservedObject var viewModel: ProfileCreationViewModel
    @ObservedObject var locationService: LocationService
    /// The edited birthday turned out to be underage; the cover must close.
    let onUnderage: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var path: [Route] = []

    enum Route: Hashable {
        case edit(ProfileCreationStep)
        case autoMatching
    }

    private static let sections: [(title: String, steps: [ProfileCreationStep])] = [
        ("Basics", [.dateOfBirth, .partnerAgeRange, .height, .partnerHeightRange, .gender, .partnerGenders, .sexualArrangement, .languages, .location]),
        ("Children", [.hasChildren, .partnerHasChildren, .futureChildren]),
        ("Lifestyle", [.alcohol, .smoking, .drugs]),
        ("Compatibility", [.aloneTime])
    ]

    var body: some View {
        NavigationStack(path: $path) {
            overview
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .edit(let step):
                        editor(for: step)
                    case .autoMatching:
                        AutoMatchingSetupView(viewModel: viewModel, onFinish: popToOverview)
                            .toolbar(.hidden, for: .navigationBar)
                    }
                }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Overview

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                autoMatchingCard

                ForEach(Self.sections, id: \.title) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.title.uppercased())
                            .font(.system(.caption, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(OnboardingTheme.tertiaryText)
                            .padding(.leading, 6)
                            .accessibilityLabel(section.title)
                            .accessibilityAddTraits(.isHeader)

                        VStack(spacing: 0) {
                            ForEach(section.steps) { step in
                                row(step, isLast: step == section.steps.last)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .onboardingSurface(cornerRadius: 24)
                    }
                }
            }
            .frame(maxWidth: OnboardingTheme.contentWidth)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background { OverviewBackground() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your profile")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(OnboardingTheme.primaryText)
                Text("Tap an answer to change it.")
                    .font(.subheadline)
                    .foregroundStyle(OnboardingTheme.secondaryText)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .frame(width: 44, height: 44)
                    .background { Circle().fill(.white.opacity(0.08)) }
                    .overlay { Circle().strokeBorder(OnboardingTheme.hairline, lineWidth: 0.5) }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.top, 12)
    }

    private var autoMatchingCard: some View {
        let settings = viewModel.state.autoMatching
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                IconTile(systemImage: "sparkles", isHighlighted: true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Join auto matching")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.primaryText)
                    Text(settings.isEnabled
                         ? "On · at least \(settings.minimumMatchPercent)% match"
                         : "Let us propose matches for you.")
                        .font(.footnote)
                        .foregroundStyle(OnboardingTheme.secondaryText)
                        .contentTransition(.opacity)
                }
                .accessibilityHidden(true)

                Spacer(minLength: 8)

                GlowToggle(isOn: settings.isEnabled, label: "Join auto matching") {
                    if settings.isEnabled {
                        viewModel.leaveAutoMatching()
                    } else {
                        path.append(.autoMatching)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if settings.isEnabled {
                Rectangle()
                    .fill(.white.opacity(0.07))
                    .frame(height: 0.5)
                    .padding(.leading, 16)

                Button { path.append(.autoMatching) } label: {
                    HStack {
                        Text("Auto matching settings")
                            .font(.system(.subheadline, weight: .medium))
                            .foregroundStyle(OnboardingTheme.primaryText)
                        Spacer()
                        Chevron()
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(AnswerRowStyle())
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(
                    colors: [OnboardingTheme.blue.opacity(0.20), OnboardingTheme.violet.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [OnboardingTheme.cyan.opacity(settings.isEnabled ? 0.55 : 0.25), OnboardingTheme.violet.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .animation(.easeInOut(duration: 0.25), value: settings.isEnabled)
    }

    private func row(_ step: ProfileCreationStep, isLast: Bool) -> some View {
        let answer = viewModel.state.summary(for: step, today: viewModel.today)
        let isAnswered = viewModel.isComplete(step)
        return Button { edit(step) } label: {
            HStack(spacing: 14) {
                IconTile(systemImage: step.overviewSymbol)

                VStack(alignment: .leading, spacing: 3) {
                    Text(step.shortTitle)
                        .font(.footnote)
                        .foregroundStyle(OnboardingTheme.secondaryText)
                    Text(answer.value)
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(isAnswered ? OnboardingTheme.primaryText : OnboardingTheme.tertiaryText)
                    if let detail = answer.detail {
                        Text(detail.prefix(1).uppercased() + detail.dropFirst())
                            .font(.subheadline)
                            .foregroundStyle(OnboardingTheme.cyan)
                    }
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                Chevron()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(AnswerRowStyle())
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(.white.opacity(0.07))
                    .frame(height: 0.5)
                    .padding(.leading, 66)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(step.shortTitle)
        .accessibilityValue(answer.compact)
        .accessibilityHint("Opens this question.")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Editing

    private func editor(for step: ProfileCreationStep) -> some View {
        ProfileCreationFlowView(
            viewModel: viewModel,
            locationService: locationService,
            canExitFromFirstStep: true,
            onExit: popToOverview,
            onUnderage: {
                dismiss()
                onUnderage()
            },
            onComplete: popToOverview
        )
        .background { OverviewBackground() }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .onDisappear {
            // Leaving without Save, such as by swiping back, keeps the old answer.
            if viewModel.editingStep != nil { viewModel.cancelEditing() }
        }
    }

    /// Editing starts before the push, so the question view opens on it.
    private func edit(_ step: ProfileCreationStep) {
        guard path.isEmpty else { return }
        viewModel.beginEditing(step)
        path.append(.edit(step))
    }

    private func popToOverview() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }
}

private struct OverviewBackground: View {
    var body: some View {
        ZStack {
            OnboardingTheme.background
            RadialGradient(
                colors: [OnboardingTheme.blue.opacity(0.22), .clear],
                center: .init(x: 0.15, y: 0),
                startRadius: 0,
                endRadius: 420
            )
            RadialGradient(
                colors: [OnboardingTheme.violet.opacity(0.16), .clear],
                center: .init(x: 0.95, y: 0.12),
                startRadius: 0,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }
}

private struct IconTile: View {
    let systemImage: String
    var isHighlighted = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(LinearGradient(
                colors: [OnboardingTheme.cyan, OnboardingTheme.violet],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .frame(width: 36, height: 36)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(.white.opacity(isHighlighted ? 0.12 : 0.06))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

private struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(OnboardingTheme.tertiaryText)
            .accessibilityHidden(true)
    }
}

private struct AnswerRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.white.opacity(configuration.isPressed ? 0.08 : 0))
    }
}

private extension ProfileCreationStep {
    var overviewSymbol: String {
        switch self {
        case .dateOfBirth: "birthday.cake"
        case .partnerAgeRange: "calendar"
        case .height: "ruler"
        case .partnerHeightRange: "arrow.up.and.down"
        case .gender: "person"
        case .partnerGenders: "heart"
        case .sexualArrangement: "link"
        case .languages: "globe"
        case .location: "mappin.and.ellipse"
        case .hasChildren: "figure.and.child.holdinghands"
        case .partnerHasChildren: "figure.2.and.child.holdinghands"
        case .futureChildren: "stroller"
        case .alcohol: "wineglass"
        case .smoking: "smoke"
        case .drugs: "leaf"
        case .aloneTime: "moon.stars"
        }
    }
}
