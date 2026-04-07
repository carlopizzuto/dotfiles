// Sources/BWMenuBar/Clipboard.swift
import AppKit

enum Clipboard {
    private static let clearDelay: TimeInterval = 30

    /// Copy text to the system clipboard and schedule auto-clear.
    static func copyAndClear(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        let changeCount = pb.changeCount

        DispatchQueue.main.asyncAfter(deadline: .now() + clearDelay) {
            // Only clear if clipboard hasn't been changed by the user since our copy
            if pb.changeCount == changeCount {
                pb.clearContents()
            }
        }
    }
}
