import PhotosUI
import SwiftUI

/// Objecting to the newest report against this account: what it said, then
/// the person's own words.
///
/// For "may be under 18" the same screen confirms the person's age instead:
/// the account stays locked until then. A live scan reads the
/// machine-readable zone of a passport or ID card and sends only the given
/// names' initials, the birth date and the expiry date, never the photo. The
/// screen only says whether the document could be read, never whether it
/// matches the profile, so nobody can try documents until one passes; the
/// server compares. When the document can't be read, the person requests a
/// manual review with a photo of the document. The photo is shown here so
/// the person sees what they added, but it stays on the phone: only that one
/// was added is sent. The screen says neither that, nor who reviews.
struct ReportObjectionSheet: View {
    let status: ModerationStatus
    let report: ModerationStatus.LatestReport
    /// This phone's profile. The server compares the document itself.
    let displayName: String
    let birthDate: CalendarDate?
    let onSubmit: (_ message: String, _ proof: AgeProof?) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var zone: MachineReadableZone?
    @State private var showsScanner = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showsLibrary = false
    @State private var showsCamera = false
    @State private var isSending = false
    @State private var sendError: String?
    /// "Request manual review" instead of a read document.
    @State private var writesInstead = false
    /// The photo of the document for the manual review: in memory while
    /// this screen is open, never stored or sent.
    @State private var documentPhoto: UIImage?
    @FocusState private var messageFocused: Bool

    static let messageLimit = 2000

    /// `writesInstead` and `documentPhoto` open the manual review with a
    /// photo already added, for rendered UI checks.
    init(status: ModerationStatus, report: ModerationStatus.LatestReport, displayName: String,
         birthDate: CalendarDate?, writesInstead: Bool = false, documentPhoto: UIImage? = nil,
         onSubmit: @escaping (_ message: String, _ proof: AgeProof?) async throws -> Void) {
        self.status = status
        self.report = report
        self.displayName = displayName
        self.birthDate = birthDate
        self.onSubmit = onSubmit
        _writesInstead = State(initialValue: writesInstead)
        _documentPhoto = State(initialValue: documentPhoto)
    }

    private var isAgeCheck: Bool { report.reportReason == .underage }

    private var trimmedMessage: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSend: Bool {
        guard !isSending else { return false }
        if isAgeCheck { return writesInstead ? documentPhoto != nil : zone != nil }
        return !trimmedMessage.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                reportCard

                if isAgeCheck {
                    proofOfAge
                    if writesInstead { explanation(placeholder: L10n("Anything you want to add (optional)")) }
                } else {
                    explanation(placeholder: L10n("Why is this report wrong?"))
                }

                VStack(spacing: 10) {
                    Button {
                        send()
                    } label: {
                        if isSending { ProgressView().tint(.white) } else { Text(sendTitle) }
                    }
                    .buttonStyle(GlowButtonStyle())
                    .disabled(!canSend)
                    .accessibilityIdentifier("objection.send")

                    if !isAgeCheck {
                        ModerationWarning(text: L10n("An unjustified objection can lead to the immediate termination of your account."))
                    }
                }
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
        .photosPicker(isPresented: $showsLibrary, selection: $pickedPhoto, matching: .images)
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task {
                let image = (try? await item.loadTransferable(type: Data.self)).flatMap(UIImage.init(data:))
                pickedPhoto = nil
                keep(image)
            }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraImagePicker { image in
                showsCamera = false
                keep(image)
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showsScanner) {
            IDDocumentScanView { zone = $0 }
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

    private var sendTitle: String {
        if !isAgeCheck { return L10n("Send objection") }
        return writesInstead ? L10n("Request manual review") : L10n("Confirm age")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(isAgeCheck ? L10n("Confirm your age") : L10n("Object"))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(isAgeCheck
                     ? L10n("Your account stays locked until your age is confirmed.")
                     : L10n("Tell us in your own words why this report is not right."))
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

    /// The report this objection is about.
    private var reportCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n("Reason"))
                .font(.system(.footnote, weight: .medium))
                .foregroundStyle(OnboardingTheme.cyan)
            Text((report.reportReason ?? .other).title)
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(OnboardingTheme.primaryText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onboardingSurface(cornerRadius: 16)
        .accessibilityElement(children: .combine)
    }

    private func explanation(placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L10n("Your explanation"))
            TextField(placeholder, text: $message, axis: .vertical)
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
    }

    // MARK: Proof of age

    /// One tile, like the photo square of automatic matching: the live scan,
    /// or the photo for a manual review. A tap on it starts over.
    private var proofOfAge: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L10n("Passport or ID card"))
            Group {
                if writesInstead { photoTile } else { scanTile }
            }
            .transition(.opacity)

            Button(writesInstead ? L10n("Scan my document instead") : L10n("Request manual review")) {
                withAnimation(.easeInOut(duration: 0.25)) { writesInstead.toggle() }
            }
            .font(.system(.subheadline, weight: .semibold))
            .foregroundStyle(OnboardingTheme.cyan)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .disabled(isSending)
            .accessibilityIdentifier("objection.manualReview")
        }
    }

    private var scanTile: some View {
        Button { showsScanner = true } label: {
            if zone != nil {
                // Read, nothing more: whether it matches is for the server.
                DocumentTile(symbol: "checkmark.seal.fill", title: L10n("Document read"), isDone: true, tips: [
                    ("lock.fill", L10n("Only your initials and dates are sent, never the photo.")),
                ])
            } else {
                DocumentTile(symbol: "text.viewfinder", title: L10n("Scan your passport or ID card"), tips: [
                    ("rectangle.and.text.magnifyingglass", L10n("Use the side with the lines of <<<")),
                    ("sun.max.fill", L10n("Good light, no glare")),
                    ("lock.fill", L10n("Only your initials and dates are sent, never the photo.")),
                ])
            }
        }
        .buttonStyle(.plain)
        .disabled(isSending)
        .accessibilityHint(zone == nil ? L10n("Opens the camera to scan your document.") : L10n("Scans your document again."))
        .accessibilityIdentifier(zone == nil ? "objection.scan" : "objection.documentRead")
    }

    /// The photo itself once added, so the person sees what they chose; a
    /// tap picks another. It can't be removed: the review needs one.
    @ViewBuilder
    private var photoTile: some View {
        let label = Group {
            if let documentPhoto {
                Color.clear
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay {
                        Image(uiImage: documentPhoto)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DocumentTile.radius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: DocumentTile.radius, style: .continuous)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: DocumentTile.radius, style: .continuous))
                    .accessibilityElement()
                    .accessibilityLabel(L10n("Choose another photo"))
                    .accessibilityIdentifier("objection.photo")
            } else {
                DocumentTile(symbol: "camera.fill", title: L10n("Add a photo of your passport or ID card"), tips: [
                    ("viewfinder", L10n("The whole document in view")),
                    ("text.magnifyingglass", L10n("Sharp and readable")),
                    ("sun.max.fill", L10n("No glare or fingers in the way")),
                ])
                .accessibilityIdentifier("objection.addPhoto")
            }
        }
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            Menu {
                Button(L10n("Take photo"), systemImage: "camera") { showsCamera = true }
                Button(L10n("Choose photo"), systemImage: "photo") { showsLibrary = true }
            } label: {
                label
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .disabled(isSending)
        } else {
            Button { showsLibrary = true } label: { label }
                .buttonStyle(.plain)
                .disabled(isSending)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(OnboardingTheme.tertiaryText)
    }

    // MARK: Actions

    /// Kept small: only shown here, and dropped with this screen.
    private func keep(_ image: UIImage?) {
        guard let image else { return }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 1600 / max(longest, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        withAnimation(.easeInOut(duration: 0.25)) {
            documentPhoto = image.preparingThumbnail(of: size) ?? image
        }
    }

    private func send() {
        messageFocused = false
        guard canSend else { return }
        isSending = true
        let proof: AgeProof? = !isAgeCheck ? nil : writesInstead ? .manualReview : zone.map { .document($0.idCheck) }
        let words = isAgeCheck && !writesInstead ? "" : trimmedMessage
        Task {
            defer { isSending = false }
            do {
                try await onSubmit(words, proof)
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
        if text.contains("Proof of age") || text.contains("Photo required") {
            return L10n("Your document could not be checked. Please take a new photo.")
        }
        return L10n("Check your connection and try again.")
    }
}

/// The empty square of automatic matching's photo, for a document: a badge
/// top left, a title, and the tips under a hairline. Dashed until done.
private struct DocumentTile: View {
    static let radius: CGFloat = 28

    let symbol: String
    let title: String
    var isDone = false
    let tips: [(symbol: String, text: String)]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.08))
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                if isDone {
                    Image(systemName: symbol)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, OnboardingTheme.cyan)
                        .font(.system(size: 26, weight: .semibold))
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.accentGradient)
                }
            }
            .frame(width: 52, height: 52)
            .accessibilityHidden(true)

            Text(title)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(OnboardingTheme.primaryText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)

            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(height: 1)
                .padding(.vertical, 14)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(tips, id: \.text) { tip in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: tip.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(OnboardingTheme.cyan)
                            .frame(width: 20)
                            .accessibilityHidden(true)
                        Text(tip.text)
                            .font(.subheadline)
                            .foregroundStyle(OnboardingTheme.primaryText.opacity(0.86))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background { shape.fill(.white.opacity(0.05)) }
        .overlay {
            if isDone {
                shape.strokeBorder(OnboardingTheme.cyan.opacity(0.55), lineWidth: 1)
            } else {
                shape.strokeBorder(.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            }
        }
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
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
