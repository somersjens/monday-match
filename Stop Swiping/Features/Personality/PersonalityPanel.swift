import SwiftUI

/// Opened from the helix: a model picker and the estimated result, while the
/// light above turns into that model's chart. The picker and the model's
/// introduction open inside the card, so nothing covers the light.
struct PersonalityPanel: View {
    let result: PersonalityResult
    /// Every model's result. The result area is as tall as the tallest of
    /// them, so switching models never resizes the card.
    let results: [PersonalityResult]
    let onSelect: (PersonalityTest) -> Void
    let onClose: () -> Void

    private enum Mode { case result, choosing, info }

    @State private var mode = Mode.result
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let cornerRadius: CGFloat = 26
    private var motion: Animation {
        OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion)
    }
    private static let quickRemoval = AnyTransition.asymmetric(
        insertion: .opacity, removal: .opacity.animation(.easeOut(duration: 0.12)))

    var body: some View {
        VStack {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    pickerButton
                    Spacer(minLength: 0)
                    closeButton
                }

                switch mode {
                case .choosing:
                    // Gone almost at once, so its rows never cross the result
                    // while the card shrinks back.
                    testList
                        .transition(.asymmetric(insertion: .opacity,
                                                removal: .opacity.animation(.linear(duration: 0.06))))
                case .info:
                    info
                        .transition(Self.quickRemoval)
                case .result:
                    resultArea
                        .transition(Self.quickRemoval)
                }

                if mode != .choosing {
                    infoButton
                        .transition(Self.quickRemoval)
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .fill(Color(red: 0.025, green: 0.03, blue: 0.09).opacity(0.94))
            )
            // Nothing spills outside the card while it grows or shrinks.
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(OnboardingTheme.accentGradient, lineWidth: 1.2)
                    .opacity(0.8)
            )
            .shadow(color: OnboardingTheme.blue.opacity(0.28), radius: 18)
            .frame(maxWidth: OnboardingTheme.controlWidth)
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
            .animation(motion, value: result.test)
        }
        .onChange(of: result.test) { _, _ in
            if mode == .info { mode = .result }
        }
    }

    private var pickerButton: some View {
        Button {
            if mode == .choosing { fold() } else { withAnimation(motion) { mode = .choosing } }
        } label: {
            HStack(spacing: 8) {
                Text(verbatim: result.test.title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(OnboardingTheme.cyan)
                    .rotationEffect(.degrees(mode == .choosing ? 180 : 0))
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Capsule().fill(OnboardingTheme.surface))
            .overlay(Capsule().strokeBorder(OnboardingTheme.accentGradient, lineWidth: 1).opacity(0.55))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n("Personality test"))
        .accessibilityValue(result.test.title)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(OnboardingTheme.primaryText.opacity(0.85))
                .frame(width: 36, height: 36)
                .background(Circle().fill(OnboardingTheme.surface))
                .overlay(Circle().strokeBorder(OnboardingTheme.accentGradient, lineWidth: 1.2).opacity(0.8))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n("Close"))
    }

    /// Folding is quick, so the shrinking card never carries the list's
    /// rows along with it.
    private func fold() {
        withAnimation(.easeOut(duration: 0.18)) { mode = .result }
    }

    /// The shown result over invisible copies of every other one: the old
    /// and new result cross in place instead of stacking, and the area keeps
    /// the tallest result's height.
    private var resultArea: some View {
        ZStack(alignment: .topLeading) {
            ForEach(results, id: \.test) { other in
                resultText(other)
                    .hidden()
                    .accessibilityHidden(true)
            }
            resultText(result)
                .id(result.test)
                .transition(.asymmetric(insertion: .onboardingReveal(reduceMotion: reduceMotion),
                                        removal: .opacity.animation(.easeOut(duration: 0.12))))
        }
    }

    private func resultText(_ result: PersonalityResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: result.headline)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(OnboardingTheme.accentGradient)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(verbatim: result.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OnboardingTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: result.summary)
                .font(.subheadline)
                .foregroundStyle(OnboardingTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One line, so it never pushes the text above around. Tapping it opens
    /// the model's introduction, and closes it again.
    private var infoButton: some View {
        Button {
            withAnimation(motion) { mode = mode == .info ? .result : .info }
        } label: {
            HStack(spacing: 5) {
                Text(L10n("Estimated from your answers · not an official test"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Image(systemName: mode == .info ? "info.circle.fill" : "info.circle")
                    .foregroundStyle(mode == .info ? OnboardingTheme.cyan : OnboardingTheme.tertiaryText)
            }
            .font(.caption2)
            .foregroundStyle(OnboardingTheme.tertiaryText)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n("Estimated from your answers · not an official test"))
        .accessibilityHint(mode == .info ? L10n("Shows your result again.") : L10n("Explains this test."))
    }

    private var info: some View {
        let legend = result.legend
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .topLeading),
                            count: legend.count > 4 ? 2 : 1)
        return VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: result.test.about)
                .font(.subheadline)
                .foregroundStyle(OnboardingTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if !legend.isEmpty {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(legend, id: \.key) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(verbatim: line.key)
                                .font(.system(.caption, design: .rounded, weight: .bold))
                                .foregroundStyle(OnboardingTheme.cyan)
                            Text(verbatim: line.value)
                                .font(.caption)
                                .foregroundStyle(OnboardingTheme.primaryText.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if let note = result.test.codeNote {
                Text(verbatim: note)
                    .font(.caption)
                    .foregroundStyle(OnboardingTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Link(destination: result.test.infoURL) {
                HStack(spacing: 4) {
                    Text(L10n("More information"))
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OnboardingTheme.cyan)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// All ten fit on most phones; a smaller screen scrolls.
    private var testList: some View {
        ViewThatFits(in: .vertical) {
            testRows
            ScrollViewReader { reader in
                ScrollView { testRows }
                    .scrollIndicators(.hidden)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.05),
                                                 .init(color: .black, location: 0.95), .init(color: .clear, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
                    .onAppear { reader.scrollTo(result.test, anchor: .center) }
            }
        }
    }

    private var testRows: some View {
        VStack(spacing: 2) {
            ForEach(PersonalityTest.allCases) { test in
                testRow(test).id(test)
            }
        }
    }

    private func testRow(_ test: PersonalityTest) -> some View {
        let isSelected = test == result.test
        return Button {
            fold()
            guard test != result.test else { return }
            // The list folds away first; the new result then crosses in place
            // in a card that already has its final height.
            Task { @MainActor in
                if !reduceMotion { try? await Task.sleep(for: .milliseconds(200)) }
                onSelect(test)
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: test.title)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.primaryText)
                    Text(verbatim: test.measures)
                        .font(.caption)
                        .foregroundStyle(OnboardingTheme.secondaryText)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(OnboardingTheme.cyan)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(OnboardingTheme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(OnboardingTheme.accentGradient, lineWidth: 1)
                                .opacity(0.5)
                        )
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The poles, traits and percentages, laid over the light's chart in the
/// same normalized space the shader draws it in.
struct PersonalityChartLabels: View {
    let result: PersonalityResult
    /// The light's centre on screen.
    let center: CGPoint
    /// Points per normalized unit.
    let unit: CGFloat

    var body: some View {
        ZStack {
            switch result.chart {
            case .spectrum(let dimensions): spectrum(dimensions)
            case .radar(let traits): radar(traits)
            case .enneagram(let traits, let type, let wing): enneagram(traits, type: type, wing: wing)
            case .wheel(let quarters, _, _): wheel(quarters)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func screen(_ point: CGPoint) -> CGPoint {
        CGPoint(x: center.x + point.x * unit, y: center.y + point.y * unit)
    }

    private var accessibilityText: String {
        switch result.chart {
        case .spectrum(let dimensions):
            dimensions.map { "\($0.dominant.name) \($0.percent)%" }.joined(separator: ", ")
        case .radar(let traits), .wheel(let traits, _, _):
            traits.map { "\($0.name) \($0.percent)%" }.joined(separator: ", ")
        case .enneagram(let traits, let type, let wing):
            "\(type) \(traits[type - 1].name), " + L10n("wing \(wing)")
        }
    }

    // MARK: Spectrum

    private func spectrum(_ dimensions: [PersonalityDimension]) -> some View {
        let count = dimensions.count
        let barWidth = WelcomeLightPersonality.Spectrum.halfWidth * 2 * unit
        return ForEach(Array(dimensions.enumerated()), id: \.offset) { row, dimension in
            let y = center.y + WelcomeLightPersonality.Spectrum.rowY(row, count: count) * unit
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                pole(dimension.low, isDominant: !dimension.leansHigh, letterFirst: true)
                Spacer(minLength: 8)
                pole(dimension.high, isDominant: dimension.leansHigh, letterFirst: false)
            }
            .frame(width: barWidth + 24)
            .position(x: center.x, y: y - 0.17 * unit)

            Text(verbatim: "\(dimension.percent)%")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(OnboardingTheme.cyan.opacity(0.9))
                .position(x: center.x + WelcomeLightPersonality.Spectrum.markerX(value: dimension.value) * unit,
                          y: y + 0.15 * unit)
        }
    }

    private func pole(_ pole: PersonalityPole, isDominant: Bool, letterFirst: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if letterFirst { letter(pole, isDominant: isDominant) }
            Text(verbatim: pole.name)
                .font(.caption.weight(isDominant ? .semibold : .regular))
                .foregroundStyle(isDominant ? OnboardingTheme.primaryText : OnboardingTheme.tertiaryText)
            if !letterFirst { letter(pole, isDominant: isDominant) }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    private func letter(_ pole: PersonalityPole, isDominant: Bool) -> some View {
        Text(verbatim: pole.letter)
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .foregroundStyle(isDominant ? OnboardingTheme.cyan : OnboardingTheme.tertiaryText)
    }

    // MARK: Radar

    private func radar(_ traits: [PersonalityTrait]) -> some View {
        let strongest = traits.indices.max { traits[$0].value < traits[$1].value }
        return ForEach(Array(traits.enumerated()), id: \.offset) { index, trait in
            let point = WelcomeLightPersonality.Radar.point(index, count: traits.count, fraction: 1.2)
            let isStrongest = index == strongest
            VStack(spacing: 1) {
                Text(verbatim: trait.short)
                    .font(.system(traits.count > 6 ? .caption : .subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(isStrongest ? OnboardingTheme.cyan : OnboardingTheme.primaryText)
                Text(verbatim: "\(trait.percent)%")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(OnboardingTheme.secondaryText)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: traits.count > 6 ? 74 : 90)
            .position(screen(point))
        }
    }

    // MARK: Enneagram

    private func enneagram(_ traits: [PersonalityTrait], type: Int, wing: Int) -> some View {
        ForEach(1...9, id: \.self) { number in
            let point = WelcomeLightPersonality.Enneagram.point(type: number, fraction: 1.2)
            Text(verbatim: "\(number)")
                .font(.system(number == type ? .title3 : .subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(number == type ? OnboardingTheme.cyan
                                 : (number == wing ? OnboardingTheme.primaryText : OnboardingTheme.tertiaryText))
                .position(screen(point))
        }
    }

    // MARK: Wheel

    private func wheel(_ quarters: [PersonalityTrait]) -> some View {
        let corners = [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)]
        let strongest = quarters.indices.max { quarters[$0].value < quarters[$1].value }
        let total = quarters.map(\.value).reduce(0, +)
        return ForEach(Array(quarters.enumerated()), id: \.offset) { index, quarter in
            let reach = WelcomeLightPersonality.Wheel.radius * 0.86
            let point = CGPoint(x: corners[index].0 * reach,
                                y: corners[index].1 * reach + WelcomeLightPersonality.centerY)
            VStack(spacing: 1) {
                Text(verbatim: quarter.short)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(index == strongest ? Self.wheelColors[index] : OnboardingTheme.primaryText)
                Text(verbatim: "\(Int((quarter.value / max(total, 1e-6) * 100).rounded()))%")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(OnboardingTheme.secondaryText)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 80)
            .position(screen(point))
        }
    }

    /// Mirrors the shader's quarter colours.
    static let wheelColors = [
        Color(red: 1.0, green: 0.36, blue: 0.46), Color(red: 1.0, green: 0.80, blue: 0.30),
        Color(red: 0.36, green: 0.95, blue: 0.56), Color(red: 0.30, green: 0.60, blue: 1.0),
    ]
}
