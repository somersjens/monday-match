import Foundation

/// Debug builds only, and only when launched with `FACE_SCAN_LOG=1`: one line
/// per analysed camera frame. Numbers only; no images, landmarks or embeddings.
/// On a phone: `xcrun devicectl device process launch --console
/// --environment-variables '{"FACE_SCAN_LOG": "1"}' --device <id> Hakketjak.monday-match`.
nonisolated enum FaceScanLog {
    #if DEBUG
    private static let enabled = ProcessInfo.processInfo.environment["FACE_SCAN_LOG"] == "1"
    #endif

    static func line(_ text: @autoclosure () -> String) {
        #if DEBUG
        guard enabled else { return }
        print("[scan] " + text())
        #endif
    }

    static func number(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "-" }
        return String(format: "%.2f", value)
    }

    static func number(_ value: Float?) -> String {
        number(value.map(Double.init))
    }
}
