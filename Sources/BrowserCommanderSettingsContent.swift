import SwiftUI

struct BrowserCommanderSettingsContent: View {
    let delegate: AppDelegate

    var body: some View {
        Section("Behaviour") {
            Toggle("Enable browser key remapping", isOn: Binding(
                get: { delegate.engine.isEnabled },
                set: { delegate.engine.isEnabled = $0 }
            ))
        }

        Section("Shortcuts") {
            JorvikShortcutRecorder(
                label: "Go Back",
                keyCode: Binding(
                    get: { delegate.goBackKeyCode },
                    set: { delegate.goBackKeyCode = $0 }
                ),
                modifiers: Binding(
                    get: { delegate.goBackModifiers },
                    set: { delegate.goBackModifiers = $0 }
                ),
                displayString: { delegate.goBackShortcutDisplayString() },
                onChanged: nil,
                eventTapToDisable: nil
            )
            JorvikShortcutRecorder(
                label: "Go Forward",
                keyCode: Binding(
                    get: { delegate.goForwardKeyCode },
                    set: { delegate.goForwardKeyCode = $0 }
                ),
                modifiers: Binding(
                    get: { delegate.goForwardModifiers },
                    set: { delegate.goForwardModifiers = $0 }
                ),
                displayString: { delegate.goForwardShortcutDisplayString() },
                onChanged: nil,
                eventTapToDisable: nil
            )
            JorvikShortcutRecorder(
                label: "Link Navigator",
                keyCode: Binding(
                    get: { delegate.linkHUDKeyCode },
                    set: { delegate.linkHUDKeyCode = $0 }
                ),
                modifiers: Binding(
                    get: { delegate.linkHUDModifiers },
                    set: { delegate.linkHUDModifiers = $0 }
                ),
                displayString: { delegate.linkHUDShortcutDisplayString() },
                onChanged: nil,
                eventTapToDisable: nil
            )
        }

        Section("Permissions") {
            HStack {
                Text("Accessibility")
                Spacer()
                if AXIsProcessTrusted() {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else {
                    Button("Grant Access") {
                        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
                        AXIsProcessTrustedWithOptions(opts)
                    }
                    .font(.caption)
                }
            }
        }

        MenuBarPillSettings {
            delegate.refreshPill()
        }
    }
}
