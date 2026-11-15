import SwiftUI

/// The questionnaire's progress, with the time left on the early-adopter
/// offer beside it while that window is running. Every question screen is an
/// equal share of the bar, however many parts it has.
struct OnboardingProgressCard: View {
    /// From 0 to 1.
    let progress: Double
    /// The early-adopter deadline. Nil, or a moment already passed, hides the
    /// countdown: lifetime access has no deadline.
    var deadline: Date?
    /// The last question was answered: the bar fills, the countdown gives way
    /// to a checkmark and a light runs along the bar.
    var isFinished = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep: CGFloat = -0.35
    @State private var glows = false

    private static let cornerRadius: CGFloat = 20
    private static let outline = LinearGradient(
        colors: [OnboardingTheme.cyan, OnboardingTheme.blue, OnboardingTheme.violet],
        startPoint: .leading, endPoint: .trailing)

    private var clampedProgress: Double { min(max(isFinished ? 1 : progress, 0), 1) }
    private var locale: Locale { AppLanguageSettings.shared.language.locale }

    var body: some View {
        // Ticks every second only while there is a countdown to show.
        TimelineView(.periodic(from: .now, by: deadline == nil ? 3_600 : 1)) { context in
            let remaining = deadline.map { $0.timeIntervalSince(context.date) } ?? 0
            let showsTimer = !isFinished && remaining > 0

            // Narrow phones drop the clock badge and tighten the type.
            ViewThatFits(in: .horizontal) {
                row(remaining: remaining, showsTimer: showsTimer, compact: false)
                row(remaining: remaining, showsTimer: showsTimer, compact: true)
            }
            .background { background }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(remaining: showsTimer ? remaining : nil))
        }
        .animation(OnboardingMotion.resolved(.spring(duration: 0.6, bounce: 0.12), reduceMotion: reduceMotion),
                   value: clampedProgress)
        .animation(OnboardingMotion.resolved(.spring(duration: 0.55, bounce: 0.22), reduceMotion: reduceMotion),
                   value: isFinished)
        .onChange(of: isFinished) { _, finished in
            guard finished else { return }
            celebrate()
        }
    }

    // MARK: - Sections

    /// The percentage, the countdown and their symbols share one size, and
    /// the bar is as thick as the digits are tall.
    private static func valueFont(compact: Bool) -> Font {
        .system(size: compact ? 17 : 19, weight: .semibold)
    }

    private static func barHeight(compact: Bool) -> CGFloat { compact ? 12 : 14 }

    private func row(remaining: TimeInterval, showsTimer: Bool, compact: Bool) -> some View {
        HStack(spacing: 0) {
            progressSection(compact: compact)
            if showsTimer || isFinished {
                Rectangle()
                    .fill(OnboardingTheme.hairline)
                    .frame(width: 1, height: 26)
                    .padding(.horizontal, compact ? 12 : 16)
                    .transition(.opacity)
                // Sized for the widest of the countdown and the checkmark, so
                // the bar keeps its length when one replaces the other.
                ZStack(alignment: .trailing) {
                    timerSection(Self.widestCountdown, compact: compact).hidden()
                    finishedSection(compact: compact).hidden()
                    if isFinished {
                        finishedSection(compact: compact)
                            .transition(.sealReveal(reduceMotion: reduceMotion))
                    } else {
                        timerSection(remaining, compact: compact)
                            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
                    }
                }
                .fixedSize()
                .accessibilityHidden(true)
            }
        }
        .font(Self.valueFont(compact: compact))
        .monospacedDigit()
        .foregroundStyle(OnboardingTheme.primaryText)
        .lineLimit(1)
        .padding(.horizontal, compact ? 14 : 18)
        .padding(.vertical, 18)
    }

    private func progressSection(compact: Bool) -> some View {
        HStack(spacing: compact ? 10 : 14) {
            bar(compact: compact)
            // Always as wide as 100%, so reaching it doesn't move the bar.
            ZStack(alignment: .trailing) {
                Text(1.0, format: Self.percentStyle(locale)).hidden()
                Text(clampedProgress, format: Self.percentStyle(locale))
                    .contentTransition(.numericText(value: clampedProgress))
            }
            .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bar(compact: Bool) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width * clampedProgress
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.09))
                Capsule()
                    .fill(OnboardingTheme.accentGradient)
                    .frame(width: width)
                    .overlay {
                        // A single light that runs along the full bar.
                        LinearGradient(colors: [.clear, .white.opacity(0.75), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: max(proxy.size.width * 0.3, 1))
                            .offset(x: proxy.size.width * sweep)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .blendMode(.plusLighter)
                            .opacity(isFinished ? 1 : 0)
                    }
                    .clipShape(Capsule())
                    .shadow(color: OnboardingTheme.blue.opacity(glows ? 0.9 : 0.55), radius: glows ? 10 : 5)
                    .opacity(clampedProgress > 0 ? 1 : 0)
            }
        }
        .frame(height: Self.barHeight(compact: compact))
        .frame(minWidth: 56)
    }

    private func timerSection(_ remaining: TimeInterval, compact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 8) {
            symbol("clock")
            Text(Self.countdown(remaining))
        }
    }

    private func finishedSection(compact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 8) {
            symbol("checkmark.circle")
                .symbolEffect(.bounce, options: .nonRepeating, value: glows)
            Text(L10n("Completed"))
        }
    }

    /// Drawn in the row's font, so it is exactly as tall as the digits.
    private func symbol(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .foregroundStyle(OnboardingTheme.accentGradient)
            .accessibilityHidden(true)
    }

    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        return shape
            .fill(Color.black.opacity(0.42))
            .background(.ultraThinMaterial.opacity(0.35), in: shape)
            .overlay { shape.fill(OnboardingTheme.surface) }
            .overlay { shape.strokeBorder(Self.outline, lineWidth: 1.2).opacity(glows ? 1 : 0.75) }
            .shadow(color: OnboardingTheme.blue.opacity(glows ? 0.55 : 0.28), radius: glows ? 26 : 16)
            .shadow(color: OnboardingTheme.violet.opacity(glows ? 0.35 : 0.12), radius: glows ? 34 : 22, x: 12)
    }

    // MARK: - Finish

    private func celebrate() {
        guard !reduceMotion else {
            withAnimation(.easeInOut(duration: 0.25)) { glows = true }
            return
        }
        sweep = -0.35
        withAnimation(.easeInOut(duration: 0.5).delay(0.35)) { glows = true }
        withAnimation(.easeInOut(duration: 0.9).delay(0.45)) { sweep = 1.05 }
    }

    // MARK: - Formatting

    /// The longest the countdown gets, with days and two-digit hours.
    private static let widestCountdown: TimeInterval = 7 * 86_400 - 1

    private static func percentStyle(_ locale: Locale) -> FloatingPointFormatStyle<Double>.Percent {
        .percent.precision(.fractionLength(0)).locale(locale)
    }

    /// "6d 23:59:59", dropping the days on the last day.
    static func countdown(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let days = total / 86_400
        let hours = total % 86_400 / 3_600
        let minutes = total % 3_600 / 60
        let seconds = total % 60
        let clock = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        return days > 0 ? "\(days)d \(clock)" : clock
    }

    private func accessibilityLabel(remaining: TimeInterval?) -> String {
        let percent = clampedProgress.formatted(Self.percentStyle(locale))
        var label = "\(L10n("Progress")): \(percent)"
        if isFinished {
            label += ". \(L10n("Completed"))"
        } else if let remaining {
            let formatter = DateComponentsFormatter()
            var calendar = Calendar.current
            calendar.locale = locale
            formatter.calendar = calendar
            formatter.unitsStyle = .full
            formatter.allowedUnits = remaining >= 86_400 ? [.day, .hour] : [.hour, .minute]
            if let time = formatter.string(from: remaining) {
                label += ". \(L10n("Time remaining")): \(time)"
            }
        }
        return label
    }
}

private struct SealRevealEffect: ViewModifier {
    let scale: CGFloat
    let blur: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale, anchor: .leading)
            .blur(radius: blur)
            .opacity(opacity)
    }
}

private extension AnyTransition {
    static func sealReveal(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .modifier(active: SealRevealEffect(scale: 0.6, blur: 6, opacity: 0),
                         identity: SealRevealEffect(scale: 1, blur: 0, opacity: 1))
    }
}

#Preview {
    VStack(spacing: 24) {
        OnboardingProgressCard(progress: 0.4, deadline: Date().addingTimeInterval(7 * 86_400 - 1))
        OnboardingProgressCard(progress: 0.72)
        OnboardingProgressCard(progress: 1, deadline: Date().addingTimeInterval(3_600), isFinished: true)
    }
    .padding(24)
    .frame(maxHeight: .infinity)
    .background(OnboardingTheme.background)
    .preferredColorScheme(.dark)
}
