import SwiftUI

struct LanguagesStep: View {
    @ObservedObject var viewModel: ProfileCreationViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pickerMode: PickerMode?

    private enum PickerMode: Identifiable {
        case add
        case replace(String)

        var id: String {
            switch self {
            case .add: "add"
            case .replace(let code): "replace-\(code)"
            }
        }
    }

    var body: some View {
        let languages = viewModel.state.languages

        FlowLayout(spacing: 10, lineSpacing: 12) {
            ForEach(languages, id: \.self) { code in
                LanguageChip(
                    option: LanguageCatalog.option(for: code),
                    canRemove: languages.count > 1,
                    onChange: { pickerMode = .replace(code) },
                    onRemove: { viewModel.removeLanguage(code) }
                )
                .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
            }

            AddLanguageChip { pickerMode = .add }
        }
        .frame(maxWidth: OnboardingTheme.controlWidth, alignment: .leading)
        .animation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion), value: languages)
        .sensoryFeedback(.selection, trigger: languages)
        .sheet(item: $pickerMode) { mode in
            LanguagePickerSheet(
                title: { if case .replace = mode { "Change language" } else { "Add a language" } }(),
                excludedCodes: Set(languages),
                onSelect: { code in
                    switch mode {
                    case .add: viewModel.addLanguage(code)
                    case .replace(let existing): viewModel.replaceLanguage(existing, with: code)
                    }
                    pickerMode = nil
                }
            )
        }
    }
}

private struct LanguageChip: View {
    let option: LanguageOption
    let canRemove: Bool
    let onChange: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onChange) {
                HStack(spacing: 8) {
                    Text(option.name)
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.primaryText)
                    if let endonym = option.endonym {
                        Text(endonym)
                            .font(.system(.subheadline))
                            .foregroundStyle(OnboardingTheme.secondaryText)
                    }
                }
                .lineLimit(1)
                .padding(.leading, 18)
                .padding(.trailing, canRemove ? 4 : 18)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(option.name)
            .accessibilityHint("Double tap to choose a different language.")

            if canRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(OnboardingTheme.secondaryText)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.white.opacity(0.1)))
                        .frame(width: 44, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(option.name)")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .background {
            Capsule(style: .continuous)
                .fill(LinearGradient(
                    colors: [OnboardingTheme.blue.opacity(0.24), OnboardingTheme.violet.opacity(0.18)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay { Capsule(style: .continuous).strokeBorder(OnboardingTheme.accentGradient, lineWidth: 1.2) }
                .shadow(color: OnboardingTheme.blue.opacity(0.3), radius: 12, y: 4)
        }
        .animation(.snappy, value: canRemove)
    }
}

private struct AddLanguageChip: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Add language", systemImage: "plus")
                .font(.system(.body, weight: .medium))
                .foregroundStyle(OnboardingTheme.primaryText.opacity(0.82))
                .padding(.horizontal, 18)
                .frame(minHeight: 48)
                .background {
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(0.28), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct LanguagePickerSheet: View {
    let title: String
    let excludedCodes: Set<String>
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var available: [LanguageOption] {
        LanguageCatalog.all.filter { !excludedCodes.contains($0.code) }
    }

    private var suggested: [LanguageOption] {
        LanguageCatalog.suggestedCodes
            .filter { !excludedCodes.contains($0) }
            .map { LanguageCatalog.option(for: $0) }
    }

    private var results: [LanguageOption] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return available }
        return available.filter {
            $0.name.localizedStandardContains(trimmed)
                || ($0.endonym?.localizedStandardContains(trimmed) ?? false)
                || $0.code.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty && !suggested.isEmpty {
                    Section("Suggested") {
                        ForEach(suggested) { row($0) }
                    }
                }
                Section(query.isEmpty ? "All languages" : "Results") {
                    ForEach(results) { row($0) }
                }
            }
            .scrollContentBackground(.hidden)
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search languages")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private func row(_ option: LanguageOption) -> some View {
        Button {
            onSelect(option.code)
        } label: {
            HStack {
                Text(option.name)
                    .foregroundStyle(.primary)
                Spacer()
                if let endonym = option.endonym {
                    Text(endonym)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel(option.name)
    }
}
