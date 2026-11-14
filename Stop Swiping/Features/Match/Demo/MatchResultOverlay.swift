import SwiftUI

/// How far the match screen's labels have appeared, following the light.
enum MatchReveal: Int, Comparable {
    case hidden
    case average
    case scores
    case issues
    case controls

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Maps the light's normalized space to points on screen.
struct MatchStageFrame {
    /// Screen position of the light's origin.
    let center: CGPoint
    /// Points per normalized unit.
    let unit: CGFloat

    func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: center.x + CGFloat(x) * unit, y: center.y + CGFloat(y) * unit)
    }
}

/// Everything around the match heart: the average in the heart, both scores
/// on the line from its tip, the reasons when there is no match, and the
/// buttons to keep or delete the match.
struct MatchResultOverlay: View {
    let match: MatchSnapshot
    let report: MatchReport
    let frame: MatchStageFrame
    let reveal: MatchReveal
    let isSaved: Bool
    var lightTransition: WelcomeLightMatch.Transition = .newMatch
    var lightStartedAt = Date()
    let onShowScores: (MatchReport.Perspective) -> Void
    let onShowProfile: () -> Void
    let onRename: (String) -> Void
    let onSave: () -> Void
    let onClose: () -> Void
    let onDelete: () -> Void
    var onRestartDemo: (() -> Void)? = nil
    var onUnderstandDemo: (() -> Void)? = nil
    /// The conversation behind a match the server made, or the demo's.
    var chat: ChatViewModel? = nil
    /// The heart has become the rings and the conversation is open.
    var isChatting = false
    /// From the top of this view to the bottom of the rings while chatting.
    var chatRingsBottom: CGFloat = 0
    var onSendMessage: () -> Void = {}
    /// Holding Save match opens a made-up conversation, before launch.
    var onStartDemoChat: () -> Void = {}
    var onViewProfile: () -> Void = {}
    var onBreakMatch: () -> Void = {}
    var onReport: (ReportReason, String, Bool) -> Void = { _, _, _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmsDeletion = false
    @State private var confirmsDeletionAgain = false
    @State private var confirmsBreak = false
    @State private var confirmsBreakAgain = false
    @State private var reportReason: ReportReason?
    @State private var showsNameEditor = false
    @State private var hasMoreIssuesBelow = false

    private let issueListPadding: CGFloat = 18
    private var layout: WelcomeLightMatch.Layout { .of(isMatch: report.isMatch) }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                ZStack {
                    if isChatting {
                        chatHeader
                            .transition(.opacity.combined(with: .offset(y: -6)))
                    } else {
                        header
                            .transition(.opacity)
                    }
                }
                .opacity(reveal >= .average ? 1 : 0)
                .allowsHitTesting(reveal >= .average)
                .accessibilityHidden(reveal < .average)
                .zIndex(1)

                TimelineView(.animation(minimumInterval: 1.0 / 60,
                    paused: lightTransition != .savedMatch || reduceMotion || reveal == .controls)) { timeline in
                    let progress = timeline.date.timeIntervalSince(lightStartedAt) / WelcomeLightMatch.Transition.savedMorphDuration
                    let offset = lightTransition == .savedMatch && !reduceMotion && reveal != .controls
                        ? WelcomeLightMatch.sharedOffset(progress: progress, layout: layout) : 0
                    let movingFrame = MatchStageFrame(
                        center: CGPoint(x: frame.center.x, y: frame.center.y + offset * frame.unit), unit: frame.unit)
                    ZStack {
                        average
                            .position(movingFrame.point(0, layout.heartCenterY))
                            .opacity(reveal >= .average ? 1 : 0)
                            .scaleEffect(reveal >= .average || reduceMotion ? 1 : 0.92)

                        score(.yours, x: -WelcomeLightMatch.scoreX, frame: movingFrame)
                        score(.theirs, x: WelcomeLightMatch.scoreX, frame: movingFrame)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    // The numbers step aside as the heart becomes the rings.
                    .opacity(isChatting ? 0 : 1)
                    .scaleEffect(isChatting && !reduceMotion ? 0.9 : 1)
                    .allowsHitTesting(!isChatting)
                    .accessibilityHidden(isChatting)
                }

                if isChatting, let chat {
                    MatchChatPanel(chat: chat, ringsBottom: chatRingsBottom,
                                   headerHeight: MatchChatLayout.headerHeight)
                        .padding(.top, MatchChatLayout.headerHeight)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .transition(.opacity.animation(.easeOut(duration: 0.5).delay(reduceMotion ? 0 : 0.6)))
                }

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                        .frame(height: max(0, frame.point(0, layout.lineY).y + 68))
                    if !report.isMatch {
                        issues
                            .opacity(reveal >= .issues ? 1 : 0)
                            .offset(y: reveal >= .issues || reduceMotion ? 0 : 8)
                    }
                    Spacer(minLength: 12)
                    if let onRestartDemo, let onUnderstandDemo {
                        VStack(spacing: 12) {
                            Button(L10n("Play from the beginning"), action: onRestartDemo)
                                .buttonStyle(GlowButtonStyle())
                            Button(L10n("I fully understand"), action: onUnderstandDemo)
                                .buttonStyle(QuietButtonStyle())
                        }
                        .frame(maxWidth: OnboardingTheme.controlWidth)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 18)
                        .opacity(reveal >= .controls ? 1 : 0)
                        .allowsHitTesting(reveal >= .controls)
                    } else {
                        controls
                            .opacity(reveal >= .controls ? 1 : 0)
                            .allowsHitTesting(reveal >= .controls)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .opacity(isChatting ? 0 : 1)
                .offset(y: isChatting && !reduceMotion ? 30 : 0)
                .allowsHitTesting(!isChatting)
                .accessibilityHidden(isChatting)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .alert(L10n("This can’t be undone"), isPresented: $confirmsDeletion) {
            Button(L10n("Cancel"), role: .cancel) {}
            Button(L10n("Continue"), role: .destructive) {
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    confirmsDeletionAgain = true
                }
            }
        } message: {
            Text(L10n("Deleting removes your match with \(match.name) for good."))
        }
        .background {
            Color.clear
                .alert(L10n("Delete your match with \(match.name)?"), isPresented: $confirmsDeletionAgain) {
                    Button(L10n("Cancel"), role: .cancel) {}
                    Button(L10n("Delete match"), role: .destructive, action: onDelete)
                } message: {
                    Text(L10n("Are you sure? This is your last chance to keep it."))
                }
        }
        .alert(L10n("This can’t be undone"), isPresented: $confirmsBreak) {
            Button(L10n("Cancel"), role: .cancel) {}
            Button(L10n("Continue"), role: .destructive) {
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    confirmsBreakAgain = true
                }
            }
        } message: {
            Text(L10n("Breaking ends your match with \(match.name) for both of you."))
        }
        .background {
            Color.clear
                .alert(L10n("Break your match with \(match.name)?"), isPresented: $confirmsBreakAgain) {
                    Button(L10n("Cancel"), role: .cancel) {}
                    Button(L10n("Break match"), role: .destructive, action: onBreakMatch)
                } message: {
                    Text(L10n("Are you sure? This is your last chance to keep it."))
                }
        }
        .sheet(item: $reportReason) { reason in
            MatchReportSheet(name: match.name, reason: reason, onSubmit: onReport)
        }
        .animation(.easeInOut(duration: reduceMotion ? 0.2 : 0.55), value: isChatting)
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Button { showsNameEditor = true } label: {
                    HStack(spacing: 9) {
                        Text(match.name)
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                            .foregroundStyle(OnboardingTheme.primaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(OnboardingTheme.tertiaryText)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ScoreButtonStyle())
                .accessibilityLabel(match.name)
                .accessibilityHint(L10n("Edit match name"))
                .accessibilityIdentifier("match.rename")
                .popover(isPresented: $showsNameEditor, arrowEdge: .top) {
                    MatchNameEditor(name: match.name) { name in
                        onRename(name)
                        showsNameEditor = false
                    }
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground(OnboardingTheme.background)
                    .preferredColorScheme(.dark)
                }
                Text(match.matchedAt.formatted(.dateTime.day().month(.wide).year().hour().minute().locale(AppLocale.current)))
                    .font(.footnote)
                    .foregroundStyle(OnboardingTheme.secondaryText)
            }

            Spacer(minLength: 0)

            Button(action: onShowProfile) {
                Image(systemName: "person.text.rectangle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.accentGradient)
                    .frame(width: 44, height: 44)
                    .background { Circle().fill(.white.opacity(0.08)) }
                    .overlay { Circle().strokeBorder(OnboardingTheme.hairline, lineWidth: 0.5) }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n("Show \(match.name)’s answers"))
            .accessibilityIdentifier("match.profile")

            if isSaved || match.isLive {
                Button(action: onClose) {
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
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    /// While chatting: back, who it is, and one gear for everything else.
    private var chatHeader: some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.accentGradient)
                    .frame(width: 44, height: 44)
                    .background { Circle().fill(.white.opacity(0.08)) }
                    .overlay { Circle().strokeBorder(OnboardingTheme.hairline, lineWidth: 0.5) }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n("Back"))
            .accessibilityIdentifier("chat.back")

            VStack(alignment: .leading, spacing: 1) {
                Text(match.name)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .lineLimit(1)
                if let chat {
                    ChatHeaderSubtitle(chat: chat, matchedAt: match.matchedAt, average: report.average)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            MatchSettingsMenu(name: match.name, onViewProfile: onViewProfile, onShowScores: onShowScores,
                              onReport: { reportReason = $0 }, onBreak: { confirmsBreak = true })
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .frame(height: MatchChatLayout.headerHeight, alignment: .top)
    }

    private var average: some View {
        VStack(spacing: 6 * layout.scale) {
            Text("\(report.average)%")
                .font(.system(size: frame.unit * 0.46 * layout.scale, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .shadow(color: OnboardingTheme.blue.opacity(0.8), radius: 14)
            Text(report.isMatch ? L10n("Match") : L10n("No match"))
                .font(.system(size: 14, weight: .medium))
                .tracking(4)
                .textCase(.uppercase)
                .foregroundStyle(report.isMatch ? Color.white.opacity(0.88) : OnboardingTheme.pink)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(report.isMatch
            ? L10n("\(report.average) percent, a match")
            : L10n("\(report.average) percent, no match"))
    }

    /// The number sits above the line and its label below it.
    private func score(_ perspective: MatchReport.Perspective, x: Double, frame: MatchStageFrame) -> some View {
        let numberHeight: CGFloat = frame.unit * 0.30
        let gap: CGFloat = 22
        let labelHeight: CGFloat = 34
        let line = frame.point(x, layout.lineY)
        return Button { onShowScores(perspective) } label: {
            VStack(spacing: 0) {
                Text("\(report.score(perspective))%")
                    .font(.system(size: frame.unit * 0.25, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .shadow(color: OnboardingTheme.blue.opacity(0.7), radius: 10)
                    .frame(height: numberHeight, alignment: .bottom)
                Color.clear.frame(height: gap)
                Text(perspective == .yours ? L10n("Your match\nwith \(match.name)") : L10n("\(match.name)’s match\nwith you"))
                    .font(.system(size: 11, weight: .medium))
                    .tracking(1.6)
                    .textCase(.uppercase)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(OnboardingTheme.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(height: labelHeight, alignment: .top)
            }
            .frame(width: frame.unit * 0.95)
            .contentShape(Rectangle())
        }
        .buttonStyle(ScoreButtonStyle())
        .position(x: line.x, y: line.y + (numberHeight + gap + labelHeight) / 2 - numberHeight - gap / 2)
        .opacity(reveal >= .scores ? 1 : 0)
        .allowsHitTesting(reveal >= .scores)
        .accessibilityLabel(perspective == .yours
            ? L10n("Your match with \(match.name): \(report.score(perspective)) percent")
            : L10n("\(match.name)’s match with you: \(report.score(perspective)) percent"))
        .accessibilityHint(L10n("Shows the answers behind this score."))
    }

    /// Their requirements you miss come after yours they miss. Scrolls
    /// only when the list is taller than the room above the buttons.
    private var issues: some View {
        ViewThatFits(in: .vertical) {
            issueList
            VStack(spacing: 0) {
                ScrollView { issueList }
                    .scrollIndicators(.hidden)
                    .onScrollGeometryChange(for: Bool.self) { geometry in
                        // Only hidden rows count, not the padding below the last issue.
                        geometry.contentOffset.y + geometry.containerSize.height
                            < geometry.contentSize.height - issueListPadding - 1
                    } action: { _, hasMore in
                        hasMoreIssuesBelow = hasMore
                    }

                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 14)
                    .padding(.bottom, 6)
                    .opacity(hasMoreIssuesBelow ? 1 : 0)
                    .accessibilityHidden(true)
            }
        }
        .onboardingSurface(cornerRadius: 22)
        .frame(maxWidth: OnboardingTheme.controlWidth)
        .padding(.horizontal, 28)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n("Why there is no match"))
    }

    private var issueList: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(report.theirIssues.enumerated()), id: \.offset) { _, issue in
                issueRow(issue)
            }
            if !report.theirIssues.isEmpty && !report.yourIssues.isEmpty {
                Rectangle()
                    .fill(OnboardingTheme.hairline)
                    .frame(height: 0.5)
                    .accessibilityHidden(true)
            }
            ForEach(Array(report.yourIssues.enumerated()), id: \.offset) { _, issue in
                issueRow(issue)
            }
        }
        .padding(issueListPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func issueRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(OnboardingTheme.pink)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundStyle(OnboardingTheme.primaryText.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            if match.isLive && report.isMatch, let chat {
                // A match the server made: both met every requirement and
                // cleared each other's minimum score, so they can talk.
                LiveMatchControls(chat: chat, name: match.name, onSendMessage: onSendMessage, onClose: onClose)
            } else {
                if isSaved {
                    Button(L10n("Close"), action: onClose)
                        .buttonStyle(GlowButtonStyle())
                } else {
                    Button(L10n("Save match"), action: onSave)
                        .buttonStyle(GlowButtonStyle())
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 3)
                                .onEnded { _ in onStartDemoChat() }
                        )
                        .accessibilityAction(named: L10n("Start a demo conversation"), onStartDemoChat)
                        .accessibilityIdentifier("match.save")
                }
                Button(L10n("Delete match")) { confirmsDeletion = true }
                    .buttonStyle(QuietButtonStyle())
            }
        }
        .frame(maxWidth: OnboardingTheme.controlWidth)
        .padding(.horizontal, 28)
        .padding(.bottom, 18)
        .animation(.easeInOut(duration: 0.25), value: isSaved)
    }
}

/// An anchored editor keeps the match visible while its local name is changed.
private struct MatchNameEditor: View {
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @FocusState private var isFocused: Bool

    init(name: String, onSave: @escaping (String) -> Void) {
        _name = State(initialValue: name)
        self.onSave = onSave
    }

    private var normalizedName: String { ProfileNameRules.normalized(name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(L10n("Edit match name"), systemImage: "pencil.line")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(OnboardingTheme.primaryText)
                .accessibilityAddTraits(.isHeader)

            TextField(L10n("Match name"), text: $name)
                .font(.system(.body, weight: .medium))
                .foregroundStyle(OnboardingTheme.primaryText)
                .tint(OnboardingTheme.cyan)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isFocused)
                .onSubmit(save)
                .padding(14)
                .onboardingSurface(cornerRadius: 14)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(OnboardingTheme.cyan.opacity(isFocused ? 0.4 : 0), lineWidth: 1)
                }
                .accessibilityIdentifier("match.nameField")
                .onChange(of: name) { _, value in
                    if value.count > ProfileNameRules.maximumLength {
                        name = String(value.prefix(ProfileNameRules.maximumLength))
                    }
                }

            HStack(spacing: 12) {
                Button(L10n("Cancel")) { dismiss() }
                    .buttonStyle(QuietButtonStyle())
                Button(L10n("Save"), action: save)
                    .buttonStyle(GlowButtonStyle())
                    .disabled(normalizedName.isEmpty)
                    .accessibilityIdentifier("match.saveName")
            }
        }
        .padding(22)
        .frame(idealWidth: 310, maxWidth: 340)
        .task { isFocused = true }
    }

    private func save() {
        guard !normalizedName.isEmpty else { return }
        isFocused = false
        onSave(normalizedName)
    }
}

private struct ScoreButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Under a live match: what the other person already wrote, and the way in.
private struct LiveMatchControls: View {
    @ObservedObject var chat: ChatViewModel
    let name: String
    let onSendMessage: () -> Void
    let onClose: () -> Void

    var body: some View {
        let unread = chat.unreadMessages
        VStack(spacing: 12) {
            if !unread.isEmpty {
                LiveMessagePreview(name: name, messages: unread)
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
            Button(unread.isEmpty ? L10n("Send a message") : L10n("Reply to \(name)"), action: onSendMessage)
                .buttonStyle(GlowButtonStyle())
                .accessibilityIdentifier("match.sendMessage")
            Button(L10n("Close"), action: onClose)
                .buttonStyle(QuietButtonStyle())
        }
        .animation(.spring(duration: 0.45, bounce: 0.2), value: unread.count)
    }
}

/// "typing…" while the other person writes, otherwise when you matched.
private struct ChatHeaderSubtitle: View {
    @ObservedObject var chat: ChatViewModel
    let matchedAt: Date
    let average: Int

    var body: some View {
        Group {
            if chat.isPartnerTyping {
                Text(L10n("typing…"))
                    .foregroundStyle(OnboardingTheme.cyan)
            } else {
                Text(L10n("\(average)% match · \(matchedAt.formatted(.dateTime.day().month(.abbreviated).locale(AppLocale.current)))"))
                    .foregroundStyle(OnboardingTheme.secondaryText)
            }
        }
        .font(.footnote)
        .lineLimit(1)
        .animation(.easeInOut(duration: 0.2), value: chat.isPartnerTyping)
    }
}
