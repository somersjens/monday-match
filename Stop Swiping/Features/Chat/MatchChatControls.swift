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
            MatchSettingsPanel(kind: .settings(name: name, canBreak: canBreak)) { choice in
                isOpen = false
                switch choice {
                case .personality, .scores:
                    // The tests and the scores cover the conversation; the keyboard has
                    // nothing left to type into. Closed now, while the panel closes: a
                    // keyboard that went down under the opening scores sheet moved it
                    // as it settled, and it came back up when the sheet closed.
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                default: break
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
                    case .close: break
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

/// A broken match's top right, where a live match has no way out: the
/// warning triangle. Whoever broke the match, the other person can still be
/// reported from here, and the match is left from here too.
struct BrokenMatchMenu: View {
    let onReport: (ReportReason) -> Void
    let onClose: () -> Void

    @State private var isOpen = false

    var body: some View {
        Button { isOpen = true } label: {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(OnboardingTheme.accentGradient)
                .frame(width: 44, height: 44)
                .background { Circle().fill(.white.opacity(0.08)) }
                .overlay { Circle().strokeBorder(OnboardingTheme.hairline, lineWidth: 0.5) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n("Report or close"))
        .accessibilityIdentifier("match.brokenMenu")
        .popover(isPresented: $isOpen, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
            MatchSettingsPanel(kind: .broken) { choice in
                isOpen = false
                Task {
                    // Let the panel close before the report sheet or the
                    // way back takes over.
                    try? await Task.sleep(for: .milliseconds(380))
                    switch choice {
                    case .report(let reason): onReport(reason)
                    case .close: onClose()
                    default: break
                    }
                }
            }
            .presentationCompactAdaptation(.popover)
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
        case close
    }

    enum Kind {
        /// The gear: your profile, both scores and the ways out of a match.
        /// `canBreak` is false once the match is broken.
        case settings(name: String, canBreak: Bool)
        /// A broken match's warning triangle: reporting and leaving.
        case broken
    }

    let kind: Kind
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

    @ViewBuilder
    private var options: some View {
        switch kind {
        case .settings(let name, let canBreak): settingsOptions(name: name, canBreak: canBreak)
        case .broken: brokenOptions
        }
    }

    private var brokenOptions: some View {
        VStack(spacing: 0) {
            row(L10n("Report your match"), symbol: "exclamationmark.triangle", showsChevron: true) { showsReasons = true }
            divider
            row(L10n("Close"), symbol: "xmark") { onChoose(.close) }
        }
    }

    private func settingsOptions(name: String, canBreak: Bool) -> some View {
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

    private static let destructive = Color(red: 1, green: 0.36, blue: 0.4)

    private var divider: some View {
        Rectangle().fill(OnboardingTheme.hairline).frame(height: 0.5).padding(.vertical, 4)
    }

    private func row(_ title: String, symbol: String, isDestructive: Bool = false,
                     showsChevron: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isDestructive ? AnyShapeStyle(Self.destructive)
                                                   : AnyShapeStyle(OnboardingTheme.accentGradient))
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
            .foregroundStyle(isDestructive ? Self.destructive : OnboardingTheme.primaryText)
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
/// match ends too. With one match at a time, a report may be traced back to
/// whoever made it, so the screen says so up front.
struct MatchReportSheet: View {
    let match: MatchSnapshot
    /// The conversation to put in the PDF; the demo's too.
    let chat: ChatViewModel?
    /// For the PDF: the other person's photo, or your own in the demo.
    let photo: UIImage?
    let onSubmit: (ReportReason, String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reason: ReportReason
    @State private var showsReasons = false
    @State private var details = ""
    @State private var alsoBreak = false
    @State private var confirmsBreak = false
    @State private var export: ExportedFile?
    @State private var exportFailed = false
    @FocusState private var detailsFocused: Bool

    private var name: String { match.name }

    init(match: MatchSnapshot, chat: ChatViewModel?, photo: UIImage?, reason: ReportReason,
         onSubmit: @escaping (ReportReason, String, Bool) -> Void) {
        self.match = match
        self.chat = chat
        self.photo = photo
        self.onSubmit = onSubmit
        _reason = State(initialValue: reason)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle(L10n("Reason"))
                    reasonPicker
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle(L10n("Details"))
                    TextField(L10n("Describe what happened (optional)"), text: $details, axis: .vertical)
                        .lineLimit(7...14)
                        .focused($detailsFocused)
                        .submitLabel(.done)
                        .foregroundStyle(OnboardingTheme.primaryText)
                        .tint(OnboardingTheme.cyan)
                        .padding(14)
                        .onboardingSurface(cornerRadius: 16)
                        .onChange(of: details) { _, text in
                            // Return closes the keyboard instead of starting a new line.
                            if text.contains("\n") {
                                details = text.replacingOccurrences(of: "\n", with: "")
                                detailsFocused = false
                                return
                            }
                            if text.utf8.count > 4000 { details = String(text.prefix(2000)) }
                        }
                }

                // Once the match is broken there is nothing left to break.
                if !match.isBroken { breakToggle }

                policeCard

                Button(L10n("Send report"), action: submit)
                    .buttonStyle(GlowButtonStyle())
                    .padding(.top, 4)
            }
            .frame(maxWidth: OnboardingTheme.contentWidth)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
            // A tap anywhere outside the text field closes the keyboard.
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { detailsFocused = false }
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(OnboardingTheme.background.ignoresSafeArea())
        .alert(L10n("This can’t be undone"), isPresented: $confirmsBreak) {
            Button(L10n("Cancel"), role: .cancel) {}
            Button(L10n("Report and break match"), role: .destructive) { send() }
        } message: {
            Text(L10n("Breaking ends your match with \(name) for both of you."))
        }
        .alert(L10n("Could not create the PDF"), isPresented: $exportFailed) {
            Button(L10n("OK"), role: .cancel) {}
        }
        .sheet(item: $export) { file in
            ShareSheet(items: [file.url])
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
        .presentationBackground(OnboardingTheme.background)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .headerTitle, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n("Report \(name)"))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .headerTitleGuide()
                Text(L10n("Reporting can affect \(name)’s account. Because you can only be matched with one person at a time, a report may be traced back to you. Please keep this in mind."))
                    .font(.subheadline)
                    .foregroundStyle(OnboardingTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.accentGradient)
                    .frame(width: 44, height: 44)
                    .background { Circle().fill(.white.opacity(0.08)) }
                    .overlay { Circle().strokeBorder(OnboardingTheme.hairline, lineWidth: 0.5) }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n("Back"))
        }
    }

    private var breakToggle: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n("Also break the match"))
                    .foregroundStyle(OnboardingTheme.primaryText)
                Text(L10n("\(name) can no longer send you messages."))
                    .font(.footnote)
                    .foregroundStyle(OnboardingTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
            GlowToggle(isOn: alsoBreak, label: L10n("Also break the match")) {
                alsoBreak.toggle()
            }
        }
        .padding(14)
        .onboardingSurface(cornerRadius: 16)
        .onChange(of: alsoBreak) { detailsFocused = false }
    }

    /// For anything criminal: the police, with the conversation and profile in hand.
    private var policeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n("In case of a criminal offence, go to the police"))
                .font(.subheadline)
                .foregroundStyle(OnboardingTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

            Rectangle().fill(.white.opacity(0.07)).frame(height: 0.5).padding(.leading, 14)

            Button(action: exportPDF) {
                HStack(spacing: 12) {
                    Text(L10n("Download chat and profile as PDF"))
                        .foregroundStyle(OnboardingTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(OnboardingTheme.accentGradient)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("report.exportPDF")
        }
        .onboardingSurface(cornerRadius: 16)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(OnboardingTheme.tertiaryText)
    }

    /// The reason was already picked from the menu, so it shows as one row;
    /// tapping it unfolds the other reasons in place, under it.
    private var reasonPicker: some View {
        VStack(spacing: 0) {
            Button {
                detailsFocused = false
                withAnimation(reasonAnimation) { showsReasons.toggle() }
            } label: {
                reasonLabel(reason) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.tertiaryText)
                        .rotationEffect(.degrees(showsReasons ? 180 : 0))
                }
                // The new reason takes its place at once, without sliding.
                .transaction(value: reason) { $0.animation = nil }
            }
            .buttonStyle(MenuRowStyle())
            .accessibilityLabel(L10n("Reason"))
            .accessibilityValue(reason.title)
            .accessibilityIdentifier("report.reason")

            if showsReasons {
                VStack(spacing: 0) {
                    ForEach(ReportReason.allCases.filter { $0 != reason }) { option in
                        Rectangle().fill(.white.opacity(0.07)).frame(height: 0.5).padding(.leading, 50)
                        Button {
                            reason = option
                            withAnimation(reasonAnimation) { showsReasons = false }
                        } label: {
                            reasonLabel(option) { EmptyView() }
                        }
                        .buttonStyle(MenuRowStyle())
                    }
                }
                .transition(.opacity)
            }
        }
        .clipShape(.rect(cornerRadius: 16))
        .onboardingSurface(cornerRadius: 16)
    }

    private var reasonAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.3)
    }

    private func reasonLabel<Trailing: View>(_ option: ReportReason,
                                             @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Image(systemName: option.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(OnboardingTheme.accentGradient)
                .frame(width: 24)
            Text(option.title)
                .foregroundStyle(OnboardingTheme.primaryText)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func exportPDF() {
        detailsFocused = false
        let document = MatchReportExport(match: match, messages: chat?.conversation.messages ?? [],
                                         isDemo: chat?.isDemo ?? false, photo: photo)
        do {
            export = ExportedFile(url: try document.writeTemporaryFile())
        } catch {
            exportFailed = true
        }
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

private struct ExportedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// The system share sheet, where a file can be saved to Files or sent on.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
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
