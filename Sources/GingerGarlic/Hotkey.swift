import Carbon.HIToolbox
import Foundation

struct HotkeySpec {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let display: String

    static let configURL: URL = AppPaths.file("hotkey.txt")

    static let defaultSpec = "ctrl+opt+cmd+g"

    private static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37,
        "j": 38, "k": 40, "n": 45, "m": 46,
        "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26,
        "8": 28, "9": 25, "0": 29,
    ]

    /// Reads e.g. "ctrl+opt+cmd+g" from the config file, writing the default on first run.
    static func load() -> HotkeySpec {
        let text = (try? String(contentsOf: configURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if text.isEmpty {
            try? FileManager.default.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? defaultSpec.write(to: configURL, atomically: true, encoding: .utf8)
        }
        return parse(text.isEmpty ? defaultSpec : text) ?? parse(defaultSpec)!
    }

    static func parse(_ spec: String) -> HotkeySpec? {
        var modifiers: UInt32 = 0
        var display = ""
        var key: (name: String, code: UInt32)?

        for token in spec.lowercased().split(separator: "+").map(String.init) {
            switch token {
            case "ctrl", "control":
                modifiers |= UInt32(controlKey); display += "⌃"
            case "opt", "option", "alt":
                modifiers |= UInt32(optionKey); display += "⌥"
            case "shift":
                modifiers |= UInt32(shiftKey); display += "⇧"
            case "cmd", "command":
                modifiers |= UInt32(cmdKey); display += "⌘"
            default:
                guard let code = keyCodes[token] else { return nil }
                key = (token, code)
            }
        }
        guard let key, modifiers != 0 else { return nil }
        return HotkeySpec(
            keyCode: key.code,
            carbonModifiers: modifiers,
            display: display + key.name.uppercased()
        )
    }
}

/// Global hotkey via Carbon's RegisterEventHotKey — no Accessibility permission
/// needed for listening (only the synthetic keystrokes elsewhere need it).
final class Hotkey {
    var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Returns false if the system rejected the hotkey (e.g. taken by another app).
    @discardableResult
    func register(_ spec: HotkeySpec) -> Bool {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                let hotkey = Unmanaged<Hotkey>.fromOpaque(userData!).takeUnretainedValue()
                DispatchQueue.main.async { hotkey.onPress?() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        let hotKeyID = EventHotKeyID(signature: OSType(0x4747_4747), id: 1) // 'GGGG'
        let status = RegisterEventHotKey(
            spec.keyCode,
            spec.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        return status == noErr
    }
}
