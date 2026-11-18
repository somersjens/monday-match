import SwiftUI
import UIKit

/// The other person at a glance: their photo with who they are, whether a
/// live scan verified the photo, how far away they live and the match.
struct MatchPhotoCard: Equatable {
    let name: String
    let age: Int?
    /// Without a photo there is no card, and no button to open it.
    let photo: UIImage
    /// The server attested the photo with a live scan. A demo uses your own
    /// verification instead.
    let isVerified: Bool
    let distanceKilometers: Int?
    /// A demo shows your own card: how a match will see you.
    var isOwnPreview = false
}

/// The round photo in the match header, styled like the buttons beside it.
struct MatchPhotoButton: View {
    let card: MatchPhotoCard
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(.white.opacity(0.08))
                Image(uiImage: card.photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 38, height: 38)
                    .clipShape(Circle())
            }
            .frame(width: 44, height: 44)
            .overlay { Circle().strokeBorder(OnboardingTheme.hairline, lineWidth: 0.5) }
            .contentShape(Circle())
        }
        .buttonStyle(PhotoPressStyle())
        .accessibilityLabel(card.isOwnPreview ? L10n("Show your photo card") : L10n("Show \(card.name)’s photo"))
        .accessibilityIdentifier("match.photo")
    }
}

/// The square card that pops out over the heart and the scores.
struct MatchPhotoCardView: View {
    let card: MatchPhotoCard
    let average: Int
    let side: CGFloat
    /// Greys the photo out, for your own photo while it isn't verified yet.
    var dimsPhoto = false
    /// Hides the match bubble, for your own photo until it is verified.
    var showsScore = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsDetails = false

    /// The gap between the colourful border and the photo.
    static let ring: CGFloat = 5
    private var ring: CGFloat { Self.ring }
    private var outerRadius: CGFloat { side * 0.11 }
    private var innerRadius: CGFloat { outerRadius - ring }
    /// Names and numbers grow with the card, from a phone to an iPad.
    static func detailScale(for side: CGFloat) -> CGFloat { min(max(side / 320, 0.82), 1.25) }
    private var scale: CGFloat { Self.detailScale(for: side) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            photo
            LinearGradient(stops: [
                .init(color: .clear, location: 0.42),
                .init(color: .black.opacity(0.35), location: 0.66),
                .init(color: .black.opacity(0.82), location: 1)
            ], startPoint: .top, endPoint: .bottom)
            details
                .padding(.horizontal, 20 * scale)
                .padding(.bottom, 18 * scale)
                .opacity(showsDetails ? 1 : 0)
                .offset(y: showsDetails || reduceMotion ? 0 : 10)
        }
        .overlay(alignment: .topTrailing) {
            if showsScore {
                scoreBadge
                    .padding(14 * scale)
                    .opacity(showsDetails ? 1 : 0)
                    .scaleEffect(showsDetails || reduceMotion ? 1 : 0.7, anchor: .topTrailing)
                    .transition(.scale(scale: 0.7, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.2), value: showsScore)
        .overlay(alignment: .topLeading) {
            if card.isOwnPreview {
                previewTag
                    .padding(14 * scale)
                    .opacity(showsDetails ? 1 : 0)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: innerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
        }
        .padding(ring)
        .background {
            RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                .fill(OnboardingTheme.background)
        }
        .overlay {
            // The light's colours, all the way round.
            RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                .strokeBorder(AngularGradient(colors: [OnboardingTheme.cyan, OnboardingTheme.blue, OnboardingTheme.violet,
                                                       OnboardingTheme.pink, OnboardingTheme.cyan],
                                              center: .center, angle: .degrees(-45)),
                              lineWidth: 2.5)
        }
        .frame(width: side, height: side)
        .shadow(color: OnboardingTheme.blue.opacity(0.55), radius: 26)
        .shadow(color: OnboardingTheme.pink.opacity(0.22), radius: 60)
        .onAppear {
            withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.4).delay(reduceMotion ? 0 : 0.14)) {
                showsDetails = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Pieces

    private var photo: some View {
        Color.clear
            .overlay {
                Image(uiImage: card.photo)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .saturation(dimsPhoto ? 0.1 : 1)
            .opacity(dimsPhoto ? 0.62 : 1)
            .animation(.easeInOut(duration: 0.45), value: dimsPhoto)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            HStack(alignment: .center, spacing: 8 * scale) {
                Text("\(Text(card.name).fontWeight(.semibold))\(Text(card.age.map { ", \($0)" } ?? "").fontWeight(.light))")
                    .font(.system(size: 30 * scale, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if card.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, OnboardingTheme.cyan)
                        .font(.system(size: 21 * scale, weight: .semibold))
                        .shadow(color: OnboardingTheme.cyan.opacity(0.7), radius: 8)
                }
            }
            HStack(spacing: 14 * scale) {
                if let distance = card.distanceKilometers {
                    Label(L10n("\(distance) km away"), systemImage: "location.fill")
                }
                if card.isVerified {
                    Label(L10n("Verified live"), systemImage: "faceid")
                }
            }
            .font(.system(size: 14 * scale, weight: .medium))
            .foregroundStyle(.white.opacity(0.82))
            .labelStyle(CompactLabelStyle())
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .shadow(color: .black.opacity(0.4), radius: 6, y: 1)
    }

    private var scoreBadge: some View {
        VStack(spacing: 1) {
            Text(average, format: .percent)
                .font(.system(size: 21 * scale, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
            Text(L10n("Match"))
                .font(.system(size: 8.5 * scale, weight: .semibold))
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.78))
        }
        .frame(width: 70 * scale, height: 70 * scale)
        .background { Circle().fill(.ultraThinMaterial) }
        .environment(\.colorScheme, .dark)
        .overlay {
            Circle().strokeBorder(OnboardingTheme.accentGradient, lineWidth: 1.5)
        }
        .shadow(color: OnboardingTheme.blue.opacity(0.6), radius: 12)
    }

    private var previewTag: some View {
        Text(L10n("How a match sees you"))
            .font(.system(size: 11 * scale, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background { Capsule().fill(.ultraThinMaterial) }
            .environment(\.colorScheme, .dark)
            .overlay { Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5) }
    }

    private var accessibilityText: String {
        var parts = [card.age.map { L10n("\(card.name), \($0)") } ?? card.name]
        if card.isVerified { parts.append(L10n("Verified live")) }
        if let distance = card.distanceKilometers { parts.append(L10n("\(distance) km away")) }
        if showsScore { parts.append(L10n("\(average) percent match")) }
        return parts.joined(separator: ", ")
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 11, weight: .semibold))
            configuration.title
        }
    }
}

private struct PhotoPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.4), value: configuration.isPressed)
    }
}
