import SwiftUI

/// Two answers on one ordered scale. Rows through the partner's limit light
/// up along a rail; appearance scores run downwards so this is a minimum.
struct PartnerPreferenceScale: View {
    enum Subject {
        case frequency
        case appearance
    }

    enum Mode {
        case own
        case partner
    }

    enum LimitStatus {
        case open
        case accepted
        case limit
        case excluded
    }

    let levels: [String]
    let ownIndex: Int?
    let partnerLimitIndex: Int?
    @Binding var mode: Mode
    let onSelectOwn: (Int) -> Void
    let onSelectPartnerLimit: (Int) -> Void

    var subject: Subject = .frequency

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var limitLabel: String { subject == .appearance ? L10n("Min") : L10n("Max") }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                tab(.own, title: subject == .appearance ? L10n("Your own appearance") : L10n("You"), value: ownIndex.map { levels[$0] }, placeholder: L10n("Choose one"))
                tab(.partner, title: subject == .appearance ? L10n("Partner, at least") : L10n("Partner, at most"), value: partnerLimitIndex.map { levels[$0] }, placeholder: L10n("Set a limit"))
            }
            .padding(6)

            Rectangle()
                .fill(.white.opacity(0.07))
                .frame(height: 0.5)

            ForEach(levels.indices, id: \.self) { index in
                row(index)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onboardingSurface(cornerRadius: 24)
        .frame(maxWidth: OnboardingTheme.controlWidth)
        .animation(OnboardingMotion.resolved(OnboardingMotion.selection, reduceMotion: reduceMotion), value: ownIndex)
        .animation(OnboardingMotion.resolved(OnboardingMotion.selection, reduceMotion: reduceMotion), value: partnerLimitIndex)
        .animation(OnboardingMotion.resolved(OnboardingMotion.selection, reduceMotion: reduceMotion), value: mode)
        .sensoryFeedback(.selection, trigger: ownIndex)
        .sensoryFeedback(.selection, trigger: partnerLimitIndex)
    }

    // MARK: - Tabs

    private func tab(_ tabMode: Mode, title: String, value: String?, placeholder: String) -> some View {
        let isActive = mode == tabMode
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return Button { mode = tabMode } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(isActive ? OnboardingTheme.primaryText : OnboardingTheme.secondaryText)
                Text(value ?? placeholder)
                    .font(.system(.footnote, weight: value == nil ? .regular : .medium))
                    .foregroundStyle(value == nil ? OnboardingTheme.tertiaryText
                                     : (isActive ? OnboardingTheme.cyan : OnboardingTheme.secondaryText))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape
                    .fill(isActive ? AnyShapeStyle(selectedFill) : AnyShapeStyle(Color.clear))
                    .overlay {
                        shape.strokeBorder(isActive ? AnyShapeStyle(OnboardingTheme.accentGradient) : AnyShapeStyle(Color.clear),
                                           lineWidth: 1.2)
                    }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value ?? L10n("Not answered"))
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Rows

    private func limitStatus(_ index: Int) -> LimitStatus {
        guard let partnerLimitIndex else { return .open }
        if index < partnerLimitIndex { return .accepted }
        return index == partnerLimitIndex ? .limit : .excluded
    }

    private func row(_ index: Int) -> some View {
        let status = limitStatus(index)
        let isOwn = index == ownIndex
        let isLast = index == levels.count - 1
        return Button {
            switch mode {
            case .own: onSelectOwn(index)
            case .partner: onSelectPartnerLimit(index)
            }
        } label: {
            HStack(spacing: 14) {
                OwnMarker(isSelected: isOwn, isActive: mode == .own)

                Text(levels[index])
                    // Selection must not change glyph widths or line breaks.
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(textColor(index, status))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Use the actual badge width, including its Dynamic Type size,
                // even when this row has no visible limit label.
                LimitBadge(title: limitLabel)
                    .hidden()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(minHeight: 52)
            .background(alignment: .trailing) {
                LimitBadge(title: limitLabel)
                    .hidden()
                    .frame(maxHeight: .infinity)
                    .overlay {
                        LimitRail(
                            status: status,
                            limitLabel: limitLabel,
                            litAbove: index > 0 && (status == .accepted || status == .limit),
                            litBelow: status == .accepted,
                            isFirst: index == 0,
                            isLast: isLast
                        )
                    }
                    .padding(.trailing, 18)
                    .opacity(mode == .partner ? 1 : 0.45)
            }
            .background { rowFill(index, status) }
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle()
                        .fill(.white.opacity(0.06))
                        .frame(height: 0.5)
                        .padding(.horizontal, 18)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(levels[index])
        .accessibilityValue(accessibilityValue(isOwn: isOwn, status: status))
        .accessibilityHint(selectionHint)
        .accessibilityAddTraits((mode == .own ? isOwn : status == .limit) ? [.isButton, .isSelected] : .isButton)
        // These are siblings of the row button, so taps on either marker
        // have their own action without nesting buttons or changing tabs.
        .overlay(alignment: .leading) {
            Button { onSelectOwn(index) } label: {
                Color.clear
                    .frame(width: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 7)
            .accessibilityLabel(L10n("You") + ", " + levels[index])
            .accessibilityAddTraits(isOwn ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("scale.own.\(index)")
        }
        .overlay(alignment: .trailing) {
            Button { onSelectPartnerLimit(index) } label: {
                LimitBadge(title: limitLabel)
                    .hidden()
                    .frame(minWidth: 44, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 18)
            .accessibilityLabel(L10n("Partner") + ", " + levels[index])
            .accessibilityValue(accessibilityValue(isOwn: false, status: status))
            .accessibilityAddTraits(status == .limit ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("scale.partner.\(index)")
        }
    }

    private var selectionHint: String {
        switch (subject, mode) {
        case (.frequency, .own): L10n("Sets how often you do this.")
        case (.frequency, .partner): L10n("Sets the most often a partner may do this.")
        case (.appearance, .own): L10n("Sets your own appearance score.")
        case (.appearance, .partner): L10n("Sets the minimum appearance score for a partner.")
        }
    }

    private func textColor(_ index: Int, _ status: LimitStatus) -> Color {
        switch mode {
        case .own:
            return index == ownIndex ? OnboardingTheme.primaryText : OnboardingTheme.primaryText.opacity(0.86)
        case .partner:
            switch status {
            case .open: return OnboardingTheme.primaryText.opacity(0.86)
            case .accepted: return OnboardingTheme.primaryText.opacity(0.92)
            case .limit: return OnboardingTheme.primaryText
            case .excluded: return OnboardingTheme.tertiaryText
            }
        }
    }

    @ViewBuilder
    private func rowFill(_ index: Int, _ status: LimitStatus) -> some View {
        switch mode {
        case .own:
            selectedFill.opacity(index == ownIndex ? 1 : 0)
        case .partner:
            switch status {
            case .limit: selectedFill
            case .accepted: OnboardingTheme.blue.opacity(0.09)
            case .open, .excluded: Color.clear
            }
        }
    }

    private var selectedFill: LinearGradient {
        LinearGradient(
            colors: [OnboardingTheme.blue.opacity(0.24), OnboardingTheme.violet.opacity(0.16)],
            startPoint: .leading, endPoint: .trailing
        )
    }

    private func accessibilityValue(isOwn: Bool, status: LimitStatus) -> String {
        var parts: [String] = []
        if isOwn { parts.append(L10n("Your answer")) }
        switch status {
        case .open: break
        case .accepted: parts.append(L10n("Accepted for a partner"))
        case .limit: parts.append(subject == .appearance ? L10n("Partner minimum") : L10n("Partner limit"))
        case .excluded: parts.append(subject == .appearance ? L10n("Below the partner minimum") : L10n("Above the partner limit"))
        }
        return parts.joined(separator: ", ")
    }
}

/// The user's own answer: a single-choice indicator.
struct OwnMarker: View {
    let isSelected: Bool
    let isActive: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.white.opacity(isSelected ? 0 : (isActive ? 0.32 : 0.14)), lineWidth: 1.5)
            Circle()
                .fill(OnboardingTheme.accentGradient)
                .opacity(isSelected ? 1 : 0)
                .scaleEffect(isSelected ? 1 : 0.6)
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .opacity(isSelected ? 1 : 0)
                .scaleEffect(isSelected ? 1 : 0.4)
        }
        .frame(width: 22, height: 22)
        .saturation(isSelected && !isActive ? 0.6 : 1)
        .accessibilityHidden(true)
    }
}

/// One row's piece of the partner rail: the lit line runs from the lowest
/// level to the limit, through a node on every row.
private struct LimitRail: View {
    let status: PartnerPreferenceScale.LimitStatus
    let limitLabel: String
    let litAbove: Bool
    let litBelow: Bool
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        VStack(spacing: 0) {
            segment(lit: litAbove).opacity(isFirst ? 0 : 1)
            segment(lit: litBelow).opacity(isLast ? 0 : 1)
        }
        .overlay { node }
        .accessibilityHidden(true)
    }

    private func segment(lit: Bool) -> some View {
        Rectangle()
            .fill(lit ? OnboardingTheme.cyan.opacity(0.85) : .white.opacity(0.12))
            .frame(width: lit ? 2 : 1.5)
            .shadow(color: OnboardingTheme.cyan.opacity(lit ? 0.6 : 0), radius: 4)
            .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var node: some View {
        switch status {
        case .limit:
            LimitBadge(title: limitLabel)
                .shadow(color: OnboardingTheme.blue.opacity(0.5), radius: 8)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        case .accepted:
            Circle()
                .fill(OnboardingTheme.cyan)
                .frame(width: 9, height: 9)
                .shadow(color: OnboardingTheme.cyan.opacity(0.7), radius: 4)
        case .open, .excluded:
            Circle()
                .fill(OnboardingTheme.background)
                .overlay { Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1.5) }
                .frame(width: 9, height: 9)
        }
    }
}

private struct LimitBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(.caption, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background { Capsule().fill(OnboardingTheme.accentGradient) }
            .fixedSize()
            .accessibilityHidden(true)
    }
}
