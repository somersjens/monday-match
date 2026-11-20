import PhotosUI
import SwiftUI

/// Objecting to the newest report against this account: what it said and
/// what it does, then the person's own words. For "may be under 18" they
/// also prove their age with a passport or ID card. The phone reads the
/// document's machine-readable zone and compares the first initial and the
/// birth date with the profile; only those facts are sent, never the photo.
/// An administrator then approves (the report is withdrawn) or rejects it.
struct ReportObjectionSheet: View {
    let status: ModerationStatus
    let report: ModerationStatus.LatestReport
    /// This phone's profile, to compare the document with.
    let displayName: String
    let birthDate: CalendarDate?
    let onSubmit: (_ message: String, _ idCheck: ReportIDCheck?) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var zone: MachineReadableZone?
    @State private var isReading = false
    @State private var readFailed = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showsCamera = false
    @State private var isSending = false
    @State private var sendError: String?
    @FocusState private var messageFocused: Bool

    static let messageLimit = 2000

    private var needsProofOfAge: Bool { report.reportReason == .underage }

    private var trimmedMessage: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSend: Bool {
        !isSending && !trimmedMessage.isEmpty && (!needsProofOfAge || zone != nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                reportCard

                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle(L10n("Your explanation"))
                    TextField(L10n("Why is this report wrong?"), text: $message, axis: .vertical)
                        .lineLimit(6...14)
                        .focused($messageFocused)
                        .foregroundStyle(OnboardingTheme.primaryText)
                        .tint(OnboardingTheme.cyan)
                        .padding(14)
                        .onboardingSurface(cornerRadius: 16)
                        .onChange(of: message) { _, text in
                            if text.count > Self.messageLimit { message = String(text.prefix(Self.messageLimit)) }
                        }
                        .accessibilityIdentifier("objection.message")
                }

                if needsProofOfAge { proofOfAge }

                Button {
                    send()
                } label: {
                    if isSending { ProgressView().tint(.white) } else { Text(L10n("Send objection")) }
                }
                .buttonStyle(GlowButtonStyle())
                .disabled(!canSend)
                .accessibilityIdentifier("objection.send")
            }
            .frame(maxWidth: OnboardingTheme.contentWidth)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { messageFocused = false }
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(OnboardingTheme.background.ignoresSafeArea())
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task {
                let image = (try? await item.loadTransferable(type: Data.self)).flatMap(UIImage.init(data:))
                pickedPhoto = nil
                await read(image)
            }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraImagePicker { image in
                showsCamera = false
                Task { await read(image) }
            }
            .ignoresSafeArea()
        }
        .alert(L10n("Could not send your objection"), isPresented: Binding(
            get: { sendError != nil }, set: { if !$0 { sendError = nil } })) {
            Button(L10n("OK"), role: .cancel) {}
        } message: {
            Text(sendError ?? "")
        }
        .interactiveDismissDisabled(isSending)
        .presentationBackground(OnboardingTheme.background)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n("Object"))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(L10n("Tell us in your own words why this report is not right."))
                    .font(.subheadline)
                    .foregroundStyle(OnboardingTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            BrandCrossButton { dismiss() }
                .disabled(isSending)
        }
    }

    /// The report this objection is about, and what it does.
    private var reportCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: (report.reportReason ?? .other).symbol)
                    .foregroundStyle(OnboardingTheme.accentGradient)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text((report.reportReason ?? .other).title)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onboardingSurface(cornerRadius: 16)
        .accessibilityElement(children: .combine)
    }

    // MARK: Proof of age

    private var proofOfAge: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L10n("Prove your age"))
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n("Photograph the lines of <<< on your passport or ID card. Your phone checks your initial and date of birth; the photo is not sent."))
                    .font(.footnote)
                    .foregroundStyle(OnboardingTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if isReading {
                    HStack(spacing: 10) {
                        ProgressView().tint(OnboardingTheme.cyan)
                        Text(L10n("Reading your document…"))
                            .font(.footnote)
                            .foregroundStyle(OnboardingTheme.secondaryText)
                    }
                } else if let zone {
                    documentResult(zone)
                } else if readFailed {
                    Label(L10n("Could not read the document. Keep the lines of <<< sharp and fully in view."),
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(OnboardingTheme.pink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showsCamera = true } label: {
                            Label(zone == nil ? L10n("Take photo") : L10n("Retake"), systemImage: "camera")
                        }
                        .buttonStyle(DocumentButtonStyle())
                        .accessibilityIdentifier("objection.camera")
                    }
                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        Label(L10n("Choose photo"), systemImage: "photo")
                    }
                    .buttonStyle(DocumentButtonStyle())
                    .accessibilityIdentifier("objection.library")
                }
                .disabled(isReading || isSending)
            }
            .padding(14)
            .onboardingSurface(cornerRadius: 16)
        }
    }

    @ViewBuilder
    private func documentResult(_ zone: MachineReadableZone) -> some View {
        let comparison = birthDate.map { IDDocumentComparison(zone: zone, displayName: displayName, birthDate: $0) }
        VStack(alignment: .leading, spacing: 6) {
            checkRow(L10n("First initial \(zone.initial)"), matches: comparison?.initialMatches,
                     detail: comparison?.initialMatches == false ? L10n("Does not match your name") : nil)
            checkRow(L10n("Born \(Self.formatted(zone.birthDate))"), matches: comparison?.birthDateMatches,
                     detail: comparison?.birthDateMatches == false ? L10n("Does not match your profile") : nil)
            checkRow(L10n("18 or older"), matches: comparison?.isAdult ?? (IDDocumentComparison.age(of: zone.birthDate, on: .today()) >= 18),
                     detail: nil)
            if comparison?.isExpired == true {
                checkRow(L10n("This document has expired"), matches: false, detail: nil)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("objection.documentResult")
    }

    private func checkRow(_ text: String, matches: Bool?, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: matches == false ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(matches == false ? OnboardingTheme.pink : OnboardingTheme.cyan)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(OnboardingTheme.primaryText)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(OnboardingTheme.secondaryText)
                }
            }
        }
    }

    static func formatted(_ date: CalendarDate) -> String {
        guard let day = date.date() else { return MachineReadableZone.iso(date) }
        return day.formatted(.dateTime.day().month(.wide).year().locale(AppLocale.current))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(OnboardingTheme.tertiaryText)
    }

    // MARK: Actions

    private func read(_ image: UIImage?) async {
        guard let image else { return }
        isReading = true
        readFailed = false
        let result = await IDDocumentScanner.read(image)
        isReading = false
        zone = result
        readFailed = result == nil
    }

    private func send() {
        messageFocused = false
        guard canSend else { return }
        isSending = true
        Task {
            defer { isSending = false }
            do {
                try await onSubmit(trimmedMessage, needsProofOfAge ? zone?.idCheck : nil)
                AccessibilityNotification.Announcement(L10n("Your objection was sent.")).post()
                dismiss()
            } catch {
                sendError = Self.explanation(of: error)
            }
        }
    }

    static func explanation(of error: Error) -> String {
        let text = String(describing: error)
        if text.contains("Objection already made") { return L10n("You already objected to this report.") }
        if text.contains("Report unavailable") { return L10n("This report no longer counts against your account.") }
        if text.contains("Proof of age") { return L10n("Your document could not be checked. Please take a new photo.") }
        return L10n("Check your connection and try again.")
    }
}

private struct DocumentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(OnboardingTheme.primaryText.opacity(isEnabled ? 1 : 0.5))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(configuration.isPressed ? 0.14 : 0.08))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(OnboardingTheme.hairline, lineWidth: 0.5)
            }
            .contentShape(Rectangle())
    }
}

/// The system camera, for one still photo.
struct CameraImagePicker: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
