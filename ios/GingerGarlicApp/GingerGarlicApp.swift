import SwiftUI

/// Container app. iOS requires a keyboard extension to ship inside a host app;
/// this one exists to (1) get the user through enabling the keyboard + Full
/// Access, (2) let them edit their style prompt, which is shared with the
/// keyboard via the App Group container.
@main
struct GingerGarlicApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var styleText = ""
    @State private var modelIssue: String? = Rewriter.availabilityIssue()

    var body: some View {
        NavigationStack {
            Form {
                Section("setup") {
                    stepRow(1, "add the keyboard", "Settings → General → Keyboard → Keyboards → Add New Keyboard → gingergarlic")
                    stepRow(2, "allow full access", "tap gingergarlic in that list → enable Allow Full Access (needed for the on-device model)")
                    stepRow(3, "use it anywhere", "in any app, hold 🌐 to switch to gingergarlic, tap ✨ fix")
                }

                if let issue = modelIssue {
                    Section {
                        Label("apple intelligence not ready: \(issue)", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }

                Section("your style prompt") {
                    TextEditor(text: $styleText)
                        .frame(minHeight: 240)
                        .font(.system(.footnote, design: .monospaced))
                    Text("shared with the keyboard. the biggest lever is the draft:/rewrite: examples — make them real messages of yours.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("gingergarlic 🫚")
            .onAppear { styleText = Style.load() }
            .onDisappear { try? styleText.write(to: Style.fileURL, atomically: true, encoding: .utf8) }
        }
    }

    private func stepRow(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.headline).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
