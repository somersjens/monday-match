import SwiftUI
import UIKit
import XCTest
@testable import Stop_Swiping

@MainActor
final class SecureChatLayoutTests: XCTestCase {
    func testRenderChatInDutchAtCompactAndStandardSizes() async throws {
        let original=AppLanguageSettings.shared.language
        defer { AppLanguageSettings.shared.language=original }
        AppLanguageSettings.shared.language = .dutch
        for size in [CGSize(width:320,height:568),CGSize(width:393,height:852)] {
            let conversation=ChatConversation(matchID:UUID(),participantName:"Alex",messages:[
                ChatMessage(sender:.match,text:"Hoi! Leuk dat we gematcht zijn. Hoe gaat je weekend?"),
                ChatMessage(sender:.currentUser,text:"Goed! Zullen we binnenkort ergens koffie drinken?")])
            let model=ChatViewModel(conversation:conversation)
            let scene=try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window=UIWindow(windowScene:scene)
            let host=UIHostingController(rootView:NavigationStack { ChatView(viewModel:model) }.preferredColorScheme(.dark))
            window.frame=CGRect(origin:.zero,size:size); window.rootViewController=host; window.isHidden=false
            host.view.frame=window.bounds; host.view.layoutIfNeeded()
            try await Task.sleep(for:.milliseconds(250))
            host.view.layoutIfNeeded()
            let image=UIGraphicsImageRenderer(size:size).image { _ in host.view.drawHierarchy(in:host.view.bounds,afterScreenUpdates:true) }
            let attachment=XCTAttachment(image:image); attachment.name="secure-chat-nl-\(Int(size.width))"; attachment.lifetime = .keepAlways; add(attachment)
            let path=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("secure-chat-nl-\(Int(size.width)).png")
            try XCTUnwrap(image.pngData()).write(to:path)
            print("CHAT_RENDER \(path.path)")
            window.isHidden=true; window.rootViewController=nil
            XCTAssertEqual(image.size,size)
        }
    }
}
