#if DEBUG
import SwiftUI

// TEMPORARY: probe for the language sheet's bottom gap. Remove after testing.
struct TempSheetProbe: ViewModifier {
    @State private var shows = false
    private let variant = UserDefaults.standard.integer(forKey: "sheetProbe")

    func body(content: Content) -> some View {
        content
            .overlay { if variant > 0 { Color.red.ignoresSafeArea() } }
            .onAppear { if variant > 0 { shows = true } }
            .sheet(isPresented: $shows) {
                switch variant {
                case 1:
                    AppLanguagePicker()
                case 2:
                    AppLanguagePicker().presentationCornerRadius(32)
                case 3:
                    AppLanguagePicker().presentationDetents([.large])
                default:
                    AppLanguagePicker().presentationSizing(.page)
                }
            }
    }
}
#endif
