import SwiftUI

struct EarlyAccessView: View {
    @ObservedObject var access: LifetimeAccessStore
    let onContinue: () -> Void
    var onBack: (() -> Void)?

    @State private var selection = LifetimeProductID.earlyAdopter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var canContinue: Bool {
        guard access.isReady, !access.isBusy, !access.isRequestingReminder else { return false }
        if access.hasPaidAccess || (selection == .earlyAdopter && access.hasAccess) { return true }
        #if DEBUG
        if selection == .earlyAdopter && access.developmentOfferEnabled { return true }
        #endif
        return access.product(selection) != nil && (selection != .earlyAdopter || access.product(.lifetime) != nil)
    }

    var body: some View {
        ZStack {
            OnboardingTheme.background.ignoresSafeArea()
            RadialGradient(colors: [OnboardingTheme.blue.opacity(0.17), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 470)
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if access.canOfferEarlyAccess {
                        planCard(.earlyAdopter)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    lifetimeCard
                    if access.products.isEmpty {
                        VStack(spacing: 8) {
                            Text(L10n("Store prices are currently unavailable."))
                                .font(.footnote)
                                .foregroundStyle(OnboardingTheme.secondaryText)
                            Button(L10n("Try again")) { Task { await access.refresh() } }
                                .font(.footnote.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    if let message = access.errorMessage {
                        Text(message).font(.footnote).foregroundStyle(.pink)
                            .accessibilityIdentifier("access.error")
                    }
                    if let notice = access.notice {
                        Text(notice).font(.footnote).foregroundStyle(OnboardingTheme.secondaryText)
                    }
                }
                .frame(maxWidth: OnboardingTheme.contentWidth)
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .task {
            await access.start()
            updateSelection()
        }
        .onChange(of: access.canOfferEarlyAccess) { _, _ in
            withAnimation(OnboardingMotion.resolved(OnboardingMotion.selection, reduceMotion: reduceMotion)) {
                updateSelection()
            }
        }
        .accessibilityIdentifier("access.screen")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let onBack {
                Button(action: onBack) {
                    Label(L10n("Back"), systemImage: "chevron.left")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(OnboardingTheme.secondaryText)
                        .frame(minHeight: 44)
                }
                .disabled(access.isBusy)
            }
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(OnboardingTheme.cyan)
                .accessibilityHidden(true)
            Text(L10n("A connection worth keeping."))
                .font(.system(size: 31, weight: .semibold))
                .tracking(-0.8)
                .accessibilityAddTraits(.isHeader)
            Text(access.canOfferEarlyAccess
                 ? L10n("Choose your way in. Make it yours forever.")
                 : L10n("Your early-adopter deadline has passed. Continue with lifetime access to finish your profile."))
                .font(.subheadline)
                .foregroundStyle(OnboardingTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var lifetimeCard: some View {
        planCard(.lifetime)
            .simultaneousGesture(LongPressGesture(minimumDuration: 3).onEnded { _ in
                #if DEBUG
                guard !access.isBusy else { return }
                access.revealDevelopmentOffer()
                selection = .earlyAdopter
                #endif
            })
    }

    private func planCard(_ id: LifetimeProductID) -> some View {
        let early = id == .earlyAdopter
        let selected = selection == id
        return Button {
            withAnimation(OnboardingMotion.resolved(OnboardingMotion.selection, reduceMotion: reduceMotion)) {
                selection = id
            }
        } label: {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        if early {
                            Text(L10n("EARLY ADOPTER"))
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1.5)
                                .foregroundStyle(OnboardingTheme.cyan)
                        }
                        Text(early ? L10n("Early Adopter Benefits") : L10n("Lifetime Access"))
                            .font(.system(size: 20, weight: .semibold))
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(selected ? OnboardingTheme.cyan : OnboardingTheme.tertiaryText)
                        .accessibilityHidden(true)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(access.product(id)?.displayPrice ?? "—")
                        .font(.system(size: 37, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                    if early, let price = access.product(.lifetime)?.displayPrice {
                        Text(price).font(.title3).strikethrough()
                            .foregroundStyle(OnboardingTheme.tertiaryText)
                    }
                }
                Rectangle().fill(OnboardingTheme.hairline).frame(height: 1)
                VStack(alignment: .leading, spacing: 12) {
                    if early {
                        benefit(L10n("Be among the first to join"))
                        benefit(L10n("Free forever:"), detail: L10n("You'll never have to pay"))
                        benefit(L10n("Ad-free forever:"), detail: L10n("Enjoy the app without ads"))
                    } else {
                        benefit(L10n("One-time payment:"), detail: L10n("No subscription, ever"))
                        benefit(L10n("All features included:"), detail: L10n("Full access to current and future features"))
                        benefit(L10n("Support our development:"), detail: L10n("Help us keep improving the app"))
                    }
                }
                if early {
                    Text(L10n("To unlock these benefits, complete your profile within 7 days of signing up."))
                        .font(.system(size: 12)).italic()
                        .foregroundStyle(OnboardingTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let deadline = access.ledger.deadline {
                        Text(L10n("Complete before \(deadline.formatted(date: .abbreviated, time: .shortened))"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(OnboardingTheme.cyan)
                    }
                }
            }
            .foregroundStyle(OnboardingTheme.primaryText)
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 26)
                    .fill(selected ? OnboardingTheme.blue.opacity(0.10) : OnboardingTheme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 26)
                            .strokeBorder(selected ? OnboardingTheme.cyan.opacity(0.65) : OnboardingTheme.hairline,
                                          lineWidth: selected ? 1.4 : 1)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 26))
        }
        .buttonStyle(.plain)
        .disabled(access.isBusy)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier(early ? "access.earlyAdopter" : "access.lifetime")
    }

    private func benefit(_ title: String, detail: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(OnboardingTheme.cyan)
                .padding(.top, 4)
                .accessibilityHidden(true)
            (Text(title).fontWeight(.semibold) + Text(detail.map { " \($0)" } ?? ""))
                .font(.system(size: 14))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if selection == .earlyAdopter && access.canOfferEarlyAccess {
                HStack(spacing: 16) {
                    Text(L10n("Send reminder 1 day before deadline"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(OnboardingTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    GlowToggle(isOn: access.ledger.reminderEnabled,
                               label: L10n("Send reminder 1 day before deadline")) {
                        Task { await access.setReminderEnabled(!access.ledger.reminderEnabled) }
                    }
                    .disabled(access.isRequestingReminder || access.isBusy)
                    .accessibilityIdentifier("access.reminder")
                }
            }
            Button {
                Task {
                    if await access.continueWith(selection) { onContinue() }
                }
            } label: {
                HStack(spacing: 10) {
                    if access.isBusy { ProgressView().tint(.white) }
                    Text(L10n("Continue"))
                }
            }
            .buttonStyle(GlowButtonStyle())
            .disabled(!canContinue)
            .accessibilityIdentifier("access.continue")
            Button(L10n("Restore purchases")) {
                Task {
                    await access.restorePurchases()
                    if access.hasAccess { onContinue() }
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(OnboardingTheme.secondaryText)
            .frame(minHeight: 32)
            .disabled(access.isBusy)
        }
        .frame(maxWidth: OnboardingTheme.controlWidth)
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(OnboardingTheme.background)
    }

    private func updateSelection() {
        selection = access.canOfferEarlyAccess ? .earlyAdopter : .lifetime
    }
}
