import SwiftUI

/// One column of a cylindrical picker. Rows tilt away from the centre line
/// like a physical wheel and snap to the selection band.
///
/// The selection is derived from the content offset: spacer rows above and
/// below the items mean an offset of `index × rowHeight` centres that item.
struct WheelPicker<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let accessibilityLabel: String
    let label: (Item) -> String
    var isItemEnabled: (Item) -> Bool = { _ in true }
    /// Reports whether the wheel is being touched, flung or settling.
    var onActivityChange: (Bool) -> Void = { _ in }

    @ScaledMetric(relativeTo: .title3) private var rowHeight: CGFloat = 42
    @State private var position = ScrollPosition()
    /// The last value this wheel reported, so it does not scroll itself back.
    @State private var reportedSelection: Item?
    /// Set while scrolling programmatically; rows passed on the way are not
    /// selections.
    @State private var pendingIndex: Int?
    @State private var offsetIndex: Int?
    @FocusState private var isFocused: Bool

    private let visibleRows = 5

    init(
        items: [Item],
        selection: Binding<Item>,
        accessibilityLabel: String,
        label: @escaping (Item) -> String,
        isItemEnabled: @escaping (Item) -> Bool = { _ in true },
        onActivityChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.items = items
        _selection = selection
        self.accessibilityLabel = accessibilityLabel
        self.label = label
        self.isItemEnabled = isItemEnabled
        self.onActivityChange = onActivityChange
        // Offsets reported by the first layout, before the wheel reaches the
        // current selection, must not overwrite it.
        _pendingIndex = State(initialValue: items.firstIndex(of: selection.wrappedValue))
    }

    var body: some View {
        let height = rowHeight * CGFloat(visibleRows)
        let padding = rowHeight * CGFloat(visibleRows / 2)

        ScrollView(.vertical) {
            VStack(spacing: 0) {
                Color.clear.frame(height: padding)
                ForEach(items, id: \.self) { item in
                    row(item, viewportHeight: height)
                }
                Color.clear.frame(height: padding)
            }
        }
        .scrollPosition($position)
        .scrollTargetBehavior(RowSnapping(rowHeight: rowHeight))
        .scrollIndicators(.hidden)
        .frame(height: height)
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.3),
                    .init(color: .black, location: 0.7),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(isFocused ? 0.7 : 0), lineWidth: 2)
                .frame(height: rowHeight + 4)
        }
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) { _, offset in
            let index = index(forOffset: offset)
            offsetIndex = index
            if let pending = pendingIndex {
                if pending == index { pendingIndex = nil }
                return
            }
            let item = items[index]
            guard item != selection else { return }
            reportedSelection = item
            selection = item
        }
        .onScrollPhaseChange { _, phase in
            if phase == .interacting { pendingIndex = nil }
            onActivityChange(phase != .idle)
        }
        .onChange(of: selection) { _, item in
            guard item != reportedSelection else { return }
            scroll(to: item, animated: true)
        }
        .onChange(of: rowHeight) {
            scroll(to: selection, animated: false)
        }
        .onAppear {
            scroll(to: selection, animated: false)
        }
        .sensoryFeedback(.selection, trigger: selection)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { step(-1); return .handled }
        .onKeyPress(.downArrow) { step(1); return .handled }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(label(selection))
        .accessibilityAdjustableAction { direction in
            step(direction == .increment ? 1 : -1)
        }
    }

    private func row(_ item: Item, viewportHeight: CGFloat) -> some View {
        let enabled = isItemEnabled(item)
        return Text(label(item))
            .font(.system(.title3, design: .rounded, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(enabled ? 1 : 0.3))
            .strikethrough(!enabled, color: .white.opacity(0.35))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity)
            .frame(height: rowHeight)
            .contentShape(Rectangle())
            .onTapGesture {
                selection = item
            }
            .visualEffect { content, proxy in
                let midY = proxy.frame(in: .scrollView).midY
                let distance = min(max((midY - viewportHeight / 2) / (viewportHeight / 2), -1.2), 1.2)
                return content
                    .rotation3DEffect(.degrees(Double(-distance) * 50), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
                    .scaleEffect(1 - abs(distance) * 0.12)
                    .opacity(1 - Double(abs(distance)) * 0.72)
            }
    }

    private func index(forOffset offset: CGFloat) -> Int {
        guard rowHeight > 0 else { return 0 }
        return min(max(Int((offset / rowHeight).rounded()), 0), items.count - 1)
    }

    private func scroll(to item: Item, animated: Bool) {
        guard let index = items.firstIndex(of: item) else { return }
        reportedSelection = item
        pendingIndex = index == offsetIndex ? nil : index
        withAnimation(animated ? .snappy(duration: 0.35) : nil) {
            position.scrollTo(y: CGFloat(index) * rowHeight)
        }
    }

    private func step(_ delta: Int) {
        guard let index = items.firstIndex(of: selection) else { return }
        let next = min(max(index + delta, 0), items.count - 1)
        if next != index { selection = items[next] }
    }
}

/// Flings come to rest exactly on a row.
private struct RowSnapping: ScrollTargetBehavior {
    let rowHeight: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard rowHeight > 0 else { return }
        target.rect.origin.y = (target.rect.minY / rowHeight).rounded() * rowHeight
    }
}
