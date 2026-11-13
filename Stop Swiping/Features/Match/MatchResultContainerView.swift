import SwiftUI

struct MatchResultContainerView: View {
    let result: MatchResult?
    let chatViewModel: ChatViewModel?
    let onClearResult: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    switch result.outcome {
                    case .noMatch:
                        NoMatchView(result: result)

                    case .matched(let profile):
                        SuccessfulMatchView(
                            result: result,
                            profile: profile,
                            chatViewModel: chatViewModel,
                            onEndMatch: onClearResult
                        )
                    }
                } else {
                    WaitingForMatchView()
                }
            }
            .navigationTitle(L10n("Match"))
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
