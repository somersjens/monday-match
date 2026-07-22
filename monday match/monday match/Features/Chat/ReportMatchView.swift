import SwiftUI

struct ReportMatchView: View {
    @Environment(\.dismiss) private var dismiss

    let participantName: String
    let onSubmit: (ReportReason, String) -> Void

    @State private var selectedReason: ReportReason?
    @State private var details = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(
                        "Reports are private. \(participantName) will not be told who submitted the report."
                    )
                    .foregroundStyle(AppColors.secondaryForeground)
                }

                Section("Reason") {
                    ForEach(ReportReason.allCases) { reason in
                        Button {
                            selectedReason = reason
                        } label: {
                            HStack {
                                Text(reason.title)
                                    .foregroundStyle(AppColors.foreground)

                                Spacer()

                                if selectedReason == reason {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(AppColors.accent)
                                }
                            }
                        }
                    }
                }

                Section("Details") {
                    TextField(
                        "Describe what happened",
                        text: $details,
                        axis: .vertical
                    )
                    .lineLimit(4...8)
                }
            }
            .navigationTitle("Report match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        guard let selectedReason else { return }
                        onSubmit(selectedReason, details)
                        dismiss()
                    }
                    .disabled(selectedReason == nil)
                }
            }
        }
    }
}

#Preview {
    ReportMatchView(
        participantName: "Alex",
        onSubmit: { _, _ in }
    )
}
