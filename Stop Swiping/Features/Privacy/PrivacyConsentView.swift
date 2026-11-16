import SwiftUI

struct PrivacyConsentView: View {
    let kind: PrivacyConsentKind
    let onAccept: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var acknowledged = false
    @State private var showsPolicy = false

    var body: some View {
        let copy = PrivacyContent.approval(kind, language: AppLanguageSettings.shared.language)
        VStack(spacing: 0) {
            PrivacyPageHeader(title: copy.title) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    PrivacyPointsCard(points: copy.points)
                        .padding(.top, 12)

                    PrivacyDetailsList(sections: copy.sections) { showsPolicy = true }

                    VStack(spacing: 14) {
                        PrivacyCheckbox(text: copy.acknowledgement, isOn: $acknowledged)
                        Button(L10n("Accept")) {
                            onAccept()
                            dismiss()
                        }
                        .buttonStyle(GlowButtonStyle())
                        .disabled(!acknowledged)
                        .accessibilityIdentifier("acceptPrivacy")
                        Button(L10n("Not now")) { dismiss() }
                            .buttonStyle(QuietButtonStyle())
                    }
                }
                .foregroundStyle(OnboardingTheme.primaryText)
                .frame(maxWidth: OnboardingTheme.contentWidth)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .background(OnboardingTheme.background.ignoresSafeArea())
        .sheet(isPresented: $showsPolicy) { PrivacyPolicyView() }
        .preferredColorScheme(.dark)
    }
}

/// All plain-language promises in one card, separated by hairlines.
private struct PrivacyPointsCard: View {
    let points: [PrivacyContent.Point]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                if index > 0 {
                    Rectangle().fill(OnboardingTheme.hairline).frame(height: 0.5)
                        .padding(.leading, 16)
                }
                row(point)
            }
        }
        .onboardingSurface(cornerRadius: 22)
    }

    /// Heading and text start at the leading edge; the icon follows the
    /// heading directly. Sizes match the details list below.
    private func row(_ point: PrivacyContent.Point) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(point.title)
                    .font(.body.weight(.semibold))
                Image(systemName: point.symbol)
                    .font(.body.weight(.regular))
                    .imageScale(.medium)
                    .foregroundStyle(OnboardingTheme.accentGradient)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(point.text)
                .font(.callout)
                .foregroundStyle(OnboardingTheme.secondaryText)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .accessibilityElement(children: .combine)
    }
}

/// The complete terms, one tappable row per topic.
private struct PrivacyDetailsList: View {
    let sections: [PrivacyContent.Section]
    let onOpenPolicy: () -> Void
    @State private var expanded: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                    if index > 0 {
                        Rectangle().fill(OnboardingTheme.hairline).frame(height: 0.5)
                            .padding(.leading, 16)
                    }
                    row(section, isOpen: expanded.contains(index)) {
                        withAnimation(.snappy(duration: 0.25)) {
                            if expanded.contains(index) { expanded.remove(index) } else { expanded.insert(index) }
                        }
                    }
                }
                Rectangle().fill(OnboardingTheme.hairline).frame(height: 0.5)
                    .padding(.leading, 16)
                Button(action: onOpenPolicy) {
                    HStack(spacing: 12) {
                        Text(L10n("Full Privacy Policy"))
                            .font(.body.weight(.medium))
                            .foregroundStyle(OnboardingTheme.cyan)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(OnboardingTheme.tertiaryText)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onboardingSurface(cornerRadius: 20)
        }
    }

    private func row(_ section: PrivacyContent.Section, isOpen: Bool, toggle: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 12) {
                    Text(section.title)
                        .font(.body)
                        .foregroundStyle(OnboardingTheme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(OnboardingTheme.tertiaryText)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isOpen ? L10n("Expanded") : L10n("Collapsed"))
            if isOpen {
                Text(section.body)
                    .font(.callout)
                    .foregroundStyle(OnboardingTheme.secondaryText)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .clipped()
    }
}

/// A full-width checkbox: the whole card is the hit target.
private struct PrivacyCheckbox: View {
    let text: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.white.opacity(isOn ? 0 : 0.35), lineWidth: 1.5)
                    if isOn {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(OnboardingTheme.buttonGradient)
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 26, height: 26)
                .animation(.snappy(duration: 0.18), value: isOn)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .contentShape(Rectangle())
            .onboardingSurface(cornerRadius: 20)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .accessibilityIdentifier("privacyAcknowledgement")
    }
}

/// The full policy uses the same top-left title and top-right close control.
struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let policy = PrivacyContent.policy(language: AppLanguageSettings.shared.language)
        let lines = policy.components(separatedBy: "\n")
        GeometryReader { geometry in
            VStack(spacing: 0) {
                PrivacyPageHeader(title: String((lines.first ?? L10n("Privacy Policy"))
                    .drop(while: { $0 == "#" || $0 == " " }))) { dismiss() }
                ScrollView {
                    PrivacyDocumentBody(markdown: lines.dropFirst().joined(separator: "\n"))
                        .frame(width: min(OnboardingTheme.contentWidth, max(0, geometry.size.width - 48)))
                        .padding(24)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(OnboardingTheme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

private struct PrivacyPageHeader: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .headerTitle, spacing: 16) {
            Text(title)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(OnboardingTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .headerTitleGuide()
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.accentGradient)
                    .frame(width: 44, height: 44)
                    .background { Circle().fill(.white.opacity(0.08)) }
                    .overlay { Circle().strokeBorder(OnboardingTheme.hairline, lineWidth: 0.5) }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .layoutPriority(1)
            .accessibilityLabel(L10n("Close"))
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 8)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)
    }
}

/// Renders headings, paragraphs, bullets and table rows without flattening
/// the supplied Markdown into an unreadable single label.
private struct PrivacyDocumentBody: View {
    let markdown: String

    private var blocks: [String] {
        markdown.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                if block.hasPrefix("#") {
                    Text(block.drop(while: { $0 == "#" || $0 == " " }))
                        .font(block.hasPrefix("## ") ? .title3.weight(.semibold) : .headline)
                        .padding(.top, block.hasPrefix("## ") ? 14 : 4)
                        .accessibilityAddTraits(.isHeader)
                } else if block.hasPrefix("| ") {
                    table(block)
                } else {
                    paragraph(block)
                }
            }
        }
        .foregroundStyle(OnboardingTheme.primaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    /// Bullets get a hanging indent so wrapped lines stay aligned.
    private func paragraph(_ block: String) -> some View {
        let lines = block.components(separatedBy: "\n")
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                if line.hasPrefix("- ") {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(OnboardingTheme.accentGradient).frame(width: 5, height: 5)
                            .alignmentGuide(.firstTextBaseline) { $0.height + 4 }
                        Text(.init(String(line.dropFirst(2))))
                    }
                } else {
                    Text(.init(line))
                }
            }
        }
        .font(.callout)
        .foregroundStyle(OnboardingTheme.primaryText.opacity(0.86))
        .lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func table(_ markdown: String) -> some View {
        let rows = markdown.split(separator: "\n").map { line in
            line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }.filter { !$0.allSatisfy { $0.allSatisfy { "-: ".contains($0) } } }
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(rows.dropFirst().enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(row.enumerated()), id: \.offset) { index, cell in
                        Text(.init(cell))
                            .font(index == 0 ? .callout.weight(.semibold) : .callout)
                            .foregroundStyle(index == 0 ? OnboardingTheme.primaryText : OnboardingTheme.secondaryText)
                    }
                }
            }
        }
    }
}

struct PrivacyActionCard: View {
    let title: String
    let isAccepted: Bool
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                Text(title)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            GlowToggle(isOn: isAccepted, label: title, action: onOpen)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onboardingSurface(cornerRadius: 24)
    }
}
