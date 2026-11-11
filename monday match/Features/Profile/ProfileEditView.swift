import SwiftUI

struct ProfileEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var profile: ProfileDraft

    @State private var draft: ProfileDraft

    init(profile: Binding<ProfileDraft>) {
        _profile = profile
        _draft = State(initialValue: profile.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic information") {
                    TextField(
                        "Display name",
                        text: $draft.displayName
                    )

                    TextField(
                        "Bio",
                        text: $draft.bio,
                        axis: .vertical
                    )
                    .lineLimit(4...8)
                }

                Section("Matching distance") {
                    Slider(
                        value: Binding(
                            get: {
                                Double(draft.preferredRadiusKilometers)
                            },
                            set: {
                                draft.preferredRadiusKilometers = Int($0.rounded())
                            }
                        ),
                        in: 5...250,
                        step: 5
                    )

                    Text("\(draft.preferredRadiusKilometers) km")
                }

                Section("Interests") {
                    ForEach(ProfileInterest.allCases) { interest in
                        Toggle(
                            interest.title,
                            isOn: Binding(
                                get: {
                                    draft.interests.contains(interest)
                                },
                                set: { isSelected in
                                    if isSelected {
                                        draft.interests.insert(interest)
                                    } else {
                                        draft.interests.remove(interest)
                                    }
                                }
                            )
                        )
                    }
                }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        profile = draft
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private var isValid: Bool {
        draft.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .count >= 2
        &&
        draft.bio
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .count >= 20
        &&
        draft.interests.count >= 3
    }
}

#Preview {
    ProfileEditView(
        profile: .constant(.mockCompleted)
    )
}
