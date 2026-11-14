import SwiftUI

/// Where the rings sit while the conversation is open, in screen points. The
/// light shrinks around the rings' middle and rises under the header.
enum MatchChatLayout {
    /// How large the light is drawn while chatting.
    static let lightScale: CGFloat = 0.72
    static let headerHeight: CGFloat = 64

    /// - Parameter unit: Points per normalized unit of the light at full size.
    static func ringsCenterY(unit: CGFloat) -> CGFloat {
        headerHeight + 0.64 * unit * lightScale + 6
    }

    /// The light's own centre, so the rings land on `ringsCenterY`.
    static func lightCenterY(unit: CGFloat) -> CGFloat {
        ringsCenterY(unit: unit) - CGFloat(WelcomeLightMatch.Chat.ringCenterY) * unit * lightScale
    }

    /// Messages fade out as they scroll up behind the rings.
    static func ringsBottom(unit: CGFloat) -> CGFloat {
        ringsCenterY(unit: unit) + 0.56 * unit * lightScale
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
        .task(id: scenePhase == .active) {
            guard chat.isLive, scenePhase == .active else { return }
            while !Task.isCancelled {
                await chat.refresh()
                chat.markAllRead()
                if chat.conversation.isClosed { return }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
        .onChange(of: chat.conversation.messages.count) { _, _ in chat.markAllRead() }
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
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: max(0, ringsBottom - headerHeight - 90))
                    LinearGradient(colors: [.clear, .black],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 100)
                    Color.black
                }
            }
            .onChange(of: visibleMessages.last?.id) { _, _ in scrollToBottom(proxy) }
            .onChange(of: chat.isPartnerTyping) { _, _ in scrollToBottom(proxy) }
            .onChange(of: composerFocused) { _, focused in
                if focused {
                    Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        scrollToBottom(proxy)
                    }
                }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private var notice: some View {
        Label(chat.isDemo ? L10n("Demo conversation. Every message gets a reply.")
                          : L10n("Messages are end-to-end encrypted. Only you and your match can read them."),
              systemImage: chat.isDemo ? "sparkles" : "lock.fill")
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
        Label(L10n("This match has ended."), systemImage: "heart.slash")
            .font(.footnote)
            .foregroundStyle(OnboardingTheme.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial.opacity(0.6))
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(L10n("Message"), text: $chat.draftMessage, axis: .vertical)
                .font(.body)
                .lineLimit(1...5)
                .foregroundStyle(OnboardingTheme.primaryText)
                .tint(OnboardingTheme.cyan)
                .focused($composerFocused)
                .submitLabel(.return)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.white.opacity(0.08))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(composerFocused ? OnboardingTheme.cyan.opacity(0.35) : OnboardingTheme.hairline,
                                      lineWidth: composerFocused ? 1 : 0.5)
                }
                .accessibilityIdentifier("chat.composer")
                .onChange(of: chat.draftMessage) { _, text in
                    if text.utf8.count > 8000 { chat.draftMessage = String(text.prefix(4000)) }
                }

            Button(action: chat.sendMessage) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(chat.canSend ? Color.white : OnboardingTheme.tertiaryText)
                    .frame(width: 44, height: 44)
                    .background {
                        Circle().fill(chat.canSend
                            ? AnyShapeStyle(OnboardingTheme.buttonGradient)
                            : AnyShapeStyle(Color.white.opacity(0.08)))
                    }
                    .shadow(color: OnboardingTheme.blue.opacity(chat.canSend ? 0.6 : 0), radius: 10)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!chat.canSend)
            .animation(.easeInOut(duration: 0.18), value: chat.canSend)
            .accessibilityLabel(L10n("Send"))
            .accessibilityIdentifier("chat.send")
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
