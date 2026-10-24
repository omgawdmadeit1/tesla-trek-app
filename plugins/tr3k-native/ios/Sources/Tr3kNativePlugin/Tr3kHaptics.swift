import UIKit

enum Tr3kHaptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notification = UINotificationFeedbackGenerator()
    private static let selection = UISelectionFeedbackGenerator()

    /// Returns false for an unknown kind. Call on the main thread.
    static func play(_ kind: String) -> Bool {
        switch kind {
        case "light":
            light.prepare()
            light.impactOccurred()
        case "medium":
            medium.prepare()
            medium.impactOccurred()
        case "heavy":
            heavy.prepare()
            heavy.impactOccurred()
        case "soft":
            soft.prepare()
            soft.impactOccurred()
        case "rigid":
            rigid.prepare()
            rigid.impactOccurred()
        case "success":
            notification.prepare()
            notification.notificationOccurred(.success)
        case "warning":
            notification.prepare()
            notification.notificationOccurred(.warning)
        case "error":
            notification.prepare()
            notification.notificationOccurred(.error)
        case "selection":
            selection.prepare()
            selection.selectionChanged()
        default:
            return false
        }
        return true
    }
}
