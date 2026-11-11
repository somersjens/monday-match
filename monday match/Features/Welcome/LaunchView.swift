import SwiftUI

struct LaunchView: View {
    var body: some View {
        Color("WelcomeBackground")
            .ignoresSafeArea()
            .preferredColorScheme(.dark)
    }
}

#Preview {
    LaunchView()
}
