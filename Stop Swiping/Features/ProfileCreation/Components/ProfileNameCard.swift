import SwiftUI

/// Asks for a first name on the home screen. Auto matching and the demo
/// match only appear once a name is saved.
struct ProfileNameCard: View {
    @ObservedObject var viewModel: ProfileCreationViewModel
    @FocusState private var isFocused: Bool

    @State private var name = ""

    private var canSave: Bool { !ProfileNameRules.normalized(name).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n("What’s your first name?"))
                .font(.system(.footnote, weight: .medium))
                .foregroundStyle(OnboardingTheme.secondaryText)
                .accessibilityHidden(true)

            HStack(spacing: 10) {
                TextField("", text: $name, prompt: Text(L10n("First name")).foregroundStyle(OnboardingTheme.tertiaryText))
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .tint(OnboardingTheme.cyan)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isFocused)
                    .onSubmit(save)
                    .accessibilityLabel(L10n("First name"))
                    .onChange(of: name) { _, value in
                        if value.count > ProfileNameRules.maximumLength {
                            name = String(value.prefix(ProfileNameRules.maximumLength))
                        }
                    }

                Button(action: save) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white.opacity(canSave ? 1 : 0.45))
                        .frame(width: 40, height: 40)
                        .background {
                            Circle()
                                .fill(OnboardingTheme.buttonGradient)
                                .opacity(canSave ? 1 : 0.35)
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .accessibilityLabel(L10n("Save name"))
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .padding(.vertical, 14)
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
                        colors: [OnboardingTheme.cyan.opacity(isFocused ? 0.6 : 0.3), OnboardingTheme.violet.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    private func save() {
        guard canSave else { return }
        isFocused = false
        viewModel.setDisplayName(name)
    }
}

/// The name in Adjust profile, edited in place.
struct ProfileNameRow: View {
    @ObservedObject var viewModel: ProfileCreationViewModel

    @State private var name = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LinearGradient(
                    colors: [OnboardingTheme.cyan, OnboardingTheme.violet],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 36, height: 36)
                .background {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(.white.opacity(0.06))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n("Name"))
                    .font(.footnote)
                    .foregroundStyle(OnboardingTheme.secondaryText)
                    .accessibilityHidden(true)
                TextField("", text: $name, prompt: Text(L10n("First name")).foregroundStyle(OnboardingTheme.tertiaryText))
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .tint(OnboardingTheme.cyan)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isFocused)
                    .onSubmit(commit)
                    .accessibilityLabel(L10n("Name"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OnboardingTheme.tertiaryText)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .onAppear { name = viewModel.state.displayName }
        .onDisappear(perform: commit)
        .onChange(of: isFocused) { _, focused in
            if !focused { commit() }
        }
        .onChange(of: name) { _, value in
            if value.count > ProfileNameRules.maximumLength {
                name = String(value.prefix(ProfileNameRules.maximumLength))
            }
        }
    }

    /// Clearing the field removes the name and restarts the next actions.
    private func commit() {
        viewModel.setDisplayName(name, allowsEmpty: true)
        name = viewModel.state.displayName
    }
}
