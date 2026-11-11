import SwiftUI

struct ChatView: View {
    // Observed, not owned: the view model is created and kept alive by
    // SignedInRootViewModel so messages survive leaving and reopening the chat.
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
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

            if viewModel.conversation.isBlocked {
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
                    Button {
                        viewModel.showsReportSheet = true
                    } label: {
                        Label(
                            "Report",
                            systemImage: "exclamationmark.bubble"
                        )
                    }

                    Button(role: .destructive) {
                        viewModel.showsBlockConfirmation = true
                    } label: {
                        Label(
                            "Block",
                            systemImage: "hand.raised"
                        )
                    }
                    .disabled(viewModel.conversation.isBlocked)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            "Block this person?",
            isPresented: $viewModel.showsBlockConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                "Block and close chat",
                role: .destructive
            ) {
                viewModel.blockMatch()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "They will no longer be able to contact you. This action should later be synced to the backend."
            )
        }
        .sheet(
            isPresented: $viewModel.showsReportSheet
        ) {
            ReportMatchView(
                participantName: viewModel.conversation.participantName,
                onSubmit: viewModel.submitReport
            )
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: AppSpacing.small) {
            TextField(
                "Message",
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
        Text("This conversation is closed because the match is blocked.")
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
                Text(message.text)
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
                            date: .omitted,
                            time: .shortened
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
