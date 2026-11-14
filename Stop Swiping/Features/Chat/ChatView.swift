import SwiftUI

struct ChatView: View {
    // Observed, not owned: the view model is created and kept alive by
    // SignedInRootViewModel so messages survive leaving and reopening the chat.
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsSecurityCode = false
    @State private var showsDeviceReplacement = false

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLive { liveStatus }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: AppSpacing.small) {
                        ForEach(viewModel.conversation.messages) { message in
                            ChatMessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(AppSpacing.large)
                }
                .onChange(
                    of: viewModel.conversation.messages.count
                ) { _, _ in
                    guard let lastID = viewModel.conversation.messages.last?.id else {
                        return
                    }

                    withAnimation {
                        proxy.scrollTo(
                            lastID,
                            anchor: .bottom
                        )
                    }
                }
            }

            if viewModel.conversation.isClosed {
                blockedBanner
            } else {
                composer
            }
        }
        .navigationTitle(viewModel.conversation.participantName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if viewModel.isLive {
                        Button(L10n("Security code"), systemImage: "lock.shield") { showsSecurityCode = true }
                        Button(L10n("End match"), role: .destructive) { viewModel.showsEndConfirmation = true }
                            .disabled(viewModel.conversation.isClosed)
                    }
                    Button {
                        viewModel.clearError(); viewModel.showsReportSheet = true
                    } label: {
                        Label(
                            L10n("Report"),
                            systemImage: "exclamationmark.bubble"
                        )
                    }

                    Button(role: .destructive) {
                        viewModel.showsBlockConfirmation = true
                    } label: {
                        Label(
                            L10n("Block"),
                            systemImage: "hand.raised"
                        )
                    }
                    .disabled(viewModel.conversation.isClosed || viewModel.isPerformingAction)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            L10n("Block this person?"),
            isPresented: $viewModel.showsBlockConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                L10n("Block and close chat"),
                role: .destructive
            ) {
                viewModel.blockMatch()
            }

            Button(L10n("Cancel"), role: .cancel) {}
        } message: {
            Text(
                L10n("They will no longer be able to contact you. The match will be closed for both of you.")
            )
        }
        .confirmationDialog(L10n("End this match?"), isPresented: $viewModel.showsEndConfirmation, titleVisibility: .visible) {
            Button(L10n("End match"), role: .destructive) { viewModel.endMatch() }
            Button(L10n("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n("Messaging will close for both of you. Auto-matching continues if it is enabled."))
        }
        .confirmationDialog(L10n("Use this iPhone for this chat?"), isPresented: $showsDeviceReplacement, titleVisibility: .visible) {
            Button(L10n("Switch to this iPhone")) { Task { await viewModel.replaceDevice() } }
            Button(L10n("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n("The previous device will stop receiving new messages. Unsent messages on this iPhone will be discarded. History from other devices cannot be recovered here. Compare the new security code with your match."))
        }
        .sheet(isPresented: $showsSecurityCode) { securitySheet }
        .task(id: scenePhase == .active) {
            guard viewModel.isLive, scenePhase == .active else { return }
            while !Task.isCancelled {
                await viewModel.refresh()
                if viewModel.conversation.isClosed { return }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
        .sheet(
            isPresented: $viewModel.showsReportSheet
        ) {
            ReportMatchView(
                participantName: viewModel.conversation.participantName,
                onSubmit: viewModel.submitReport
            )
            .disabled(viewModel.isPerformingAction)
            .alert(L10n("Could not submit report"), isPresented:Binding(
                get:{viewModel.errorMessage != nil},set:{if !$0 { viewModel.clearError() }})) {
                Button(L10n("OK")) { viewModel.clearError() }
            } message: { Text(viewModel.errorMessage ?? "") }
        }
    }

    private var liveStatus: some View {
        VStack(spacing: 6) {
            if let error = viewModel.errorMessage {
                Text(L10n(AppLocalizedMessage(stringLiteral:error))).font(.caption).foregroundStyle(.orange)
                Button(L10n("Retry")) { Task { await viewModel.refresh() } }.font(.caption)
            } else if !viewModel.isReady && !viewModel.conversation.isClosed {
                Text(L10n("Waiting for your match to open this conversation."))
                    .font(.caption).foregroundStyle(AppColors.secondaryForeground)
            }
            if viewModel.pendingMessageCount > 0 && !viewModel.conversation.isClosed {
                Text(L10n("Messages are waiting to be sent. Keep the app open to retry."))
                    .font(.caption).foregroundStyle(AppColors.secondaryForeground)
            }
            if viewModel.requiresDeviceReplacement {
                Button(L10n("Switch to this iPhone")) { showsDeviceReplacement = true }
            } else if viewModel.securityCode != nil {
                Button { showsSecurityCode = true } label: {
                    Label(viewModel.requiresKeyConfirmation ? L10n("Security key changed — compare codes") : L10n("Security code"), systemImage: "lock.shield")
                }.font(.caption)
            }
        }.padding(.horizontal).padding(.vertical,8)
    }
    private var securitySheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName:"lock.shield").font(.largeTitle)
                Text(L10n("Compare this code with your match by phone or in person. It must be identical on both phones."))
                if let code=viewModel.securityCode {
                    Text(code).font(.system(.title3,design:.monospaced)).textSelection(.enabled)
                    if viewModel.requiresKeyConfirmation && viewModel.pendingMessageCount > 0 {
                        Text(L10n("Unsent messages for the previous device will be discarded when you confirm this code."))
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    Button(L10n("I compared the code")) { viewModel.confirmSecurityCode(); showsSecurityCode=false }
                }
                if viewModel.securityCodeVerified { Text(L10n("Security code checked")) }
                Text(L10n("Messages are encrypted on your phone. Lost private keys cannot be recovered from Supabase."))
                    .font(.footnote).foregroundStyle(AppColors.secondaryForeground)
                Spacer()
            }.padding(24).navigationTitle(L10n("Security code"))
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button(L10n("Done")) { showsSecurityCode=false } } }
        }.presentationDetents([.medium,.large])
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: AppSpacing.small) {
            TextField(
                L10n("Message"),
                text: $viewModel.draftMessage,
                axis: .vertical
            )
            .lineLimit(1...5)
            .padding(.horizontal, AppSpacing.medium)
            .padding(.vertical, 12)
            .background(AppColors.secondaryBackground)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
            )

            Button(action: viewModel.sendMessage) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 42, height: 42)
                    .background(
                        viewModel.canSend
                            ? AppColors.accent
                            : AppColors.secondaryBackground
                    )
                    .foregroundStyle(
                        viewModel.canSend
                            ? Color.white
                            : AppColors.secondaryForeground
                    )
                    .clipShape(Circle())
            }
            .disabled(!viewModel.canSend)
        }
        .padding(AppSpacing.medium)
        .background(.ultraThinMaterial)
    }

    private var blockedBanner: some View {
        Text(L10n("This conversation is closed."))
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.secondaryForeground)
            .frame(maxWidth: .infinity)
            .padding(AppSpacing.medium)
            .background(.ultraThinMaterial)
    }
}

private struct ChatMessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.sender == .currentUser {
                Spacer(minLength: 48)
            }

            VStack(
                alignment: message.sender == .currentUser
                    ? .trailing
                    : .leading,
                spacing: 4
            ) {
                Text(message.sender == .system ? L10n(AppLocalizedMessage(stringLiteral: message.text)) : message.text)
                    .font(AppTypography.body)
                    .padding(.horizontal, AppSpacing.medium)
                    .padding(.vertical, 12)
                    .background(background)
                    .foregroundStyle(foreground)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 20,
                            style: .continuous
                        )
                    )

                if message.sender != .system {
                    Text(
                        message.sentAt.formatted(
                            Date.FormatStyle(date: .omitted, time: .shortened).locale(AppLocale.current)
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(AppColors.secondaryForeground)
                }
            }

            if message.sender != .currentUser {
                Spacer(minLength: 48)
            }
        }
    }

    private var background: Color {
        switch message.sender {
        case .currentUser:
            return AppColors.accent
        case .match:
            return AppColors.secondaryBackground
        case .system:
            return AppColors.accent.opacity(0.08)
        }
    }

    private var foreground: Color {
        message.sender == .currentUser
            ? .white
            : AppColors.foreground
    }
}

#Preview {
    NavigationStack {
        ChatView(
            viewModel: ChatViewModel(conversation: .mock())
        )
    }
}
