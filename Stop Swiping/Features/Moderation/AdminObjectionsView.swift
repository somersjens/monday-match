import SwiftUI

/// For administrators only, behind the shield at the home screen's top
/// left. First "concerning offline behavior", which comes here at once: it
/// already counts as a regular warning, and the administrator keeps it so or
/// bans the account directly. Then every open objection to a report. Each
/// shows the report first (its reason, explanation and, if the reporter
/// added it, the conversation), then the objection. Approve (green)
/// withdraws the report, which lifts a block or ban it caused; reject (red)
/// keeps it, and can also ban the account directly. Other reports without an
/// objection never show here.
///
/// A decision takes two taps and no pop-up: the chosen button turns into
/// "Undo" and the other one into "Send". Send never sits where the decision
/// was, so a double tap undoes instead of sending. A sent card leaves the
/// list at once; the server call runs behind it.
struct AdminObjectionsView: View {
    let load: () async throws -> [AdminObjection]
    let decide: (_ objectionID: UUID, _ approve: Bool, _ ban: Bool) async throws -> Void
    var loadReviews: () async throws -> [AdminReview] = { [] }
    var review: (_ reportID: UUID, _ ban: Bool) async throws -> Void = { _, _ in }
    /// This administrator's own name, for a demo report about themself: the
    /// server holds no profile while automatic matching is off.
    var ownName: String = ""

    @Environment(\.dismiss) private var dismiss
    @State private var objections: [AdminObjection] = []
    @State private var reviews: [AdminReview] = []
    @State private var hasLoaded = false
    @State private var loadFailed = false
    /// Sent decisions the server has not confirmed yet: a reload meanwhile
    /// must not bring their cards back.
    @State private var sending: Set<UUID> = []
    @State private var decideFailed = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header
                if !hasLoaded {
                    ProgressView()
                        .tint(OnboardingTheme.cyan)
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else if loadFailed && objections.isEmpty && reviews.isEmpty {
                    emptyState(L10n("The objections could not be loaded."), symbol: "wifi.exclamationmark")
                } else if objections.isEmpty && reviews.isEmpty {
                    emptyState(L10n("No open objections."), symbol: "checkmark.seal")
                } else {
                    if !reviews.isEmpty { listTitle(L10n("Concerning behavior")) }
                    ForEach(reviews) { item in
                        ReviewCard(review: item, ownName: ownName) { ban in
                            send(item, ban: ban)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                    if !reviews.isEmpty && !objections.isEmpty { listTitle(L10n("Objections")) }
                    ForEach(objections) { objection in
                        ObjectionCard(objection: objection, ownName: ownName) { approve, ban in
                            send(objection, approve: approve, ban: ban)
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
            .animation(.easeInOut(duration: 0.25), value: objections.map(\.id) + reviews.map(\.id))
        }
        .scrollIndicators(.hidden)
        .refreshable { await reload() }
        .background(OnboardingTheme.background.ignoresSafeArea())
        .task { await reload() }
        .alert(L10n("Could not save the decision"), isPresented: $decideFailed) {
            Button(L10n("OK"), role: .cancel) {}
        }
        .presentationBackground(OnboardingTheme.background)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n("Moderation"))
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

    private func listTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(OnboardingTheme.tertiaryText)
            .padding(.top, 4)
    }

    private func reload() async {
        async let loadedReviews = try? loadReviews()
        do {
            objections = try await load().filter { !sending.contains($0.id) }
            loadFailed = false
        } catch {
            loadFailed = true
        }
        if let loaded = await loadedReviews { reviews = loaded.filter { !sending.contains($0.id) } }
        hasLoaded = true
    }

    private func send(_ objection: AdminObjection, approve: Bool, ban: Bool) {
        objections.removeAll { $0.id == objection.id }
        submit(objection.id) { try await decide(objection.id, approve, ban) }
    }

    private func send(_ item: AdminReview, ban: Bool) {
        reviews.removeAll { $0.id == item.id }
        submit(item.id) { try await review(item.id, ban) }
    }

    /// The card is already gone; on failure it comes back with the reload.
    private func submit(_ id: UUID, _ call: @escaping () async throws -> Void) {
        sending.insert(id)
        Task {
            do {
                try await call()
                sending.remove(id)
            } catch {
                sending.remove(id)
                decideFailed = true
                await reload()
            }
        }
    }
}

/// One objection: the report, then the objection, then the two decisions.
private struct ObjectionCard: View {
    let objection: AdminObjection
    var ownName: String = ""
    let onSend: (_ approve: Bool, _ ban: Bool) -> Void

    @State private var staged: AdminDecisionSide?
    @State private var ban = false

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

            ComplaintSection(report: objection.report)

            AdminSection(title: L10n("Objection"), date: objection.createdAt) {
                Text(objection.message.isEmpty ? L10n("No explanation given.") : objection.message)
                    .font(.subheadline)
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if objection.idCheck?.manualReview == true {
                    Label(L10n("Manual review requested. They added a photo of their document on their phone; it was not sent."),
                          systemImage: "person.text.rectangle")
                        .font(.footnote)
                        .foregroundStyle(OnboardingTheme.secondaryText)
                } else if let check = objection.idCheck {
                    idCheck(check)
                } else if reason == .underage {
                    Label(L10n("Could not confirm their age with a document."), systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(OnboardingTheme.pink)
                }
            }

            if let date = objection.autoDecidesAt {
                AutoDecisionNote(text: L10n("Approved automatically on \(AutoDecisionNote.format(date)) if you don’t decide."))
            }

            if let staged {
                VStack(alignment: .leading, spacing: 10) {
                    StagedDecisionNote(text: staged == .right
                        ? L10n("The report is withdrawn and no longer counts. A block or ban it caused ends now.")
                        : L10n("The report stands. The person sees that their objection was rejected. For an unjustified objection you can also ban the account at once."))
                    if staged == .left {
                        Toggle(L10n("Also ban the account"), isOn: $ban)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(OnboardingTheme.primaryText)
                            .tint(.red)
                            .accessibilityIdentifier("admin.reject.ban")
                    }
                }
                .transition(.opacity)
            }

            AdminDecisionRow(
                left: .init(title: L10n("Reject"), symbol: "xmark", color: .red, identifier: "admin.reject"),
                right: .init(title: L10n("Approve"), symbol: "checkmark", color: .green, identifier: "admin.approve"),
                staged: $staged
            ) { side in
                onSend(side == .right, side == .left && ban)
            }
            .onChange(of: staged) { if staged == nil { ban = false } }
        }
        .animation(.snappy(duration: 0.22), value: staged)
        .padding(16)
        .onboardingSurface(cornerRadius: 20)
        .accessibilityElement(children: .contain)
    }

    private var consequence: String { AdminConsequence.label(objection.report) }

    private func idCheck(_ check: AdminObjection.IDCheck) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n("Proof of age (read on their phone)"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(OnboardingTheme.secondaryText)
            row(L10n("Initials \((check.initials ?? check.initial.map { [$0] } ?? ["?"]).joined(separator: ", ")) – profile \(check.profileInitial ?? "?")"),
                ok: check.initialMatches)
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
}

/// "Concerning offline behavior": the report, then keep it as a regular
/// warning or ban the account directly.
private struct ReviewCard: View {
    let review: AdminReview
    var ownName: String = ""
    let onSend: (_ ban: Bool) -> Void

    @State private var staged: AdminDecisionSide?

    private var name: String {
        if let name = review.displayName, !name.isEmpty { return name }
        if review.report.isDemo, !ownName.isEmpty { return ownName }
        return L10n("Unknown name")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(.system(.headline))
                    .foregroundStyle(OnboardingTheme.primaryText)
                Spacer(minLength: 8)
                Text(AdminConsequence.label(review.report))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OnboardingTheme.pink)
            }

            ComplaintSection(report: review.report)

            if let date = review.autoDecidesAt {
                AutoDecisionNote(text: L10n("Stays a regular warning on \(AutoDecisionNote.format(date)) if you don’t decide."))
            }

            if let staged {
                StagedDecisionNote(text: staged == .right
                    ? L10n("The account is blocked permanently, like after a third strike, and so is the phone it used. An approved objection lifts it.")
                    : L10n("The report stays a regular strike, as the person already sees it."))
                    .transition(.opacity)
            }

            AdminDecisionRow(
                left: .init(title: L10n("Regular warning"), symbol: "exclamationmark.bubble",
                            color: OnboardingTheme.blue, identifier: "admin.review.warning"),
                right: .init(title: L10n("Ban now"), symbol: "nosign", color: .red, identifier: "admin.review.ban"),
                staged: $staged
            ) { side in
                onSend(side == .right)
            }
        }
        .animation(.snappy(duration: 0.22), value: staged)
        .padding(16)
        .onboardingSurface(cornerRadius: 20)
        .accessibilityElement(children: .contain)
    }
}

/// When the server decides by itself if no administrator does.
private struct AutoDecisionNote: View {
    let text: String

    static func format(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).hour().minute().locale(AppLocale.current))
    }

    var body: some View {
        Label(text, systemImage: "clock")
            .font(.caption)
            .foregroundStyle(OnboardingTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// What the report does to the reported person's account.
private enum AdminConsequence {
    static func label(_ report: AdminObjection.Report) -> String {
        if report.isDemo { return L10n("Demo") }
        return switch report.strike {
        case ...0: L10n("Age check")
        case 1: L10n("Warning")
        case 2: L10n("7-day block")
        default: L10n("Ban")
        }
    }
}

/// The report as the reporter sent it: reason, explanation, conversation.
private struct ComplaintSection: View {
    let report: AdminObjection.Report

    @State private var showsChat = false

    private var reason: ReportReason { ReportReason(rawValue: report.reason) ?? .other }

    var body: some View {
        AdminSection(title: L10n("Complaint"), date: report.createdAt) {
            Label(reason.title, systemImage: reason.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OnboardingTheme.primaryText)
            Text(report.details.isEmpty ? L10n("No explanation given.") : report.details)
                .font(.subheadline)
                .foregroundStyle(report.details.isEmpty ? OnboardingTheme.tertiaryText : OnboardingTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if report.isDemo {
                Text(L10n("Demo report: you reported the demo match yourself."))
                    .font(.caption)
                    .foregroundStyle(OnboardingTheme.secondaryText)
            }
            if report.endedMatch {
                Text(L10n("The reporter also broke the match."))
                    .font(.caption)
                    .foregroundStyle(OnboardingTheme.secondaryText)
            }
            chat
        }
    }

    @ViewBuilder
    private var chat: some View {
        if let lines = report.chatCopy, !lines.isEmpty {
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
}

/// A titled, dated part of a card.
private struct AdminSection<Content: View>: View {
    let title: String
    let date: Date
    @ViewBuilder let content: Content

    var body: some View {
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
            content
        }
    }
}

enum AdminDecisionSide { case left, right }

/// Two decisions side by side. Tapping one stages it: that button becomes
/// "Undo" and the other becomes "Send" in the decision's colour, so Send is
/// never under the finger that just chose.
private struct AdminDecisionRow: View {
    struct Choice {
        let title: String
        let symbol: String
        let color: Color
        let identifier: String
    }

    let left: Choice
    let right: Choice
    @Binding var staged: AdminDecisionSide?
    let onSend: (AdminDecisionSide) -> Void

    var body: some View {
        HStack(spacing: 10) {
            slot(.left)
            slot(.right)
        }
        .animation(.snappy(duration: 0.22), value: staged)
        .sensoryFeedback(.selection, trigger: staged)
    }

    @ViewBuilder
    private func slot(_ side: AdminDecisionSide) -> some View {
        let choice = side == .left ? left : right
        if let staged {
            let chosen = staged == .left ? left : right
            if staged == side {
                AdminDecisionButton(title: L10n("Undo"), symbol: "arrow.uturn.backward",
                                    color: .white.opacity(0.14)) {
                    self.staged = nil
                }
                .accessibilityIdentifier("\(choice.identifier).undo")
            } else {
                AdminDecisionButton(title: L10n("Send"), symbol: "paperplane.fill", color: chosen.color) {
                    onSend(staged)
                }
                .accessibilityHint(chosen.title)
                .accessibilityIdentifier("\(chosen.identifier).send")
            }
        } else {
            AdminDecisionButton(title: choice.title, symbol: choice.symbol, color: choice.color) {
                staged = side
            }
            .accessibilityIdentifier(choice.identifier)
        }
    }
}

/// What the staged decision does, shown above Send and Undo.
private struct StagedDecisionNote: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(OnboardingTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AdminDecisionButton: View {
    let title: String
    let symbol: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(0.85)) }
                .contentShape(Rectangle())
                .contentTransition(.opacity)
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
        .accessibilityLabel(L10n("Moderation"))
        .accessibilityValue(pending > 0 ? L10n("\(pending) open") : L10n("None open"))
        .accessibilityIdentifier("admin.objections")
    }
}
