# gingergarlic on iOS (keyboard extension)

The iOS version is a **companion keyboard**: you keep typing with your normal
keyboard, switch to gingergarlic (🌐), tap **✨ fix**, and your text is
rewritten in place by the same on-device model and logic as the Mac app.

This folder has all the source. What it can't contain is the Xcode project
itself (targets, signing, capabilities) — you assemble that once, below. None
of this is buildable from the command line; it needs Xcode + your iPhone.

## prerequisites

- **iPhone 15 Pro or newer** (A17 Pro+) with **Apple Intelligence enabled**
  (Settings → Apple Intelligence & Siri). This is non-negotiable — the model
  doesn't exist on older devices.
- **Xcode 26** (iOS 26 SDK, which has the FoundationModels framework).
- An Apple ID for signing. A free personal team works for installing on your
  own device (re-sign every 7 days); a paid account avoids that.

## the source layout

```
Sources/GingerGarlic/          <- shared core (also used by the Mac app)
    Rewriter.swift  SpellFix.swift  Style.swift
    StyleProfile.swift  Corpus.swift  Paths.swift        <- add these to BOTH iOS targets
    AppDelegate/Clipboard/Hotkey/LaunchHUD/main.swift    <- macOS only, do NOT add
ios/GingerGarlicApp/           <- container app (SwiftUI)
ios/GingerGarlicKeyboard/      <- keyboard extension
```

The six core files are the same ones the Mac builds. They use
`#if os(macOS)` / `canImport(UIKit)` so they compile cleanly for iOS —
`SpellFix` uses `UITextChecker` there, `Paths` uses the App Group container.

## assemble the Xcode project (once)

1. **New project** → iOS → App. Name `GingerGarlicApp`, bundle id
   `xyz.curiousapple.gingergarlic`, interface SwiftUI, language Swift.
   Set the deployment target to **iOS 26.0**.
2. Delete the generated `ContentView.swift`; add `ios/GingerGarlicApp/GingerGarlicApp.swift`.
3. **Add target** → iOS → Custom Keyboard Extension. Name
   `GingerGarlicKeyboard`, bundle id `xyz.curiousapple.gingergarlic.keyboard`.
   Delete its generated `KeyboardViewController.swift`; add ours from
   `ios/GingerGarlicKeyboard/`, and replace the generated `Info.plist` with
   ours (or just set `RequestsOpenAccess = YES` and confirm the principal
   class is `$(PRODUCT_MODULE_NAME).KeyboardViewController`).
4. **Add the six core files to both targets.** Select the files in the
   navigator → File Inspector → Target Membership → check both
   `GingerGarlicApp` and `GingerGarlicKeyboard`. (Add the files by reference
   from `Sources/GingerGarlic/` so the Mac and iOS builds stay in sync.)
5. **App Group.** For each target: Signing & Capabilities → + Capability →
   App Groups → add `group.xyz.curiousapple.gingergarlic`. Use the provided
   `.entitlements` files or let Xcode generate them. This is how the keyboard
   and app share your style prompt + profile.
6. **Signing.** Set your team on both targets. If you change the bundle ids or
   group id, update `AppPaths.appGroupID` in `Paths.swift` and both
   entitlements to match.
7. Select the app scheme, pick your iPhone, **Run**.

## enable it on the phone

1. Settings → General → Keyboard → Keyboards → Add New Keyboard → gingergarlic.
2. Tap gingergarlic in that list → enable **Allow Full Access**. Required —
   without it the extension can't reach the on-device model or the shared
   style file.
3. In any app (Notes is the easiest first test), type a sentence, hold 🌐,
   switch to gingergarlic, tap **✨ fix**.

## verify (the two things I couldn't test from a Mac)

- **memory.** Keyboard extensions have a tight budget and this is the real
  risk. FoundationModels runs the LLM in a *system* process, so the model
  shouldn't count against the keyboard — but confirm: run the keyboard target
  with the Xcode Memory gauge open and fix a few messages. If the keyboard
  silently reloads/disappears mid-rewrite, it's being jetsammed. Mitigations
  already in place: `useRetrieval = false` keeps the NLEmbedding model out of
  the extension. If it still spikes, move rewriting into the container app via
  a share extension (heavier budget) as a fallback.
- **latency.** Should mirror the Mac (~1s). First fix after enabling the
  keyboard pays a one-time model warm-up.

## known limitations of the companion-keyboard MVP

- **switching keyboards** each time is clunky. The polish step is a full
  QWERTY keyboard with the fix key built in (what Grammarly's keyboard does) —
  much more work, deferred until the core UX is proven on-device.
- **grabbing the full text** relies on `documentContextBeforeInput`, which a
  few apps truncate to the current paragraph. Fine for typical chat messages;
  long multi-paragraph drafts may only partially capture.
