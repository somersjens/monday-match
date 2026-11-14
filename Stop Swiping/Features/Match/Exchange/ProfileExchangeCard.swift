import SwiftUI

/// Shown while the profile is being shared: how the code is scanned, and
/// who nearby is sharing too.
struct ProfileExchangeCard: View {
    @ObservedObject var session: ProfileExchangeSession

    private static let visiblePeople = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                icon

                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n("Let someone else scan your code"))
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(session.people.isEmpty
                         ? L10n("Then see on their phone whether you’re a match. They scan with the camera button at the top right, or with their iPhone’s camera.")
                         : L10n("Then see on their phone whether you’re a match. Or hold your phones together, top to top."))
                        .font(.footnote)
                        .foregroundStyle(OnboardingTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }
                .accessibilityElement(children: .combine)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if let notice = session.notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(OnboardingTheme.pink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }

            ForEach(session.people.prefix(Self.visiblePeople)) { person in
                divider
                row(person)
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
                        colors: [OnboardingTheme.cyan.opacity(session.people.isEmpty ? 0.25 : 0.55),
                                 OnboardingTheme.violet.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .animation(.easeInOut(duration: 0.25), value: session.people)
        .animation(.easeInOut(duration: 0.25), value: session.notice)
    }

    private func row(_ person: ProfileExchangeSession.Person) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .lineLimit(1)
                Text(status(person))
                    .font(.caption)
                    .foregroundStyle(person.wantsToExchange && !person.isWaiting
                                     ? OnboardingTheme.cyan : OnboardingTheme.secondaryText)
                    .lineLimit(2)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            if person.isWaiting {
                Button(L10n("Cancel")) { session.decline(person.id) }
                    .buttonStyle(ExchangeChipStyle(isProminent: false))
                    .accessibilityLabel(L10n("Cancel exchanging with \(person.name)"))
            } else {
                if person.wantsToExchange {
                    Button { session.decline(person.id) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 20)
                    }
                    .buttonStyle(ExchangeChipStyle(isProminent: false))
                    .accessibilityLabel(L10n("Don’t exchange with \(person.name)"))
                }
                Button(L10n("Exchange")) { session.confirm(person.id) }
                    .buttonStyle(ExchangeChipStyle(isProminent: true))
                    .accessibilityLabel(L10n("Exchange profiles with \(person.name)"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func status(_ person: ProfileExchangeSession.Person) -> String {
        if person.isWaiting { return L10n("Waiting for \(person.name)…") }
        if person.wantsToExchange { return L10n("Wants to exchange profiles") }
        return L10n("Nearby and sharing")
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.07))
            .frame(height: 0.5)
            .padding(.leading, 16)
    }

    private var icon: some View {
        Image(systemName: session.people.isEmpty ? "qrcode.viewfinder" : "dot.radiowaves.left.and.right")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(LinearGradient(
                colors: [OnboardingTheme.cyan, OnboardingTheme.violet],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: session.isActive && !session.people.isEmpty)
            .frame(width: 36, height: 36)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(.white.opacity(0.12))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

private struct ExchangeChipStyle: ButtonStyle {
    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.footnote, weight: .semibold))
            .foregroundStyle(.white.opacity(isProminent ? 1 : 0.82))
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background {
                Capsule().fill(isProminent ? AnyShapeStyle(OnboardingTheme.buttonGradient)
                                           : AnyShapeStyle(.white.opacity(0.10)))
            }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
