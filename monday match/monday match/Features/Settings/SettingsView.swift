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
                Section("Notifications") {
                    Toggle(
                        "Matching reminders",
                        isOn: $matchingReminders
                    )

                    Toggle(
                        "Chat notifications",
                        isOn: $chatNotifications
                    )
                }

                Section("Privacy and safety") {
                    NavigationLink("Blocked profiles") {
                        PlaceholderScreen(
                            title: "Blocked profiles",
                            message: "Blocked profiles will appear here after backend synchronization is added."
                        )
                    }

                    NavigationLink("Community guidelines") {
                        PlaceholderScreen(
                            title: "Community guidelines",
                            message: "Safety and conduct rules will appear here."
                        )
                    }

                    NavigationLink("Privacy overview") {
                        PlaceholderScreen(
                            title: "Privacy overview",
                            message: "A clear explanation of profile and matching data will appear here."
                        )
                    }
                }

                Section("Account") {
                    Button("Sign out", action: onSignOut)

                    Button(
                        "Delete local profile data",
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
            .navigationTitle("Settings")
            .confirmationDialog(
                "Delete local profile data?",
                isPresented: $showsDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(
                    "Delete local data",
                    role: .destructive
                ) {
                    onDeleteLocalProfile()
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "This removes the locally saved profile from this device. Backend account deletion will be added later."
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
