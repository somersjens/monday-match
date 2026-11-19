import SwiftUI

struct EarlyAccessView: View {
    /// The select circle and the benefit checkmarks share one column.
    private static let selectorWidth: CGFloat = 22
    /// The outline of the chosen plan, in the Continue button's blue-to-violet.
    private static let selectedOutline = LinearGradient(
        colors: [Color(red: 0.30, green: 0.52, blue: 1), OnboardingTheme.violet],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    @ObservedObject var access: LifetimeAccessStore
    let onContinue: () -> Void
    var onBack: (() -> Void)?
    var usesSharedLight = false
    /// An unfinished questionnaire's progress, shown above the plans once the
    /// free early-adopter plan is gone. That plan is claimed only once, before
    /// any answer counts, so while it is offered there is no progress to show.
    var questionnaireProgress: Double?
    /// The profile is finished: the plans come back because paid access
    /// ended (a monthly plan that ran out, a refund), not to finish it.
    var profileIsComplete = false

    @State private var selection = LifetimeProductID.lifetime
    @State private var hasAppeared = false
    /// The reminder above the footer, which the plans scroll clear of.
    @State private var reminderHeight: CGFloat = 0
    /// How much of the extra room of a wide window (iPad, iPhone Duo open)
    /// the plans use, from 0 on an iPhone to 1 on an iPad, continuously.
    @State private var roominess: CGFloat = 0
    @State private var showsPrivacyPolicy = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    private var canContinue: Bool {
        guard access.isReady, !access.isBusy, !access.isRequestingReminder else { return false }
        if access.hasPaidAccess || (selection == .earlyAdopter && access.hasAccess) { return true }
        if selection == .earlyAdopter && access.isEarlyAccessRevealed { return true }
        return access.product(selection) != nil && (selection != .earlyAdopter || access.product(.lifetime) != nil)
    }

    /// The plan next to lifetime access: the free one while it lasts, and
    /// only after that the monthly plan, so nobody pays monthly for what
    /// they could have had free.
    private var secondPlan: LifetimeProductID {
        access.canOfferEarlyAccess ? .earlyAdopter : .monthly
    }

    var body: some View {
        ZStack {
            if !usesSharedLight {
                Color("WelcomeBackground").ignoresSafeArea()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: spaced(12, 20)) {
                    if let questionnaireProgress, !access.canOfferEarlyAccess {
                        OnboardingProgressCard(progress: questionnaireProgress)
                            .padding(.bottom, 6)
                            .accessArrival(visible: hasAppeared, delay: 0.12)
                    }
                    lifetimeCard
                        .accessArrival(visible: hasAppeared, delay: 0.22)
                    planCard(secondPlan)
                        .id(secondPlan)
                        .accessArrival(visible: hasAppeared, delay: 0.34)
                        .transition(.opacity.combined(with: .offset(y: 16)))
                    if secondPlan == .monthly {
                        if profileIsComplete {
                            Text(L10n("Your access has ended. Choose a plan to keep using Stop Swiping. Your profile and answers are still here."))
                                .font(.footnote)
                                .foregroundStyle(OnboardingTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessArrival(visible: hasAppeared, delay: 0.4)
                        } else if access.ledger.effectiveStartedAt != nil {
                            Text(L10n("Your early-adopter deadline has passed. Choose a plan to finish your profile."))
                                .font(.footnote)
                                .foregroundStyle(OnboardingTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessArrival(visible: hasAppeared, delay: 0.4)
                        }
                        subscriptionTerms
                            .accessArrival(visible: hasAppeared, delay: 0.4)
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
                .padding(.top, spaced(8, 24))
                .padding(.bottom, spaced(12, 20) + (showsReminder ? reminderHeight : 0))
                .frame(maxWidth: .infinity)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                roominess = min(1, max(0, (width - 440) / (744 - 440)))
            }
            .safeAreaInset(edge: .top, spacing: 0) { lightNavigation }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                footer.accessArrival(visible: hasAppeared, delay: 0.46)
            }
            // The welcome screen moves its light by the same inset.
            .adaptiveStageHeight()
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .task {
            hasAppeared = true
            await access.start()
            keepSelectionAvailable()
        }
        .sheet(isPresented: $showsPrivacyPolicy) { PrivacyPolicyView() }
        .sensoryFeedback(.selection, trigger: selection)
        // A purchase or a restore that went through.
        .sensoryFeedback(.success, trigger: access.hasPaidAccess) { _, paid in paid }
        .soundFeedback(.success, trigger: access.hasPaidAccess) { _, paid in paid }
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

    /// What Apple asks to show with a subscription: that it renews, how to
    /// cancel, and the terms and privacy policy.
    private var subscriptionTerms: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n("The monthly plan renews automatically until you cancel it. Cancel anytime in your Apple Account settings, at least 24 hours before the next renewal."))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                Link(L10n("Terms of Use"), destination: Self.termsOfUse)
                Button(L10n("Privacy Policy")) { showsPrivacyPolicy = true }
                    .buttonStyle(.plain)
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(OnboardingTheme.cyan)
        }
        .font(.system(size: 11.5))
        .foregroundStyle(OnboardingTheme.tertiaryText)
    }

    /// Apple's standard licence agreement, which the app uses.
    private static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    private func title(_ id: LifetimeProductID) -> String {
        switch id {
        case .earlyAdopter: L10n("Early Adopter Benefits")
        case .monthly: L10n("Monthly Access")
        case .lifetime, .subscriberLifetime: L10n("Lifetime Access")
        }
    }

    @ViewBuilder
    private func benefits(_ id: LifetimeProductID) -> some View {
        switch id {
        case .earlyAdopter:
            benefit(L10n("Be among the first to join"))
            benefit(L10n("Free forever:"), detail: L10n("You'll never have to pay"))
            benefit(L10n("Ad-free forever:"), detail: L10n("Enjoy the app without ads"))
        case .monthly:
            benefit(L10n("Low monthly cost:"), detail: L10n("Still includes all features"))
            benefit(L10n("Cancel anytime:"), detail: L10n("No long-term commitment"))
            benefit(L10n("No big upfront cost:"), detail: L10n("See if you like it first"))
        case .lifetime, .subscriberLifetime:
            benefit(L10n("One-time payment:"), detail: L10n("No subscription, ever"))
            benefit(L10n("All features included:"), detail: L10n("Now and in the future"))
            benefit(L10n("Support us:"), detail: L10n("Help improve the app"))
        }
    }

    private func planCard(_ id: LifetimeProductID) -> some View {
        let early = id == .earlyAdopter
        let selected = selection == id
        return Button {
            if selection != id { SoundPlayer.shared.play(.select) }
            withAnimation(OnboardingMotion.resolved(OnboardingMotion.selection, reduceMotion: reduceMotion)) {
                selection = id
            }
        } label: {
            VStack(alignment: .leading, spacing: spaced(10, 14)) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 21, weight: .light))
                        .foregroundStyle(selected ? AnyShapeStyle(OnboardingTheme.accentGradient)
                                                  : AnyShapeStyle(OnboardingTheme.tertiaryText))
                        .frame(width: Self.selectorWidth)
                        .accessibilityHidden(true)
                    Text(title(id))
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
                        } else if id.isSubscription {
                            Text(L10n("per month")).font(.system(size: 12))
                                .foregroundStyle(OnboardingTheme.tertiaryText)
                        }
                    }
                    .layoutPriority(1)
                }
                Rectangle().fill(OnboardingTheme.hairline).frame(height: 1)
                VStack(alignment: .leading, spacing: spaced(7, 10)) {
                    benefits(id)
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
            .padding(spaced(16, 22))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 22)
                    .fill(selected ? OnboardingTheme.blue.opacity(0.10) : OnboardingTheme.surface)
                    .overlay {
                        ZStack {
                            RoundedRectangle(cornerRadius: 22)
                                .strokeBorder(OnboardingTheme.hairline, lineWidth: 1)
                                .opacity(selected ? 0 : 1)
                            RoundedRectangle(cornerRadius: 22)
                                .strokeBorder(Self.selectedOutline, lineWidth: 1.5)
                                .opacity(selected ? 1 : 0)
                        }
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .disabled(access.isBusy)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier(early ? "access.earlyAdopter" : id.isSubscription ? "access.monthly" : "access.lifetime")
    }

    private func benefit(_ title: String, detail: String? = nil) -> some View {
        // Same column and spacing as the select circle, so each checkmark sits
        // under it and the text lines up with the plan's title.
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(OnboardingTheme.cyan)
                .frame(width: Self.selectorWidth)
                .padding(.top, 4)
                .accessibilityHidden(true)
            Text("\(Text(title).fontWeight(.semibold))\(detail.map { " \($0)" } ?? "")")
                .font(.system(size: 13))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// `compact` on an iPhone, `roomy` on an iPad, in between while a window
    /// is resized or an iPhone Duo unfolds.
    private func spaced(_ compact: CGFloat, _ roomy: CGFloat) -> CGFloat {
        compact + (roomy - compact) * roominess
    }

    private var showsReminder: Bool {
        selection == .earlyAdopter && access.canOfferEarlyAccess
    }

    /// The footer keeps one height, so the Continue button never moves: the
    /// reminder rises above it instead of pushing it, and the plans make room
    /// for it at the end of their scroll.
    ///
    /// Continue and Restore purchases sit exactly where the landing page's
    /// Get started and account link are, and where the questionnaire's
    /// Continue and Back follow, so the buttons stay put between the screens.
    private var footer: some View {
        VStack(spacing: 12) {
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
            .buttonStyle(QuietButtonStyle())
            .disabled(access.isBusy)
        }
        .frame(maxWidth: OnboardingTheme.controlWidth)
        .padding(.horizontal, 28)
        // With the reminder's own 4 pt below it, the same 12 pt as above.
        .padding(.top, 8)
        .controlsBottomPadding()
        .frame(maxWidth: .infinity)
        .background(Color("WelcomeBackground"))
        .overlay(alignment: .top) {
            ZStack {
                if showsReminder {
                    ReminderRow(isOn: access.ledger.reminderEnabled,
                                isDisabled: access.isRequestingReminder || access.isBusy) {
                        Task { await access.setReminderEnabled(!access.ledger.reminderEnabled) }
                    }
                    .frame(maxWidth: OnboardingTheme.controlWidth)
                    .padding(.horizontal, 28)
                    .padding(.top, 6)
                    .frame(maxWidth: .infinity)
                    .background(Color("WelcomeBackground"))
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { reminderHeight = $0 }
                    .transition(.reminderReveal(reduceMotion: reduceMotion))
                }
            }
            // The row's bottom rests on the footer's top edge.
            .alignmentGuide(.top) { $0[.bottom] }
        }
        .animation(OnboardingMotion.resolved(.spring(duration: 0.55, bounce: 0.14), reduceMotion: reduceMotion),
                   value: selection)
    }

    /// Progress is worth showing once the questionnaire has begun: after a
    /// first answer, or once an early-adopter window was started. The view
    /// still hides it while the free plan is offered.
    static func questionnaireProgress(_ progress: Double, hasStartedEarlyAccess: Bool) -> Double? {
        return progress > 0 || hasStartedEarlyAccess ? progress : nil
    }

    private func keepSelectionAvailable() {
        if selection != .lifetime && selection != secondPlan {
            selection = .lifetime
        }
    }
}

/// The reminder switch under the early-adopter card. The row resolves out of
/// a soft blur while the switch follows a beat later with a small spring.
private struct ReminderRow: View {
    let isOn: Bool
    let isDisabled: Bool
    let action: () -> Void

    @State private var switchVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Text(L10n("Send reminder 1 day before deadline"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isOn ? OnboardingTheme.primaryText : OnboardingTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: isOn)
            Spacer(minLength: 0)
            GlowToggle(isOn: isOn, label: L10n("Send reminder 1 day before deadline"), action: action)
                .disabled(isDisabled)
                .accessibilityIdentifier("access.reminder")
                .opacity(switchVisible ? 1 : 0)
                .scaleEffect(switchVisible || reduceMotion ? 1 : 0.7)
                .offset(x: switchVisible || reduceMotion ? 0 : 10)
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        // The same height and corners as the Continue button below it.
        .frame(minHeight: OnboardingTheme.buttonHeight)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(isOn ? OnboardingTheme.blue.opacity(0.10) : OnboardingTheme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(isOn ? OnboardingTheme.cyan.opacity(0.35) : OnboardingTheme.hairline,
                                      lineWidth: 1)
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: isOn)
        }
        .padding(.bottom, 4)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.18)
                          : .spring(duration: 0.5, bounce: 0.32).delay(0.12)) {
                switchVisible = true
            }
        }
    }
}

private struct ReminderRevealEffect: ViewModifier {
    let offset: CGFloat
    let blur: CGFloat
    let scale: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale, anchor: .bottom)
            .offset(y: offset)
            .blur(radius: blur)
            .opacity(opacity)
    }
}

private extension AnyTransition {
    static func reminderReveal(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .modifier(
                active: ReminderRevealEffect(offset: 14, blur: 8, scale: 0.94, opacity: 0),
                identity: ReminderRevealEffect(offset: 0, blur: 0, scale: 1, opacity: 1)
            ),
            removal: .modifier(
                active: ReminderRevealEffect(offset: 8, blur: 6, scale: 0.97, opacity: 0),
                identity: ReminderRevealEffect(offset: 0, blur: 0, scale: 1, opacity: 1)
            ).animation(.easeOut(duration: 0.2))
        )
    }
}
