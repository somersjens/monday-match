import SwiftUI

/// Chat preserves the match heart's full-size canvas and shoulder position.
/// Reserve the same space in the scroll view, including the moving ribbon glow.
enum MatchChatLayout {
    static let headerHeight: CGFloat = 64

    static func ringsBottom(unit: CGFloat, lightCenterY: CGFloat) -> CGFloat {
        lightCenterY + CGFloat(WelcomeLightMatch.Chat.bottomExtent) * unit
    }

    /// Leave a readable message below the fade when the keyboard reduces
    /// the viewport, while keeping the artwork in its original position.
    static func messageFade(viewportHeight: CGFloat, ringsBottom: CGFloat, headerHeight: CGFloat) -> (clear: CGFloat, gradient: CGFloat) {
        let gradient = min(100, max(0, viewportHeight) * 0.3)
        let clear = min(max(0, ringsBottom - headerHeight - 90), max(0, viewportHeight - gradient - 112))
        return (clear, gradient)
    }
}

/// The conversation under the rings: text only, newest at the bottom, with
/// the composer above the keyboard.
struct MatchChatPanel: View {
    @ObservedObject var chat: ChatViewModel
    /// From the top of the panel to the bottom of the rings.
    let ringsBottom: CGFloat
    let headerHeight: CGFloat

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var composerFocused: Bool
    @State private var showsSecurityCode = false
    @State private var showsDeviceReplacement = false
    /// Read only when the keyboard opens, so scrolling never redraws the panel.
    @State private var scrollEdge = ScrollEdgeTracker()

    private var visibleMessages: [ChatMessage] { chat.conversation.messages }

    var body: some View {
        VStack(spacing: 0) {
            messages
            status
            if chat.conversation.isClosed {
                closedBanner
            } else {
                composer
            }
        }
        // On iPad and iPhone Duo open, messages keep a readable line length
        // instead of running from edge to edge.
        .readableColumn()
        .task(id: scenePhase == .active) {
            guard chat.isLive, scenePhase == .active else { return }
            chat.isOnScreen = true
            chat.noteActivity()
            defer { chat.isOnScreen = false }
            while !Task.isCancelled {
                await chat.refresh()
                chat.markAllRead()
                if chat.conversation.isClosed { return }
                do { try await Task.sleep(for: chat.pollInterval) } catch { return }
            }
        }
        .onChange(of: chat.conversation.messages.count) { old, new in
            chat.markAllRead()
            playMessageSound(from: old, to: new)
        }
        .sheet(isPresented: $showsSecurityCode) { securitySheet }
        .confirmationDialog(L10n("Use this iPhone for this chat?"), isPresented: $showsDeviceReplacement, titleVisibility: .visible) {
            Button(L10n("Switch to this iPhone")) { Task { await chat.replaceDevice() } }
            Button(L10n("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n("The previous device will stop receiving new messages. Unsent messages on this iPhone will be discarded. History from other devices cannot be recovered here. Compare the new security code with your match."))
        }
    }

    // MARK: - Messages

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    notice
                        .padding(.bottom, 14)
                    ForEach(Array(visibleMessages.enumerated()), id: \.element.id) { index, message in
                        let previous = index > 0 ? visibleMessages[index - 1] : nil
                        if previous.map({ !Calendar.current.isDate($0.sentAt, inSameDayAs: message.sentAt) }) ?? true {
                            dayChip(message.sentAt)
                                .padding(.vertical, 10)
                        }
                        ChatBubble(message: message,
                                   isFirstInGroup: previous?.sender != message.sender,
                                   isRead: chat.isReadByPartner(message),
                                   isDelivered: chat.isDelivered(message))
                            .padding(.top, previous?.sender == message.sender ? 2 : 8)
                            .id(message.id)
                            .transition(reduceMotion ? .opacity
                                : .asymmetric(insertion: .scale(scale: 0.85, anchor: message.sender == .currentUser ? .bottomTrailing : .bottomLeading)
                                    .combined(with: .opacity), removal: .opacity))
                    }
                    if chat.isPartnerTyping {
                        TypingBubble()
                            .padding(.top, 8)
                            .id("typing")
                            .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .bottomLeading)))
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, 14)
                .padding(.top, max(0, ringsBottom - headerHeight))
                .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.2), value: visibleMessages.count)
                .animation(.easeInOut(duration: 0.2), value: chat.isPartnerTyping)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .mask {
                // Messages dissolve into the rings instead of running over them.
                GeometryReader { proxy in
                    let fade = MatchChatLayout.messageFade(viewportHeight: proxy.size.height,
                                                           ringsBottom: ringsBottom, headerHeight: headerHeight)
                    VStack(spacing: 0) {
                        Color.clear.frame(height: fade.clear)
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: fade.gradient)
                        Color.black
                    }
                }
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.visibleRect.maxY >= geometry.contentSize.height - 24
            } action: { _, atBottom in
                scrollEdge.isAtBottom = atBottom
            }
            .onChange(of: visibleMessages.last?.id) { _, _ in scrollToBottom(proxy) }
            .onChange(of: chat.isPartnerTyping) { _, _ in scrollToBottom(proxy) }
            .onChange(of: composerFocused) { _, focused in
                // At the bottom, the bottom anchor already keeps the newest
                // message above the rising keyboard. A second, animated scroll
                // started halfway through the keyboard's slide made it stutter.
                guard focused, !scrollEdge.isAtBottom else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    scrollToBottom(proxy)
                }
            }
        }
    }

    /// A message just sent or just arrived. A history loading in stays quiet.
    private func playMessageSound(from old: Int, to new: Int) {
        guard new > old, let message = chat.conversation.messages.last,
              Date().timeIntervalSince(message.sentAt) < 30 else { return }
        SoundPlayer.shared.play(message.sender == .currentUser ? .messageSent : .messageReceived)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private var notice: some View {
        // The same for a demo and a live match: how long the server keeps
        // the conversation (see 202611180003_retention_and_identity_hmac.sql).
        // The icon sits inline in the text so the whole notice centres,
        // including when it wraps onto a second line.
        Text("\(Image(systemName: "clock.arrow.circlepath")) \(L10n("Chat history is kept for up to 12 months, even after the match is broken."))")
            .font(.caption2)
            .foregroundStyle(OnboardingTheme.secondaryText)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background { Capsule().fill(.white.opacity(0.06)) }
            .overlay { Capsule().strokeBorder(OnboardingTheme.hairline, lineWidth: 0.5) }
            .frame(maxWidth: 300)
    }

    private func dayChip(_ date: Date) -> some View {
        Text(Self.dayTitle(date))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(OnboardingTheme.secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background { Capsule().fill(.white.opacity(0.07)) }
    }

    private static func dayTitle(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return L10n("Today") }
        if Calendar.current.isDateInYesterday(date) { return L10n("Yesterday") }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(AppLocale.current))
    }

    // MARK: - Status

    @ViewBuilder
    private var status: some View {
        if chat.isLive && !chat.conversation.isClosed {
            VStack(spacing: 6) {
                if let error = chat.errorMessage {
                    Button { Task { await chat.refresh() } } label: {
                        Label(L10n(AppLocalizedMessage(stringLiteral: error)), systemImage: "arrow.clockwise")
                    }
                    .foregroundStyle(OnboardingTheme.pink)
                } else if !chat.isReady && !chat.requiresKeyConfirmation && !chat.requiresDeviceReplacement {
                    Text(L10n("Waiting for \(chat.conversation.participantName) to open this conversation."))
                        .foregroundStyle(OnboardingTheme.secondaryText)
                }
                if chat.requiresDeviceReplacement {
                    Button(L10n("Switch to this iPhone")) { showsDeviceReplacement = true }
                        .foregroundStyle(OnboardingTheme.cyan)
                } else if chat.requiresKeyConfirmation {
                    Button { showsSecurityCode = true } label: {
                        Label(L10n("Security key changed — compare codes"), systemImage: "lock.shield")
                    }
                    .foregroundStyle(OnboardingTheme.cyan)
                }
                if chat.pendingMessageCount > 0 && chat.errorMessage != nil {
                    Text(L10n("Messages are waiting to be sent. Keep the app open to retry."))
                        .foregroundStyle(OnboardingTheme.secondaryText)
                }
            }
            .font(.caption)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.bottom, 6)
        }
    }

    private var closedBanner: some View {
        Label(L10n("This match is broken. No more messages can be sent, and you can never be matched again."),
              systemImage: "heart.slash")
            .font(.footnote)
            .foregroundStyle(OnboardingTheme.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial.opacity(0.6))
    }

    // MARK: - Composer

    private var composer: some View {
        MatchChatComposer(chat: chat, draft: chat.draft, isFocused: $composerFocused)
            .background {
                // A tap anywhere else on the screen — the gear, the header,
                // the messages — closes the keyboard and still does its job.
                // It measures the composer itself: a frame kept in state
                // changed as the keyboard pushed the composer up and redrew
                // the whole conversation during the keyboard's slide.
                KeyboardDismissTap(isActive: composerFocused) {
                    composerFocused = false
                }
                .allowsHitTesting(false)
            }
    }

    // MARK: - Security code

    private var securitySheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "lock.shield")
                    .font(.largeTitle)
                    .foregroundStyle(OnboardingTheme.accentGradient)
                Text(L10n("Compare this code with your match by phone or in person. It must be identical on both phones."))
                    .multilineTextAlignment(.center)
                if let code = chat.securityCode {
                    Text(code)
                        .font(.system(.title3, design: .monospaced))
                        .textSelection(.enabled)
                    Button(L10n("I compared the code")) {
                        chat.confirmSecurityCode()
                        showsSecurityCode = false
                    }
                    .buttonStyle(GlowButtonStyle())
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle(L10n("Security code"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n("Done")) { showsSecurityCode = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(OnboardingTheme.background)
        .preferredColorScheme(.dark)
    }
}

/// The text field and send button. It alone watches the draft, so typing
/// redraws this row and nothing else on the screen.
private struct MatchChatComposer: View {
    @ObservedObject var chat: ChatViewModel
    @ObservedObject var draft: ChatDraft
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        let canSend = chat.canSend
        // The send pill sits inside the field, on its last line.
        HStack(alignment: .bottom, spacing: 0) {
            TextField(L10n("Message"), text: $draft.text, axis: .vertical)
                .font(.body)
                .lineLimit(1...5)
                .foregroundStyle(OnboardingTheme.primaryText)
                .tint(OnboardingTheme.cyan)
                .focused(isFocused)
                .submitLabel(.return)
                .padding(.leading, 16)
                .padding(.trailing, 4)
                .padding(.vertical, 11)
                .accessibilityIdentifier("chat.composer")
                .onChange(of: draft.text) { _, text in
                    // Return in an empty field closes the keyboard instead of starting a new line.
                    if text.contains("\n"), text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        draft.text = ""
                        isFocused.wrappedValue = false
                        return
                    }
                    if text.utf8.count > 8000 { draft.text = String(text.prefix(4000)) }
                }

            Button {
                // With nothing to send, the grey pill closes the keyboard.
                if canSend { chat.sendMessage() } else { isFocused.wrappedValue = false }
            } label: {
                Image(systemName: "paperplane")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(canSend ? Color.white : OnboardingTheme.tertiaryText)
                    .frame(width: 52, height: 34)
                    .background {
                        Capsule().fill(canSend
                            ? AnyShapeStyle(OnboardingTheme.buttonGradient)
                            : AnyShapeStyle(Color.white.opacity(0.08)))
                    }
                    .shadow(color: OnboardingTheme.violet.opacity(canSend ? 0.55 : 0), radius: 10)
                    .padding(5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.18), value: canSend)
            .accessibilityLabel(canSend ? L10n("Send") : L10n("Hide keyboard"))
            .accessibilityIdentifier("chat.send")
        }
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(isFocused.wrappedValue ? OnboardingTheme.cyan.opacity(0.35) : OnboardingTheme.hairline,
                              lineWidth: isFocused.wrappedValue ? 1 : 0.5)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background {
            LinearGradient(colors: [OnboardingTheme.background.opacity(0), OnboardingTheme.background.opacity(0.92)],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// Whether the conversation is scrolled to its newest message. A reference,
/// so updating it while scrolling never redraws the panel.
private final class ScrollEdgeTracker {
    var isAtBottom = true
}

/// Watches every tap in the window while the keyboard is up and calls
/// `dismiss` for those outside the view it sits behind. It never cancels
/// the touch, so the button or gear that was tapped still works.
private struct KeyboardDismissTap: UIViewRepresentable {
    var isActive: Bool
    var dismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WindowAnchor {
        let view = WindowAnchor()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        context.coordinator.anchor = view
        return view
    }

    func updateUIView(_ view: WindowAnchor, context: Context) {
        context.coordinator.isActive = isActive
        context.coordinator.dismiss = dismiss
    }

    static func dismantleUIView(_ view: WindowAnchor, coordinator: Coordinator) {
        coordinator.attach(to: nil)
    }

    final class WindowAnchor: UIView {
        weak var coordinator: Coordinator?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.attach(to: window)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isActive = false
        var dismiss: () -> Void = {}
        /// Sized to the composer, so its bounds are the area left alone.
        weak var anchor: UIView?

        private lazy var recognizer: UITapGestureRecognizer = {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(tapped))
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            return recognizer
        }()

        func attach(to window: UIWindow?) {
            recognizer.view?.removeGestureRecognizer(recognizer)
            window?.addGestureRecognizer(recognizer)
        }

        @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            dismiss()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard isActive, let anchor else { return false }
            return !anchor.bounds.contains(touch.location(in: anchor))
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

/// One message. Sent messages lean right in the light's own gradient; the
/// other person's sit left on a quiet surface. The time and, for sent
/// messages, the delivery ticks ride in the bubble's corner.
struct ChatBubble: View {
    let message: ChatMessage
    var isFirstInGroup = true
    var isRead = false
    var isDelivered = true

    private var isMine: Bool { message.sender == .currentUser }

    var body: some View {
        if message.sender == .system {
            Text(L10n(AppLocalizedMessage(stringLiteral: message.text)))
                .font(.caption)
                .foregroundStyle(OnboardingTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        } else {
            HStack(spacing: 0) {
                if isMine { Spacer(minLength: 56) }
                bubble
                if !isMine { Spacer(minLength: 56) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isMine ? L10n("You: \(message.text)") : message.text)
            .accessibilityValue(time)
        }
    }

    private var time: String {
        message.sentAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(AppLocale.current))
    }

    private var bubble: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: !isMine && isFirstInGroup ? 5 : 18,
            bottomLeadingRadius: 18, bottomTrailingRadius: 18,
            topTrailingRadius: isMine && isFirstInGroup ? 5 : 18, style: .continuous)
        // Invisible copy of the stamp: the time rides on the last line when
        // there is room, and the bubble grows a line when there is not.
        let text = Text(verbatim: message.text).font(.body).foregroundStyle(.white)
        let room = Text(verbatim: "  \(time)" + (isMine ? "  ✓✓" : "")).font(.system(size: 10.5)).foregroundStyle(.clear)
        return Text("\(text)\(room)")
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .overlay(alignment: .bottomTrailing) {
                stamp.padding(.trailing, 10).padding(.bottom, 6)
            }
            .background {
                if isMine {
                    shape.fill(LinearGradient(colors: [OnboardingTheme.blue.opacity(0.92), OnboardingTheme.violet.opacity(0.88)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: OnboardingTheme.blue.opacity(0.35), radius: 8, y: 2)
                } else {
                    shape.fill(Color.white.opacity(0.10))
                        .overlay { shape.strokeBorder(OnboardingTheme.hairline, lineWidth: 0.5) }
                }
            }
            .textSelection(.enabled)
    }
}

private extension ChatBubble {
    @ViewBuilder
    var stamp: some View {
        HStack(spacing: 3) {
            Text(time)
            if isMine {
                if !isDelivered {
                    Image(systemName: "clock").font(.system(size: 9, weight: .semibold))
                } else {
                    // One tick once the server has it, two bright ones once read.
                    ZStack(alignment: .leading) {
                        Image(systemName: "checkmark")
                        if isRead { Image(systemName: "checkmark").offset(x: 4) }
                    }
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isRead ? OnboardingTheme.cyan : .white.opacity(0.75))
                    .frame(width: 15, alignment: .leading)
                }
            }
        }
        .font(.system(size: 10.5))
        .monospacedDigit()
        .foregroundStyle(.white.opacity(isMine ? 0.72 : 0.5))
    }
}

/// Three dots that rise in turn while the other person writes.
struct TypingBubble: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                HStack(spacing: 5) {
                    ForEach(0..<3) { index in
                        let wave = reduceMotion ? 0 : max(0, sin((t * 2 * .pi / 1.1) - Double(index) * 0.7))
                        Circle()
                            .fill(.white.opacity(0.45 + 0.4 * wave))
                            .frame(width: 7, height: 7)
                            .offset(y: -3 * wave)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background {
                UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 18,
                                       bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            }
            Spacer(minLength: 56)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n("Typing"))
    }
}
