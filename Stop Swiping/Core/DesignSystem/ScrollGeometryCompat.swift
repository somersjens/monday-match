import SwiftUI

/// The parts of `ScrollGeometry` the app reads, as a type that exists on
/// every supported iOS version.
struct ScrollMetrics {
    var contentOffset: CGPoint
    var contentSize: CGSize
    var containerSize: CGSize
    var visibleRect: CGRect
}

extension View {
    /// `onScrollGeometryChange` on iOS 18 and later. iOS 17 has no way to
    /// observe scroll geometry from outside the scroll view, so there the
    /// action reports `fallback` once when the view appears.
    @ViewBuilder
    func onScrollMetricsChange<Value: Equatable>(
        for type: Value.Type,
        fallback: Value,
        of transform: @escaping (ScrollMetrics) -> Value,
        action: @escaping (Value) -> Void
    ) -> some View {
        if #available(iOS 18, *) {
            onScrollGeometryChange(for: type) { geometry in
                transform(ScrollMetrics(contentOffset: geometry.contentOffset,
                                        contentSize: geometry.contentSize,
                                        containerSize: geometry.containerSize,
                                        visibleRect: geometry.visibleRect))
            } action: { _, value in
                action(value)
            }
        } else {
            onAppear { action(fallback) }
        }
    }
}
