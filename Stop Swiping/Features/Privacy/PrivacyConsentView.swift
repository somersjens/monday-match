import SwiftUI

struct PrivacyConsentView: View {
    let kind: PrivacyConsentKind
    let onAccept: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var acknowledged = false
    @State private var showsDetails = false
    @State private var showsPolicy = false

    var body: some View {
        let copy = PrivacyContent.approval(kind, language: AppLanguageSettings.shared.language)
        VStack(spacing: 0) {
            PrivacyPageHeader(title: copy.title) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PrivacyDocumentBody(markdown: copy.summary)
                    DisclosureGroup(L10n("Read more"), isExpanded: $showsDetails) {
                        PrivacyDocumentBody(markdown: copy.details).padding(.top, 16)
                    }
                    .tint(OnboardingTheme.cyan)
                    Button(L10n("Read the full Privacy Policy")) { showsPolicy = true }
                        .foregroundStyle(OnboardingTheme.cyan)
                        .frame(minHeight: 44)
                    Toggle(isOn: $acknowledged) {
                        Text(copy.acknowledgement)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .tint(OnboardingTheme.violet)
                    .accessibilityIdentifier("privacyAcknowledgement")
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
                .foregroundStyle(OnboardingTheme.primaryText)
                .frame(maxWidth: OnboardingTheme.contentWidth)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
        .background(OnboardingTheme.background.ignoresSafeArea())
        .sheet(isPresented: $showsPolicy) { PrivacyPolicyView() }
        .preferredColorScheme(.dark)
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
        HStack(alignment: .top, spacing: 16) {
            Text(title)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(OnboardingTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
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
        LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                if block.hasPrefix("#") {
                    Text(block.drop(while: { $0 == "#" || $0 == " " }))
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                } else if block.hasPrefix("| ") {
                    table(block)
                } else {
                    Text(.init(block.replacingOccurrences(of: "\n- ", with: "\n\n• ")
                        .replacingOccurrences(of: "^- ", with: "• ", options: .regularExpression)))
                        .font(.subheadline)
                        .lineSpacing(4)
                }
            }
        }
        .foregroundStyle(OnboardingTheme.primaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
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
                            .font(index == 0 ? .subheadline.weight(.semibold) : .subheadline)
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
