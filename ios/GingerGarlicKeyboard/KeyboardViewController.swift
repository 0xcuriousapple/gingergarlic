import UIKit

/// gingergarlic keyboard extension.
///
/// This is a lightweight "companion" keyboard: it does NOT reimplement QWERTY.
/// You type with your normal keyboard, switch to gingergarlic (globe key), tap
/// "fix", and it rewrites what's in the text field in place. Switching back is
/// one tap. (A full QWERTY-with-fix-key keyboard à la Grammarly is the polish
/// step — see ios/SETUP.md.)
///
/// The portable core (Rewriter, SpellFix, Style, StyleProfile, Corpus, Paths)
/// is compiled into this target, so the rewrite logic is identical to the Mac.
final class KeyboardViewController: UIInputViewController {
    private let rewriter: Rewriter = {
        let r = Rewriter()
        // Keyboard extensions get a tight memory budget; skip NLEmbedding
        // retrieval and lean on the base prompt + aggregate style profile.
        r.useRetrieval = false
        return r
    }()

    private var fixButton: UIButton!
    private var globeButton: UIButton!
    private var statusLabel: UILabel!
    private var busy = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.heightAnchor.constraint(equalToConstant: 216).isActive = true
        buildUI()
        showModelStatus()
    }

    // MARK: - UI

    private func buildUI() {
        view.backgroundColor = UIColor.secondarySystemBackground

        fixButton = UIButton(type: .system)
        fixButton.setTitle("✨ fix my text", for: .normal)
        fixButton.titleLabel?.font = .systemFont(ofSize: 20, weight: .semibold)
        fixButton.backgroundColor = UIColor.systemBlue
        fixButton.setTitleColor(.white, for: .normal)
        fixButton.layer.cornerRadius = 14
        fixButton.addTarget(self, action: #selector(fixTapped), for: .touchUpInside)

        statusLabel = UILabel()
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.text = "type your message, then tap fix"

        globeButton = UIButton(type: .system)
        globeButton.setTitle("🌐 keyboard", for: .normal)
        globeButton.titleLabel?.font = .systemFont(ofSize: 15)
        globeButton.setTitleColor(.label, for: .normal)
        // handleInputModeList presents the keyboard switcher for free.
        globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)

        let stack = UIStackView(arrangedSubviews: [fixButton, statusLabel, globeButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            fixButton.heightAnchor.constraint(equalToConstant: 56),
            globeButton.heightAnchor.constraint(equalToConstant: 40),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
        ])
    }

    private func showModelStatus() {
        if let issue = Rewriter.availabilityIssue() {
            setEnabled(false)
            statusLabel.text = "⚠️ \(issue)\nenable apple intelligence in settings"
        }
    }

    private func setEnabled(_ enabled: Bool) {
        fixButton.isEnabled = enabled
        fixButton.alpha = enabled ? 1 : 0.4
    }

    private func setBusy(_ value: Bool) {
        busy = value
        setEnabled(!value)
        fixButton.setTitle(value ? "✨ fixing…" : "✨ fix my text", for: .normal)
    }

    // MARK: - Fix flow

    @objc private func fixTapped() {
        guard !busy else { return }
        let proxy = textDocumentProxy
        let before = proxy.documentContextBeforeInput ?? ""
        let after = proxy.documentContextAfterInput ?? ""
        let full = before + after

        guard full.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace).count >= 1 else {
            statusLabel.text = "nothing to fix — type something first"
            return
        }

        setBusy(true)
        statusLabel.text = "rewriting on-device…"

        Task {
            do {
                let rewritten = try await rewriter.rewrite(full)
                await MainActor.run {
                    self.replaceAll(before: before, after: after, with: rewritten)
                    self.statusLabel.text = "done ✓"
                }
            } catch {
                await MainActor.run { self.statusLabel.text = "⚠️ \(error.localizedDescription)" }
            }
            await MainActor.run { self.setBusy(false) }
        }
    }

    /// Replace the entire field contents with `new`. Moves the cursor to the
    /// end, deletes everything, then inserts the rewrite.
    private func replaceAll(before: String, after: String, with new: String) {
        let proxy = textDocumentProxy
        if !after.isEmpty {
            proxy.adjustTextPosition(byCharacterOffset: after.count)
        }
        for _ in 0..<(before.count + after.count) {
            proxy.deleteBackward()
        }
        proxy.insertText(new)
    }
}
