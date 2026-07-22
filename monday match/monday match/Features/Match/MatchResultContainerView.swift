import SwiftUI

struct MatchResultContainerView: View {
    let result: MatchResult?
    let conversation: ChatConversation?
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
                            conversation: conversation,
                            onEndMatch: onClearResult
                        )
                    }
                } else {
                    WaitingForMatchView()
                }
            }
            .navigationTitle("Match")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
