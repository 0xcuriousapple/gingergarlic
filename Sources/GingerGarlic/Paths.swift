import Foundation

/// Base directory for gingergarlic's config/data files (style.md, profile.json,
/// corpus.jsonl, adapter.fmadapter).
///
/// - macOS: `~/.config/gingergarlic` — a normal dotfolder.
/// - iOS: the keyboard extension and the container app are separate sandboxes,
///   so they share one App Group container. Set the same group id on both
///   targets' entitlements (see ios/SETUP.md).
enum AppPaths {
    static let appGroupID = "group.xyz.curiousapple.gingergarlic"

    static let base: URL = {
        let fm = FileManager.default
        #if os(macOS)
        let dir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".config/gingergarlic")
        #else
        let dir: URL
        if let container = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            dir = container.appendingPathComponent("gingergarlic")
        } else {
            // No App Group configured: fall back to the local sandbox. The
            // keyboard still works standalone; it just can't share the style
            // profile with the container app.
            dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("gingergarlic")
        }
        #endif
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func file(_ name: String) -> URL {
        base.appendingPathComponent(name)
    }
}
