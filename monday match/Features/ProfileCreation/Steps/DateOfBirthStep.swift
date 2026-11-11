import SwiftUI

struct DateOfBirthStep: View {
    @ObservedObject var viewModel: ProfileCreationViewModel
    let onAutoAdvance: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title3) private var dayWidth: CGFloat = 64
    @ScaledMetric(relativeTo: .title3) private var yearWidth: CGFloat = 92
    @State private var adjustingFields: Set<BirthDateField> = []

    private struct AutoAdvanceKey: Equatable {
        let selection: CalendarDate
        let isAdjusting: Bool
    }

    var body: some View {
        VStack(spacing: 24) {
            picker
            status
        }
        .frame(maxWidth: OnboardingTheme.controlWidth)
        .task(id: AutoAdvanceKey(selection: viewModel.birthDateSelection, isAdjusting: !adjustingFields.isEmpty)) {
            // Waits until every wheel has come to rest, then gives the user a
            // moment to see their age before moving on.
            guard adjustingFields.isEmpty, viewModel.shouldAutoAdvanceFromBirthDate else { return }
            try? await Task.sleep(for: .milliseconds(1100))
            guard !Task.isCancelled, adjustingFields.isEmpty, viewModel.shouldAutoAdvanceFromBirthDate else { return }
            onAutoAdvance()
        }
    }

    private var picker: some View {
        let selection = viewModel.birthDateSelection
        let daysInMonth = BirthDateRules.daysInMonth(month: selection.month, year: selection.year, calendar: viewModel.calendar)

        return VStack(spacing: 4) {
            HStack(spacing: 0) {
                columnTitle("Day").frame(width: dayWidth)
                columnTitle("Month").frame(maxWidth: .infinity)
                columnTitle("Year").frame(width: yearWidth)
            }
            .accessibilityHidden(true)

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.07))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(OnboardingTheme.accentGradient.opacity(0.5), lineWidth: 1)
                    }
                    .frame(height: 46)

                HStack(spacing: 0) {
                    WheelPicker(
                        items: Array(1...31),
                        selection: binding(\.day),
                        accessibilityLabel: "Day",
                        label: { String($0) },
                        isItemEnabled: { $0 <= daysInMonth },
                        onActivityChange: { track(.day, isActive: $0) }
                    )
                    .frame(width: dayWidth)

                    WheelPicker(
                        items: Array(1...12),
                        selection: binding(\.month),
                        accessibilityLabel: "Month",
                        label: { viewModel.monthName($0) },
                        onActivityChange: { track(.month, isActive: $0) }
                    )
                    .frame(maxWidth: .infinity)

                    WheelPicker(
                        items: BirthDateRules.selectableYears(today: viewModel.today),
                        selection: binding(\.year),
                        accessibilityLabel: "Year",
                        label: { String($0) },
                        onActivityChange: { track(.year, isActive: $0) }
                    )
                    .frame(width: yearWidth)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .onboardingSurface(cornerRadius: 28)
    }

    /// One reserved slot for age and messages, so nothing below it moves.
    private var status: some View {
        ZStack {
            if let feedback = viewModel.feedback {
                OnboardingFeedbackLabel(feedback: feedback)
                    .modifier(ShakeEffect(animatableData: reduceMotion ? 0 : CGFloat(viewModel.rejectionCount)))
                    .transition(.onboardingReveal(reduceMotion: reduceMotion))
            } else if let hint = viewModel.birthDateHint {
                OnboardingFeedbackLabel(feedback: hint)
                    .modifier(ShakeEffect(animatableData: reduceMotion ? 0 : CGFloat(viewModel.rejectionCount)))
                    .transition(.onboardingReveal(reduceMotion: reduceMotion))
            } else if let age = viewModel.visibleAge {
                AgeReadout(age: age)
                    .transition(.onboardingReveal(reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 84)
        .animation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion), value: statusIdentity)
        .animation(.linear(duration: 0.4), value: viewModel.rejectionCount)
    }

    private var statusIdentity: String {
        if let feedback = viewModel.feedback { return "feedback-\(feedback.message)" }
        if let hint = viewModel.birthDateHint { return "hint-\(hint.message)" }
        return viewModel.visibleAge == nil ? "empty" : "age"
    }

    private func columnTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(.caption2, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(OnboardingTheme.tertiaryText)
    }

    private func binding(_ field: WritableKeyPath<CalendarDate, Int>) -> Binding<Int> {
        Binding(
            get: { viewModel.birthDateSelection[keyPath: field] },
            set: { value in
                var selection = viewModel.birthDateSelection
                selection[keyPath: field] = value
                viewModel.updateBirthDate(selection)
            }
        )
    }

    private func track(_ field: BirthDateField, isActive: Bool) {
        if isActive {
            adjustingFields.insert(field)
        } else {
            adjustingFields.remove(field)
        }
    }
}

private struct AgeReadout: View {
    let age: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(age)")
                .font(.system(size: 52, weight: .light, design: .rounded).monospacedDigit())
                .foregroundStyle(OnboardingTheme.primaryText)
                .contentTransition(.numericText(value: Double(age)))
            Text(age == 1 ? "year old" : "years old")
                .font(.system(.title3, weight: .medium))
                .foregroundStyle(OnboardingTheme.secondaryText)
        }
        .animation(.snappy, value: age)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You are \(age) years old")
    }
}
