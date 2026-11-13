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
    @State private var showsLanguagePicker = false

    enum Route: Hashable {
        case edit(ProfileCreationStep)
    }

    private static var sections: [(title: String, steps: [ProfileCreationStep])] { [
        (L10n("Basics"), [.dateOfBirth, .partnerAgeRange, .height, .partnerHeightRange, .gender, .partnerGenders, .sexualArrangement, .religion, .languages, .location]),
        (L10n("Children"), [.hasChildren, .partnerHasChildren, .futureChildren]),
        (L10n("Lifestyle"), [.alcohol, .smoking, .drugs]),
        (L10n("Compatibility"), [.aloneTime])
    ] }

    var body: some View {
        NavigationStack(path: $path) {
            overview
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .edit(let step):
                        editor(for: step)
                    }
                }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsLanguagePicker) {
            AppLanguagePicker()
        }
    }

    // MARK: - Overview

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

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
                Text(L10n("Your profile"))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(OnboardingTheme.primaryText)
                Text(L10n("Tap an answer to change it."))
                    .font(.subheadline)
                    .foregroundStyle(OnboardingTheme.secondaryText)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            Button { showsLanguagePicker = true } label: {
                LanguageFlagSymbol()
                    .fill(OnboardingTheme.accentGradient)
                    .frame(width: 16, height: 20)
                    .frame(width: 44, height: 44)
                    .background { Circle().fill(.white.opacity(0.08)) }
                    .overlay { Circle().strokeBorder(OnboardingTheme.hairline, lineWidth: 0.5) }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n("App language"))
            .accessibilityValue(AppLanguageSettings.shared.language.name)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.accentGradient)
                    .frame(width: 44, height: 44)
                    .background { Circle().fill(.white.opacity(0.08)) }
                    .overlay { Circle().strokeBorder(OnboardingTheme.hairline, lineWidth: 0.5) }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n("Close"))
        }
        .padding(.top, 12)
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
        .accessibilityHint(L10n("Opens this question."))
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

/// The waving language flag with a slightly longer, rounded pole.
private struct LanguageFlagSymbol: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: CGRect(x: 0.5, y: 0, width: 1.8, height: 22), cornerSize: CGSize(width: 0.9, height: 0.9))
        path.move(to: CGPoint(x: 2, y: 1.5))
        path.addCurve(to: CGPoint(x: 17.5, y: 2), control1: CGPoint(x: 7, y: -1), control2: CGPoint(x: 11, y: 5))
        path.addLine(to: CGPoint(x: 17.5, y: 13))
        path.addCurve(to: CGPoint(x: 2, y: 12.5), control1: CGPoint(x: 11, y: 16), control2: CGPoint(x: 7, y: 10))
        path.closeSubpath()
        return path.applying(CGAffineTransform(scaleX: rect.width / 18, y: rect.height / 22))
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
        case .religion: "sparkles"
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
