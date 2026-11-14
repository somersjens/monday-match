import SwiftUI

struct EarlyAccessView: View {
    @ObservedObject var access: LifetimeAccessStore
    let onContinue: () -> Void
    var onBack: (() -> Void)?
    var usesSharedLight = false

    @State private var selection = LifetimeProductID.lifetime
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    private var canContinue: Bool {
        guard access.isReady, !access.isBusy, !access.isRequestingReminder else { return false }
        if access.hasPaidAccess || (selection == .earlyAdopter && access.hasAccess) { return true }
        if selection == .earlyAdopter && access.isEarlyAccessRevealed { return true }
        return access.product(selection) != nil && (selection != .earlyAdopter || access.product(.lifetime) != nil)
    }

    var body: some View {
        ZStack {
            if !usesSharedLight {
                Color("WelcomeBackground").ignoresSafeArea()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    lifetimeCard
                        .accessArrival(visible: hasAppeared, delay: 0.16)
                    if access.canOfferEarlyAccess {
                        planCard(.earlyAdopter)
                            .accessArrival(visible: hasAppeared, delay: 0.28)
                            .transition(.opacity.combined(with: .offset(y: 16)))
                    } else {
                        Text(L10n("Your early-adopter deadline has passed. Continue with lifetime access to finish your profile."))
                            .font(.footnote)
                            .foregroundStyle(OnboardingTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessArrival(visible: hasAppeared, delay: 0.28)
                    }
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
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { lightNavigation }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer.accessArrival(visible: hasAppeared, delay: 0.40)
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .task {
            hasAppeared = true
            await access.start()
            keepSelectionAvailable()
        }
        .onChange(of: access.canOfferEarlyAccess) { _, _ in
            withAnimation(OnboardingMotion.resolved(OnboardingMotion.selection, reduceMotion: reduceMotion)) {
                keepSelectionAvailable()
            }
        }
    }

    /// Tapping the light, or pulling it down, reverses the shared transition.
    /// On the welcome screen the artwork belongs to the parent so its phase and
    /// Metal surface continue unchanged; standalone access routes draw it here.
    private var lightNavigation: some View {
        ZStack {
            if !usesSharedLight {
                WelcomeLightAnimation(skipsEntrance: true)
                    .frame(width: 300, height: 630)
                    .scaleEffect(AccessScreenMotion.lightScale(for: 300))
                    .position(x: 80, y: AccessScreenMotion.lightCenterY)
            }
            Button(action: goBack) {
                Rectangle().fill(.white.opacity(0.001))
                    .frame(width: 160, height: AccessScreenMotion.headerHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(access.isBusy)
            .accessibilityLabel(L10n("Back"))
            .accessibilityIdentifier("access.back")
            .simultaneousGesture(DragGesture(minimumDistance: 12).onEnded { gesture in
                if gesture.translation.height > 24 { goBack() }
            })
        }
        .frame(width: 160, height: AccessScreenMotion.headerHeight)
        .frame(maxWidth: .infinity)
    }

    private func goBack() {
        guard !access.isBusy else { return }
        if let onBack { onBack() }
        else { dismiss() }
    }

    private var lifetimeCard: some View {
        planCard(.lifetime)
            .simultaneousGesture(LongPressGesture(minimumDuration: 3).onEnded { _ in
                guard !access.isBusy else { return }
                access.revealEarlyAccess()
                selection = .earlyAdopter
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
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 21, weight: .light))
                        .foregroundStyle(selected ? OnboardingTheme.cyan : OnboardingTheme.tertiaryText)
                        .accessibilityHidden(true)
                    Text(early ? L10n("Early Adopter Benefits") : L10n("Lifetime Access"))
                        .font(.system(size: 17, weight: .semibold))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(access.product(id)?.displayPrice ?? "—")
                            .font(.system(size: 20, weight: .semibold))
                            .tracking(-0.3)
                            .minimumScaleFactor(0.65)
                            .lineLimit(1)
                        if early, let price = access.product(.lifetime)?.displayPrice {
                            Text(price).font(.system(size: 12)).strikethrough()
                                .foregroundStyle(OnboardingTheme.tertiaryText)
                        }
                    }
                    .layoutPriority(1)
                }
                Rectangle().fill(OnboardingTheme.hairline).frame(height: 1)
                VStack(alignment: .leading, spacing: 7) {
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
                        .font(.system(size: 11.5)).italic()
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
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 22)
                    .fill(selected ? OnboardingTheme.blue.opacity(0.10) : OnboardingTheme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(selected ? OnboardingTheme.cyan.opacity(0.65) : OnboardingTheme.hairline,
                                          lineWidth: selected ? 1.4 : 1)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .disabled(access.isBusy)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier(early ? "access.earlyAdopter" : "access.lifetime")
    }

    private func benefit(_ title: String, detail: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(OnboardingTheme.cyan)
                .padding(.top, 4)
                .accessibilityHidden(true)
            Text("\(Text(title).fontWeight(.semibold))\(detail.map { " \($0)" } ?? "")")
                .font(.system(size: 13))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
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
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .background(Color("WelcomeBackground"))
        .animation(OnboardingMotion.resolved(OnboardingMotion.selection, reduceMotion: reduceMotion), value: selection)
    }

    private func keepSelectionAvailable() {
        if selection == .earlyAdopter && !access.canOfferEarlyAccess {
            selection = .lifetime
        }
    }
}
