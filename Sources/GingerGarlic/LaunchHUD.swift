import AppKit

/// Small floating pill under the menu bar that confirms the app is running,
/// then fades out. Menu bar icons are easy to miss (or hidden by the notch).
enum LaunchHUD {
    private static var panel: NSPanel?

    static func show(_ message: String, seconds: TimeInterval = 4) {
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.sizeToFit()

        let padding: CGFloat = 18
        let size = NSSize(width: label.frame.width + padding * 2, height: label.frame.height + padding)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]

        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        content.layer?.cornerRadius = size.height / 2
        label.frame.origin = NSPoint(x: padding, y: padding / 2)
        content.addSubview(label)
        panel.contentView = content

        if let screen = NSScreen.main {
            let x = screen.visibleFrame.midX - size.width / 2
            let y = screen.visibleFrame.maxY - size.height - 8
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFrontRegardless()
        self.panel = panel

        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.5
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
                if self.panel === panel { self.panel = nil }
            })
        }
    }
}

enum SingleInstance {
    /// Terminates any other running gingergarlic processes so relaunching
    /// always replaces the previous instance.
    static func killOthers() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", "gingergarlic"]
        let pipe = Pipe()
        task.standardOutput = pipe
        guard (try? task.run()) != nil else { return }
        task.waitUntilExit()
        let output = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let myPid = getpid()
        for line in output.split(separator: "\n") {
            if let pid = Int32(line.trimmingCharacters(in: .whitespaces)), pid != myPid {
                kill(pid, SIGTERM)
            }
        }
    }
}
