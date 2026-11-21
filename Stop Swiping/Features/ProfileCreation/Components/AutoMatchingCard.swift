import SwiftUI

/// The home screen's auto matching switch and entry to its setup flow.
struct AutoMatchingCard: View {
    @ObservedObject var viewModel: ProfileCreationViewModel
    let onOpenSettings: () -> Void

    @State private var resumeFailed = false

    var body: some View {
        let settings = viewModel.state.autoMatching
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button(action: onOpenSettings) {
                    HStack(spacing: 4) {
                        Text(L10n("Join auto matching"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if settings.isEnabled {
                            Text(verbatim: "· \(L10nPercent(settings.minimumMatchPercent))")
                                .foregroundStyle(OnboardingTheme.secondaryText)
                                .fixedSize()
                                .layoutPriority(1)
                        }
                    }
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityHint(L10n("Auto matching settings"))

                GlowToggle(isOn: settings.isEnabled, label: L10n("Join auto matching")) {
                    resumeFailed = false
                    if settings.isEnabled {
                        viewModel.leaveAutoMatching()
                    } else if viewModel.canResumeAutoMatching {
                        resumeFailed = !viewModel.resumeAutoMatching()
                    } else {
                        onOpenSettings()
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: OnboardingTheme.buttonHeight)

            if resumeFailed {
                Text(L10n("Auto matching couldn’t be saved. Try again."))
                    .font(.footnote)
                    .foregroundStyle(OnboardingTheme.pink)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .modifier(MatchingActionSurface(isOn: settings.isEnabled))
        .animation(.easeInOut(duration: 0.25), value: settings.isEnabled)
    }
}

/// Half-price lifetime access for monthly subscribers, as tall as the auto
/// matching card it sits above. Closing it hides it for a month.
struct SubscriberLifetimeOfferCard: View {
    @ObservedObject var access: LifetimeAccessStore

    /// Why the last purchase didn't go through, shown under the offer.
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button(action: buy) {
                    HStack(spacing: 8) {
                        // Two short lines rather than one long one, so the
                        // offer reads in full on the narrowest iPhone too.
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L10n("Lifetime Access"))
                                .font(.system(.body, weight: .semibold))
                            Text(L10n("\(L10nPercent(50)) off for subscribers"))
                                .font(.system(.footnote, weight: .medium))
                                .foregroundStyle(OnboardingTheme.cyan)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if access.isBusy {
                            ProgressView().tint(.white)
                        } else if let price = access.product(.subscriberLifetime)?.displayPrice {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(price)
                                    .font(.system(.body, weight: .semibold))
                                if let full = access.product(.lifetime)?.displayPrice {
                                    Text(full)
                                        .font(.system(size: 12))
                                        .strikethrough()
                                        .foregroundStyle(OnboardingTheme.tertiaryText)
                                }
                            }
                            .fixedSize()
                        }
                    }
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(access.isBusy)
                .accessibilityIdentifier("offer.subscriberLifetime")

                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(OnboardingTheme.secondaryText)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(access.isBusy)
                .accessibilityLabel(L10n("Close offer"))
            }
            .padding(.leading, 16)
            .padding(.trailing, 4)
            .frame(minHeight: OnboardingTheme.buttonHeight)

            if let message = failure {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(OnboardingTheme.pink)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .modifier(MatchingActionSurface(isOn: true))
    }

    private func buy() {
        Task {
            // The store then asks to cancel the monthly plan (CancelSubscriptionReminder).
            failure = nil
            if await !access.continueWith(.subscriberLifetime) {
                failure = access.errorMessage ?? access.notice
            }
        }
    }

    private func close() {
        SoundPlayer.shared.play(.close)
        withAnimation(.easeInOut(duration: 0.25)) { access.dismissSubscriberOffer() }
    }
}

/// The sentence the app uses wherever it asks to cancel the monthly plan.
enum CancelSubscriptionCopy {
    static var message: String {
        L10n("Now that you have lifetime access, you can cancel your subscription; otherwise you’ll keep paying.")
    }
}

/// Right after lifetime access was bought on top of a monthly plan. No app
/// can cancel a plan (Apple and Google both leave that to the person), so
/// ask at once; the home screen's card keeps asking until it is cancelled.
struct CancelSubscriptionReminder: ViewModifier {
    @ObservedObject var access: LifetimeAccessStore

    func body(content: Content) -> some View {
        content
            .alert(L10n("Lifetime access unlocked"), isPresented: $access.asksToCancelSubscription) {
                if !access.cancelsOnAnotherAppleID {
                    Button(L10n("Cancel subscription")) { Task { await access.manageSubscription() } }
                }
                Button(L10n("Not now"), role: .cancel) {}
            } message: {
                Text(CancelSubscriptionCopy.message)
            }
    }
}

/// Lifetime access while a monthly plan will still be charged: stays on the
/// home screen until the store says the plan no longer renews. The whole
/// sentence always shows, on every screen width and text size.
struct CancelSubscriptionCard: View {
    @ObservedObject var access: LifetimeAccessStore
    @State private var isOpening = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(CancelSubscriptionCopy.message)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(OnboardingTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if access.cancelsOnAnotherAppleID {
                // This phone's Apple ID isn't the one being charged.
                Text(L10n("Your subscription runs on another Apple ID. Cancel it in Settings on the iPhone or iPad you subscribed with."))
                    .font(.footnote)
                    .foregroundStyle(OnboardingTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button(action: open) {
                    HStack(spacing: 8) {
                        Text(L10n("Cancel subscription"))
                        if isOpening { ProgressView().tint(OnboardingTheme.cyan) }
                    }
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.cyan)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isOpening)
                .accessibilityIdentifier("offer.cancelMonthly")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, access.cancelsOnAnotherAppleID ? 14 : 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(MatchingActionSurface(isOn: true))
        .accessibilityElement(children: .contain)
    }

    private func open() {
        isOpening = true
        Task {
            await access.manageSubscription()
            isOpening = false
        }
    }
}

/// The account step of the home screen. Its switch slides on and the card
/// opens in place into Apple and Google sign-in, so the helix stays on
/// screen. Once signed in the card keeps its height and confirms it where the
/// switch was, then sinks away while the next step rises in its place;
/// sliding the switch back closes it again.
struct AccountCreationCard: View {
    enum Phase: Equatable {
        case closed
        case open
        case signedIn
        /// The confirmed card fades out while the next step takes over.
        case handover

        var isSignedIn: Bool { self == .signedIn || self == .handover }
    }

    let phase: Phase
    @ObservedObject var signIn: SignInViewModel
    let onToggle: () -> Void
    let onAuthenticated: (RestoredSession) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isLocked: Bool { phase.isSignedIn || signIn.isSigningIn }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button(action: onToggle) {
                    // The checkmark follows the text, so the label starts where
                    // the other cards' labels do.
                    HStack(spacing: 8) {
                        Text(phase.isSignedIn ? L10n("You’re signed in") : L10n("Create your account"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .contentTransition(.opacity)
                            .id(phase.isSignedIn)
                            .transition(.onboardingReveal(reduceMotion: reduceMotion))
                        if phase.isSignedIn {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(OnboardingTheme.accentGradient)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                        }
                    }
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)

                // The card's opening and closing already sound.
                GlowToggle(isOn: phase != .closed, label: L10n("Create your account"), playsSound: false,
                           action: onToggle)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: OnboardingTheme.buttonHeight)
            .disabled(isLocked)

            // Signed in, the sign-in buttons fade but keep their room, so the
            // confirmation stays where the switch was slid.
            if phase != .closed {
                VStack(spacing: 10) {
                    Text(L10n("Keep your profile safe and let your matches reach you."))
                        .font(.footnote)
                        .foregroundStyle(OnboardingTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                        .padding(.top, -8)
                        .padding(.bottom, 4)

                    AccountSignInButtons(viewModel: signIn, height: 52, cornerRadius: 12,
                                         onAuthenticated: onAuthenticated)

                    if let message = signIn.errorMessage {
                        AccountSignInError(message: message)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 2)
                            .transition(.onboardingReveal(reduceMotion: reduceMotion))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .opacity(phase == .open ? 1 : 0)
                .blur(radius: phase == .open || reduceMotion ? 0 : 6)
                .allowsHitTesting(phase == .open)
                .accessibilityHidden(phase != .open)
                .transition(.onboardingReveal(reduceMotion: reduceMotion))
            }
        }
        .modifier(MatchingActionSurface(isOn: phase != .closed))
        .landingDeparture(phase == .handover, reduceMotion: reduceMotion)
        .animation(.easeInOut(duration: 0.2), value: signIn.errorMessage)
    }
}

/// Asks for notification permission. The switch slides on while the system
/// prompt is open; the decision itself then replaces this card.
struct NotificationPermissionCard: View {
    let isRequesting: Bool
    let onAllow: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onAllow) {
                Text(L10n("Allow notifications"))
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)

            GlowToggle(isOn: isRequesting, label: L10n("Allow notifications"), action: onAllow)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: OnboardingTheme.buttonHeight)
        .modifier(MatchingActionSurface(isOn: isRequesting))
        .disabled(isRequesting)
    }
}

struct MatchingActionSurface: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        content
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(
                    colors: [OnboardingTheme.blue.opacity(0.20), OnboardingTheme.violet.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [OnboardingTheme.cyan.opacity(isOn ? 0.55 : 0.25), OnboardingTheme.violet.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
}
