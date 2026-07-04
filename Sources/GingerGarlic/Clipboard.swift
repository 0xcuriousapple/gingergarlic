import AppKit

enum Clipboard {
    private static let keyC: CGKeyCode = 8
    private static let keyV: CGKeyCode = 9

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func promptForTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Copies the current selection in the frontmost app by synthesizing ⌘C,
    /// then waits for the pasteboard to change. Returns nil if nothing was copied.
    static func captureSelection() async -> String? {
        let pb = NSPasteboard.general
        let before = pb.changeCount
        postKeystroke(keyC, flags: .maskCommand)
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 25_000_000)
            if pb.changeCount != before {
                return pb.string(forType: .string)
            }
        }
        return nil
    }

    /// Puts text on the pasteboard and synthesizes ⌘V into the frontmost app.
    static func paste(_ text: String) async {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        try? await Task.sleep(nanoseconds: 50_000_000)
        postKeystroke(keyV, flags: .maskCommand)
    }

    static func set(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func currentString() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    private static func postKeystroke(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
