import SwiftUI

struct LaunchView: View {
    var body: some View {
        ZStack {
            AppColors.background
                .ignoresSafeArea()

            ProgressView()
                .controlSize(.large)
        }
    }
}

#Preview {
    LaunchView()
}
