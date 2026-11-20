import SwiftUI

/// For administrators only, behind the shield at the home screen's top
/// left: every open objection to a report. Each shows the report first (its
/// reason, explanation and, if the reporter added it, the conversation),
/// then the objection. Approve (green) withdraws the report, which lifts a
/// block or ban it caused; reject (red) keeps it. Plain reports without an
/// objection never show here.
struct AdminObjectionsView: View {
    let load: () async throws -> [AdminObjection]
    let decide: (_ objectionID: UUID, _ approve: Bool) async throws -> Void
    /// This administrator's own name, for a demo report about themself: the
    /// server holds no profile while automatic matching is off.
    var ownName: String = ""

    @Environment(\.dismiss) private var dismiss
    @State private var objections: [AdminObjection] = []
    @State private var hasLoaded = false
    @State private var loadFailed = false
    @State private var deciding: UUID?
    @State private var pending: (objection: AdminObjection, approve: Bool)?
    @State private var decideFailed = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header
                if !hasLoaded {
                    ProgressView()
                        .tint(OnboardingTheme.cyan)
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else if loadFailed && objections.isEmpty {
                    emptyState(L10n("The objections could not be loaded."), symbol: "wifi.exclamationmark")
                } else if objections.isEmpty {
                    emptyState(L10n("No open objections."), symbol: "checkmark.seal")
                } else {
                    ForEach(objections) { objection in
                        ObjectionCard(objection: objection, ownName: ownName, isDeciding: deciding == objection.id) { approve in
                            pending = (objection, approve)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                }
            }
            .frame(maxWidth: OnboardingTheme.contentWidth)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.25), value: objections.map(\.id))
        }
        .scrollIndicators(.hidden)
        .refreshable { await reload() }
        .background(OnboardingTheme.background.ignoresSafeArea())
        .task { await reload() }
        .alert(pending?.approve == true ? L10n("Approve this objection?") : L10n("Reject this objection?"),
               isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
               presenting: pending) { choice in
            Button(L10n("Cancel"), role: .cancel) {}
            Button(choice.approve ? L10n("Approve") : L10n("Reject"), role: choice.approve ? nil : .destructive) {
                Task { await apply(choice.objection, approve: choice.approve) }
            }
        } message: { choice in
            Text(choice.approve
                 ? L10n("The report is withdrawn and no longer counts. A block or ban it caused ends now.")
                 : L10n("The report stands. The person sees that their objection was rejected."))
        }
        .alert(L10n("Could not save the decision"), isPresented: $decideFailed) {
            Button(L10n("OK"), role: .cancel) {}
        }
        .presentationBackground(OnboardingTheme.background)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n("Objections"))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(OnboardingTheme.primaryText)
                Text(L10n("First the complaint, then the objection."))
                    .font(.subheadline)
                    .foregroundStyle(OnboardingTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            BrandCrossButton { dismiss() }
        }
    }

    private func emptyState(_ text: String, symbol: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(OnboardingTheme.accentGradient)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(OnboardingTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func reload() async {
        do {
            objections = try await load()
            loadFailed = false
        } catch {
            loadFailed = true
        }
        hasLoaded = true
    }

    private func apply(_ objection: AdminObjection, approve: Bool) async {
        deciding = objection.id
        defer { deciding = nil }
        do {
            try await decide(objection.id, approve)
            objections.removeAll { $0.id == objection.id }
        } catch {
            decideFailed = true
            await reload()
        }
    }
}

/// One objection: the report, then the objection, then the two decisions.
private struct ObjectionCard: View {
    let objection: AdminObjection
    var ownName: String = ""
    let isDeciding: Bool
    let onDecide: (_ approve: Bool) -> Void

    @State private var showsChat = false

    private var reason: ReportReason { ReportReason(rawValue: objection.report.reason) ?? .other }

    private var name: String {
        if let name = objection.displayName, !name.isEmpty { return name }
        if objection.report.isDemo, !ownName.isEmpty { return ownName }
        return L10n("Unknown name")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(.system(.headline))
                    .foregroundStyle(OnboardingTheme.primaryText)
                Spacer(minLength: 8)
                Text(consequence)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OnboardingTheme.pink)
            }

            section(L10n("Complaint"), date: objection.report.createdAt) {
                Label(reason.title, systemImage: reason.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                Text(objection.report.details.isEmpty ? L10n("No explanation given.") : objection.report.details)
                    .font(.subheadline)
                    .foregroundStyle(objection.report.details.isEmpty ? OnboardingTheme.tertiaryText : OnboardingTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if objection.report.isDemo {
                    Text(L10n("Demo report: you reported the demo match yourself."))
                        .font(.caption)
                        .foregroundStyle(OnboardingTheme.secondaryText)
                }
                if objection.report.endedMatch {
                    Text(L10n("The reporter also broke the match."))
                        .font(.caption)
                        .foregroundStyle(OnboardingTheme.secondaryText)
                }
                chat
            }

            section(L10n("Objection"), date: objection.createdAt) {
                Text(objection.message.isEmpty ? L10n("No explanation given.") : objection.message)
                    .font(.subheadline)
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if let check = objection.idCheck { idCheck(check) }
            }

            HStack(spacing: 10) {
                decisionButton(L10n("Reject"), symbol: "xmark", color: .red) { onDecide(false) }
                    .accessibilityIdentifier("admin.reject")
                decisionButton(L10n("Approve"), symbol: "checkmark", color: .green) { onDecide(true) }
                    .accessibilityIdentifier("admin.approve")
            }
            .disabled(isDeciding)
            .overlay { if isDeciding { ProgressView().tint(.white) } }
        }
        .padding(16)
        .onboardingSurface(cornerRadius: 20)
        .accessibilityElement(children: .contain)
    }

    private var consequence: String {
        if objection.report.isDemo { return L10n("Demo") }
        return switch objection.report.strike {
        case ...1: L10n("Warning")
        case 2: L10n("7-day block")
        default: L10n("Ban")
        }
    }

    @ViewBuilder
    private var chat: some View {
        if let lines = objection.report.chatCopy, !lines.isEmpty {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { showsChat.toggle() }
            } label: {
                HStack {
                    Label(L10n("Conversation (\(lines.count) messages)"), systemImage: "bubble.left.and.bubble.right")
                    Spacer()
                    Image(systemName: "chevron.down").rotationEffect(.degrees(showsChat ? 180 : 0))
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(OnboardingTheme.cyan)
                .frame(minHeight: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showsChat {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: "\(line.from == .reporter ? L10n("Reporter") : L10n("Reported")) · \(line.at.formatted(.dateTime.day().month().hour().minute().locale(AppLocale.current)))")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(line.from == .reported ? OnboardingTheme.pink : OnboardingTheme.tertiaryText)
                            Text(line.text)
                                .font(.footnote)
                                .foregroundStyle(OnboardingTheme.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: line.from == .reported ? .leading : .trailing)
                    }
                }
                .padding(12)
                .background { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.25)) }
            }
        } else {
            Text(L10n("No conversation attached."))
                .font(.caption)
                .foregroundStyle(OnboardingTheme.tertiaryText)
        }
    }

    private func idCheck(_ check: AdminObjection.IDCheck) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n("Proof of age (read on their phone)"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(OnboardingTheme.secondaryText)
            row(L10n("Initial \(check.initial ?? "?") – profile \(check.profileInitial ?? "?")"), ok: check.initialMatches)
            row(L10n("Born \(check.birthDate ?? "?") – profile \(check.profileBirthDate ?? "?")"), ok: check.birthDateMatches)
            row(L10n("18 or older"), ok: check.adult)
            row(L10n("Check digits valid"), ok: check.checkDigits)
            if check.expired == true { row(L10n("This document has expired"), ok: false) }
            if objection.ageProvenBefore {
                Label(L10n("Age already approved automatically before"), systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(OnboardingTheme.pink)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.05)) }
    }

    private func row(_ text: String, ok: Bool?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: ok == true ? "checkmark.circle.fill" : ok == false ? "xmark.circle.fill" : "questionmark.circle")
                .foregroundStyle(ok == true ? Color.green : ok == false ? Color.red : OnboardingTheme.tertiaryText)
            Text(text)
                .font(.footnote)
                .foregroundStyle(OnboardingTheme.primaryText)
        }
    }

    private func section<Content: View>(_ title: String, date: Date, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(OnboardingTheme.tertiaryText)
                Spacer()
                Text(date.formatted(.dateTime.day().month().year().hour().minute().locale(AppLocale.current)))
                    .font(.caption2)
                    .foregroundStyle(OnboardingTheme.tertiaryText)
            }
            content()
        }
    }

    private func decisionButton(_ title: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(0.85)) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The shield at the home screen's top left, opposite the QR code, for
/// administrators. A badge counts the open objections.
struct AdminObjectionsButton: View {
    var size: CGFloat = 44
    let pending: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: size * 19 / 44, weight: .semibold))
                .foregroundStyle(OnboardingTheme.accentGradient)
                .frame(width: size, height: size)
                .background {
                    Circle().fill(LinearGradient(
                        colors: [OnboardingTheme.blue.opacity(0.24), OnboardingTheme.violet.opacity(0.20)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                }
                .overlay {
                    Circle().strokeBorder(OnboardingTheme.accentGradient.opacity(0.45), lineWidth: 1)
                }
                .overlay(alignment: .topTrailing) {
                    if pending > 0 {
                        Text(pending > 99 ? "99+" : "\(pending)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background { Capsule().fill(OnboardingTheme.pink) }
                            .offset(x: 4, y: -4)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n("Objections"))
        .accessibilityValue(pending > 0 ? L10n("\(pending) open") : L10n("None open"))
        .accessibilityIdentifier("admin.objections")
    }
}
