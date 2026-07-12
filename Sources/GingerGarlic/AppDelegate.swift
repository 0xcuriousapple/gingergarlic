import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotkey = Hotkey()
    private let rewriter = Rewriter()
    private var busy = false

    private var lastOriginal: String?
    private var lastRewrite: String?
    private var hotkeyDisplay = ""
    private var corpusCount = 0
    private var savedCount = 0
    private var profileDrafts = 0
    private var lastStatus = ""
    private var recording = UserDefaults.standard.bool(forKey: Rewriter.recordingDefaultsKey)

    private let idleTitle = "🫚"
    private let busyTitle = "🫚…"

    func applicationDidFinishLaunching(_ notification: Notification) {
        SingleInstance.killOthers()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = idleTitle

        let spec = HotkeySpec.load()
        hotkeyDisplay = spec.display
        hotkey.onPress = { [weak self] in self?.handleHotkey() }
        let registered = hotkey.register(spec)

        rebuildMenu(status: startupStatus(hotkeyRegistered: registered))

        if registered {
            LaunchHUD.show("🫚 gingergarlic is running — \(hotkeyDisplay) to rewrite")
        } else {
            LaunchHUD.show("🫚 ⚠️ hotkey \(hotkeyDisplay) is taken by another app — edit hotkey.txt", seconds: 8)
        }

        if !Clipboard.isTrusted {
            Clipboard.promptForTrust()
        }
        rewriter.prewarm()
        refreshCorpusCount()
    }

    private func refreshCorpusCount() {
        Task { @MainActor in
            corpusCount = await rewriter.corpus.acceptedCount()
            savedCount = await rewriter.corpus.persistedCount()
            profileDrafts = await rewriter.profile.draftCount()
            rebuildMenu(status: lastStatus)
        }
    }

    private func startupStatus(hotkeyRegistered: Bool = true) -> String {
        if !hotkeyRegistered {
            return "⚠️ \(hotkeyDisplay) is taken — edit hotkey.txt + relaunch"
        }
        if let issue = Rewriter.availabilityIssue() {
            return "⚠️ \(issue)"
        }
        return "ready — select text, press \(hotkeyDisplay)"
    }

    private func rebuildMenu(status: String) {
        lastStatus = status
        let menu = NSMenu()

        let statusLine = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)

        var learning = "style profile: \(profileDrafts) drafts · session examples: \(corpusCount)"
        if Rewriter.usingAdapter { learning += " · LoRA ✓" }
        let learningLine = NSMenuItem(title: learning, action: nil, keyEquivalent: "")
        learningLine.isEnabled = false
        menu.addItem(learningLine)
        menu.addItem(.separator())

        let record = NSMenuItem(
            title: "save history for LoRA training",
            action: #selector(toggleRecording), keyEquivalent: ""
        )
        record.state = recording ? .on : .off
        menu.addItem(record)
        if recording || savedCount > 0 {
            menu.addItem(withTitle: "wipe recorded history (\(savedCount) pairs)…",
                         action: #selector(wipeHistory), keyEquivalent: "")
        }
        menu.addItem(.separator())

        if lastOriginal != nil {
            menu.addItem(withTitle: "copy original (undo)", action: #selector(copyOriginal), keyEquivalent: "")
        }
        if lastRewrite != nil {
            menu.addItem(withTitle: "copy last rewrite", action: #selector(copyRewrite), keyEquivalent: "")
        }
        menu.addItem(withTitle: "edit style prompt", action: #selector(editStyle), keyEquivalent: "")
        menu.addItem(withTitle: "change hotkey (relaunch after)", action: #selector(editHotkey), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "quit gingergarlic", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem.menu = menu
    }

    // MARK: - Hotkey flow

    private func handleHotkey() {
        guard !busy else { return }
        guard Clipboard.isTrusted else {
            Clipboard.promptForTrust()
            rebuildMenu(status: "⚠️ grant Accessibility permission, then retry")
            return
        }

        busy = true
        statusItem.button?.title = busyTitle

        Task { @MainActor in
            defer {
                busy = false
                statusItem.button?.title = idleTitle
            }

            let clipboardBefore = Clipboard.currentString()

            // Let the user release ⌃⌥ so held modifiers don't mix into the ⌘C.
            try? await Task.sleep(nanoseconds: 150_000_000)

            guard let selection = await Clipboard.captureSelection(),
                  !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                NSSound.beep()
                rebuildMenu(status: "nothing selected — ⌘A first, then \(hotkeyDisplay)")
                return
            }

            do {
                let rewritten = try await rewriter.rewrite(selection)
                lastOriginal = selection
                lastRewrite = rewritten
                await Clipboard.paste(rewritten)

                // Give the target app a beat to consume the paste,
                // then hand the user their clipboard back.
                try? await Task.sleep(nanoseconds: 600_000_000)
                if let clipboardBefore {
                    Clipboard.set(clipboardBefore)
                }
                rebuildMenu(status: "ready — select text, press \(hotkeyDisplay)")
            } catch {
                NSSound.beep()
                rebuildMenu(status: "⚠️ \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Menu actions

    @objc private func copyOriginal() {
        guard let lastOriginal else { return }
        Clipboard.set(lastOriginal)
        // Undo is the rejection signal: keep that pair out of the few-shot
        // pool and flag it for future adapter training.
        Task { @MainActor in
            await rewriter.corpus.markLastRejected()
            refreshCorpusCount()
        }
    }

    @objc private func copyRewrite() {
        if let lastRewrite { Clipboard.set(lastRewrite) }
    }

    @objc private func editStyle() {
        _ = Style.load() // ensure the file exists
        NSWorkspace.shared.open(Style.fileURL)
    }

    @objc private func editHotkey() {
        _ = HotkeySpec.load() // ensure the file exists
        NSWorkspace.shared.open(HotkeySpec.configURL)
    }

    @objc private func toggleRecording() {
        recording.toggle()
        UserDefaults.standard.set(recording, forKey: Rewriter.recordingDefaultsKey)
        Task { @MainActor in
            await rewriter.corpus.setPersist(recording)
            refreshCorpusCount()
        }
    }

    @objc private func wipeHistory() {
        let alert = NSAlert()
        alert.messageText = "wipe recorded history?"
        alert.informativeText = "deletes corpus.jsonl and everything learned this session. the aggregate style profile (no message content) is kept."
        alert.addButton(withTitle: "wipe")
        alert.addButton(withTitle: "cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { @MainActor in
            await rewriter.corpus.wipe()
            refreshCorpusCount()
        }
    }
}
