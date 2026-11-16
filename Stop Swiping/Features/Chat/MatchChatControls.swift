import SwiftUI

/// The single gear in the chat's top right: your own profile and personality
/// tests, both scores, and the two ways out of a match. Drawn as its own
/// panel so every option fits on one line.
struct MatchSettingsMenu: View {
    let name: String
    let onViewProfile: () -> Void
    let onShowPersonality: () -> Void
    let onShowScores: (MatchReport.Perspective) -> Void
    let onReport: (ReportReason) -> Void
    let onBreak: () -> Void
    /// False once the match is broken: only reporting is left.
    var canBreak = true

    @State private var isOpen = false

    var body: some View {
        Button { isOpen = true } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(OnboardingTheme.accentGradient)
                .frame(width: 44, height: 44)
                .background { Circle().fill(.white.opacity(0.08)) }
                .overlay { Circle().strokeBorder(OnboardingTheme.hairline, lineWidth: 0.5) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n("Match settings"))
        .accessibilityIdentifier("chat.settings")
        .popover(isPresented: $isOpen, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
            MatchSettingsPanel(name: name, canBreak: canBreak) { choice in
                isOpen = false
                if case .personality = choice {
                    // The tests cover the conversation; the keyboard has nothing left to type into.
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                Task {
                    // Let the panel close before a sheet or alert takes over.
                    try? await Task.sleep(for: .milliseconds(380))
                    switch choice {
                    case .profile: onViewProfile()
                    case .personality: onShowPersonality()
                    case .scores(let perspective): onShowScores(perspective)
                    case .report(let reason): onReport(reason)
                    case .breakMatch: onBreak()
                    }
                }
            }
            .presentationCompactAdaptation(.popover)
            // The system's own glass: a custom material here covered the body
            // but not the arrow, so the corner by the gear looked different.
            .preferredColorScheme(.dark)
        }
    }
}

private struct MatchSettingsPanel: View {
    enum Choice {
        case profile
        case personality
        case scores(MatchReport.Perspective)
        case report(ReportReason)
        case breakMatch
    }

    let name: String
    let canBreak: Bool
    let onChoose: (Choice) -> Void

    @State private var showsReasons = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            if showsReasons {
                reasons
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            } else {
                options
                    .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(width: 310)
        .padding(.vertical, 6)
        .animation(.spring(duration: 0.32, bounce: 0.1), value: showsReasons)
    }

    private var options: some View {
        VStack(spacing: 0) {
            row(L10n("View your profile"), symbol: "person.crop.circle") { onChoose(.profile) }
            row(L10n("Your personality tests"), symbol: "brain.head.profile") { onChoose(.personality) }
            divider
            row(L10n("Your match with \(name)"), symbol: "arrow.right.circle") { onChoose(.scores(.yours)) }
            row(L10n("\(name)’s match with you"), symbol: "arrow.left.circle") { onChoose(.scores(.theirs)) }
            divider
            row(L10n("Report your match"), symbol: "exclamationmark.triangle", showsChevron: true) { showsReasons = true }
            if canBreak {
                row(L10n("Break your match"), symbol: "heart.slash", isDestructive: true) { onChoose(.breakMatch) }
            }
        }
    }

    private var reasons: some View {
        VStack(spacing: 0) {
            Button { showsReasons = false } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 24)
                    Text(L10n("Report your match"))
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(OnboardingTheme.primaryText)
                .padding(.horizontal, 16)
                .frame(minHeight: 46)
                .contentShape(Rectangle())
            }
            .buttonStyle(MenuRowStyle())
            divider
            ForEach(ReportReason.allCases) { reason in
                row(reason.title, symbol: reason.symbol) { onChoose(.report(reason)) }
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(OnboardingTheme.hairline).frame(height: 0.5).padding(.vertical, 4)
    }

    private func row(_ title: String, symbol: String, isDestructive: Bool = false,
                     showsChevron: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 24)
                Text(title)
                    .font(.body)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.tertiaryText)
                }
            }
            .foregroundStyle(isDestructive ? Color(red: 1, green: 0.36, blue: 0.4) : OnboardingTheme.primaryText)
            .padding(.horizontal, 16)
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowStyle())
    }
}

private struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.white.opacity(configuration.isPressed ? 0.10 : 0))
    }
}

/// After a reason is picked from the menu: what happened, and whether the
/// match ends too. The other person is never told who reported them.
struct MatchReportSheet: View {
    let name: String
    let onSubmit: (ReportReason, String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason
    @State private var details = ""
    @State private var alsoBreak = false
    @State private var confirmsBreak = false
    @FocusState private var detailsFocused: Bool

    init(name: String, reason: ReportReason, onSubmit: @escaping (ReportReason, String, Bool) -> Void) {
        self.name = name
        self.onSubmit = onSubmit
        _reason = State(initialValue: reason)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(L10n("Reports are private. \(name) will not be told who submitted the report."))
                        .font(.subheadline)
                        .foregroundStyle(OnboardingTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle(L10n("What happened?"))
                        VStack(spacing: 0) {
                            ForEach(ReportReason.allCases) { option in
                                reasonRow(option, isLast: option == ReportReason.allCases.last)
                            }
                        }
                        .onboardingSurface(cornerRadius: 18)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle(L10n("Details"))
                        TextField(L10n("Describe what happened (optional)"), text: $details, axis: .vertical)
                            .lineLimit(3...8)
                            .focused($detailsFocused)
                            .foregroundStyle(OnboardingTheme.primaryText)
                            .tint(OnboardingTheme.cyan)
                            .padding(14)
                            .onboardingSurface(cornerRadius: 16)
                            .onChange(of: details) { _, text in
                                if text.utf8.count > 4000 { details = String(text.prefix(2000)) }
                            }
                    }

                    Toggle(isOn: $alsoBreak) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n("Also break the match"))
                                .foregroundStyle(OnboardingTheme.primaryText)
                            Text(L10n("\(name) can no longer send you messages."))
                                .font(.footnote)
                                .foregroundStyle(OnboardingTheme.secondaryText)
                        }
                    }
                    .tint(OnboardingTheme.violet)
                    .padding(14)
                    .onboardingSurface(cornerRadius: 16)

                    Button(L10n("Send report"), action: submit)
                        .buttonStyle(GlowButtonStyle())
                        .padding(.top, 4)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(OnboardingTheme.background.ignoresSafeArea())
            .navigationTitle(L10n("Report \(name)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n("Cancel")) { dismiss() }
                }
            }
            .alert(L10n("This can’t be undone"), isPresented: $confirmsBreak) {
                Button(L10n("Cancel"), role: .cancel) {}
                Button(L10n("Report and break match"), role: .destructive) { send() }
            } message: {
                Text(L10n("Breaking ends your match with \(name) for both of you."))
            }
        }
        .presentationBackground(OnboardingTheme.background)
        .preferredColorScheme(.dark)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(OnboardingTheme.tertiaryText)
    }

    private func reasonRow(_ option: ReportReason, isLast: Bool) -> some View {
        Button { reason = option } label: {
            HStack(spacing: 12) {
                Image(systemName: option.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(OnboardingTheme.accentGradient)
                    .frame(width: 24)
                Text(option.title)
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: reason == option ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(reason == option ? AnyShapeStyle(OnboardingTheme.accentGradient)
                                                      : AnyShapeStyle(OnboardingTheme.tertiaryText))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(.white.opacity(0.07)).frame(height: 0.5).padding(.leading, 50)
            }
        }
        .accessibilityAddTraits(reason == option ? .isSelected : [])
    }

    private func submit() {
        detailsFocused = false
        if alsoBreak { confirmsBreak = true } else { send() }
    }

    private func send() {
        onSubmit(reason, details.trimmingCharacters(in: .whitespacesAndNewlines), alsoBreak)
        dismiss()
    }
}

/// On the match screen, before the conversation is opened: what the other
/// person has already written, as it would arrive on a lock screen.
struct LiveMessagePreview: View {
    let name: String
    let messages: [ChatMessage]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glows = false

    var body: some View {
        if let last = messages.last {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(OnboardingTheme.cyan)
                        .frame(width: 7, height: 7)
                        .shadow(color: OnboardingTheme.cyan, radius: glows ? 6 : 2)
                    Text(messages.count == 1 ? L10n("New message from \(name)")
                                             : L10n("\(messages.count) new messages from \(name)"))
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(OnboardingTheme.secondaryText)
                }
                ChatBubble(message: last, isFirstInGroup: true)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { glows = true }
            }
        }
    }
}

/// The home screen's way into the active match, with what is new in it.
struct LiveMatchCard: View {
    @ObservedObject var center: LiveMatchCenter
    let onOpen: () -> Void

    var body: some View {
        if let match = center.match {
            let unread = center.unreadMessages
            let count = center.unreadCount
            Button(action: onOpen) {
                HStack(spacing: 14) {
                    RingsBadge()
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(match.partnerName)
                                .font(.system(.body, weight: .semibold))
                                .foregroundStyle(OnboardingTheme.primaryText)
                            Text(match.average, format: .percent)
                                .font(.system(.footnote, design: .rounded, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(OnboardingTheme.cyan)
                        }
                        Text(unread.last?.text ?? (count > 0 ? L10n("New message") : L10n("You have a match. Say hi!")))
                            .font(.footnote)
                            .foregroundStyle(count > 0 ? OnboardingTheme.primaryText.opacity(0.88) : OnboardingTheme.secondaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .frame(minWidth: 22, minHeight: 22)
                            .background { Capsule().fill(OnboardingTheme.buttonGradient) }
                            .shadow(color: OnboardingTheme.blue.opacity(0.6), radius: 6)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(OnboardingTheme.tertiaryText)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onboardingSurface(cornerRadius: 22)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n("Your match with \(match.partnerName), \(match.average) percent"))
            .accessibilityValue(count > 0 ? L10n("\(count) unread") : "")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("home.liveMatch")
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }
}

/// Two small rings, the shape the conversation takes.
private struct RingsBadge: View {
    var body: some View {
        ZStack {
            Circle().strokeBorder(OnboardingTheme.cyan, lineWidth: 1.6).frame(width: 18, height: 18).offset(x: -5)
            Circle().strokeBorder(OnboardingTheme.violet, lineWidth: 1.6).frame(width: 18, height: 18).offset(x: 5)
        }
        .frame(width: 40, height: 40)
        .background { Circle().fill(.white.opacity(0.07)) }
        .shadow(color: OnboardingTheme.blue.opacity(0.5), radius: 6)
        .accessibilityHidden(true)
    }
}
