import SwiftUI

struct SettingsView: View {
    let onSignOut: () -> Void
    let onDeleteLocalProfile: () -> Void

    @State private var matchingReminders = true
    @State private var chatNotifications = true
    @State private var showsDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n("Notifications")) {
                    Toggle(
                        L10n("Matching reminders"),
                        isOn: $matchingReminders
                    )

                    Toggle(
                        L10n("Chat notifications"),
                        isOn: $chatNotifications
                    )
                }

                Section(L10n("Privacy and safety")) {
                    NavigationLink(L10n("Blocked profiles")) {
                        PlaceholderScreen(
                            title: L10n("Blocked profiles"),
                            message: L10n("Blocked profiles will appear here after backend synchronization is added.")
                        )
                    }

                    NavigationLink(L10n("Community guidelines")) {
                        PlaceholderScreen(
                            title: L10n("Community guidelines"),
                            message: L10n("Safety and conduct rules will appear here.")
                        )
                    }

                    NavigationLink(L10n("Privacy overview")) {
                        PlaceholderScreen(
                            title: L10n("Privacy overview"),
                            message: L10n("A clear explanation of profile and matching data will appear here.")
                        )
                    }
                }

                Section(L10n("Account")) {
                    Button(L10n("Sign out"), action: onSignOut)

                    Button(
                        L10n("Delete local profile data"),
                        role: .destructive
                    ) {
                        showsDeleteConfirmation = true
                    }
                }

                Section {
                    Text("MVP build 9")
                        .foregroundStyle(AppColors.secondaryForeground)
                }
            }
            .navigationTitle(L10n("Settings"))
            .confirmationDialog(
                L10n("Delete local profile data?"),
                isPresented: $showsDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(
                    L10n("Delete local data"),
                    role: .destructive
                ) {
                    onDeleteLocalProfile()
                }

                Button(L10n("Cancel"), role: .cancel) {}
            } message: {
                Text(
                    L10n("This removes the locally saved profile from this device. Backend account deletion will be added later.")
                )
            }
        }
    }
}

#Preview {
    SettingsView(
        onSignOut: {},
        onDeleteLocalProfile: {}
    )
}
