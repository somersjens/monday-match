import SwiftUI

struct AppLanguagePicker: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n("App language"))
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.primaryText)
                    Text(L10n("Choose the language used throughout the app."))
                        .font(.subheadline)
                        .foregroundStyle(OnboardingTheme.secondaryText)
                }
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.accentGradient)
                        .frame(width: 44, height: 44)
                        .background { Circle().fill(.white.opacity(0.08)) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n("Close"))
            }

            VStack(spacing: 0) {
                ForEach(AppLanguage.allCases) { language in
                    let isSelected = AppLanguageSettings.shared.language == language
                    Button {
                        AppLanguageSettings.shared.language = language
                        dismiss()
                    } label: {
                        HStack(spacing: 14) {
                            Text(language.flag)
                                .font(.system(size: 24))
                                .frame(width: 30)
                                .accessibilityHidden(true)
                            Text(language.name)
                                .font(.system(.body, weight: .medium))
                                .foregroundStyle(OnboardingTheme.primaryText)
                            Spacer()
                            OwnMarker(isSelected: isSelected, isActive: true)
                        }
                        .padding(18)
                        .frame(minHeight: 60)
                        .background(OnboardingTheme.blue.opacity(isSelected ? 0.12 : 0))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(language.name)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .onboardingSurface(cornerRadius: 24)
        }
        .padding(24)
        .frame(maxWidth: OnboardingTheme.contentWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 12)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(OnboardingTheme.background)
        .preferredColorScheme(.dark)
    }
}
