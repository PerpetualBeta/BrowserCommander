import AppKit
import ApplicationServices
import SwiftUI
import ServiceManagement
import Sparkle

@MainActor
@Observable
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    let engine = BrowserCommanderEngine()

    // @ObservationIgnored because @Observable's macro transforms stored
    // properties into computed properties with init accessors, which is
    // incompatible with `lazy`. These aren't observable state anyway —
    // Sparkle drives its own UI, no SwiftUI needs to react to changes.
    @ObservationIgnored let sparkleUserDriverDelegate = BrowserCommanderUserDriverDelegate()
    @ObservationIgnored lazy var sparkleUpdater = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: sparkleUserDriverDelegate
    )

    var linkHUDKeyCode: UInt16 = {
        let val = UserDefaults.standard.object(forKey: "linkHUDKeyCode")
        return val != nil ? UInt16(UserDefaults.standard.integer(forKey: "linkHUDKeyCode")) : 37
    }() {
        didSet {
            UserDefaults.standard.set(Int(linkHUDKeyCode), forKey: "linkHUDKeyCode")
            engine.updateLinkHUDHotkey(keyCode: linkHUDKeyCode, modifiers: linkHUDModifiers)
        }
    }

    var linkHUDModifiers: NSEvent.ModifierFlags = {
        let val = UserDefaults.standard.object(forKey: "linkHUDModifiers")
        if let raw = val as? UInt { return NSEvent.ModifierFlags(rawValue: raw) }
        return [.command, .control, .option, .shift]
    }() {
        didSet {
            UserDefaults.standard.set(linkHUDModifiers.rawValue, forKey: "linkHUDModifiers")
            engine.updateLinkHUDHotkey(keyCode: linkHUDKeyCode, modifiers: linkHUDModifiers)
        }
    }

    var goBackKeyCode: UInt16 = {
        let val = UserDefaults.standard.object(forKey: "goBackKeyCode")
        return val != nil ? UInt16(UserDefaults.standard.integer(forKey: "goBackKeyCode")) : 51  // Backspace
    }() {
        didSet {
            UserDefaults.standard.set(Int(goBackKeyCode), forKey: "goBackKeyCode")
            engine.updateGoBackHotkey(keyCode: goBackKeyCode, modifiers: goBackModifiers)
        }
    }

    var goBackModifiers: NSEvent.ModifierFlags = {
        let val = UserDefaults.standard.object(forKey: "goBackModifiers")
        if let raw = val as? UInt { return NSEvent.ModifierFlags(rawValue: raw) }
        return []
    }() {
        didSet {
            UserDefaults.standard.set(goBackModifiers.rawValue, forKey: "goBackModifiers")
            engine.updateGoBackHotkey(keyCode: goBackKeyCode, modifiers: goBackModifiers)
        }
    }

    var goForwardKeyCode: UInt16 = {
        let val = UserDefaults.standard.object(forKey: "goForwardKeyCode")
        return val != nil ? UInt16(UserDefaults.standard.integer(forKey: "goForwardKeyCode")) : 51  // Backspace
    }() {
        didSet {
            UserDefaults.standard.set(Int(goForwardKeyCode), forKey: "goForwardKeyCode")
            engine.updateGoForwardHotkey(keyCode: goForwardKeyCode, modifiers: goForwardModifiers)
        }
    }

    var goForwardModifiers: NSEvent.ModifierFlags = {
        let val = UserDefaults.standard.object(forKey: "goForwardModifiers")
        if let raw = val as? UInt { return NSEvent.ModifierFlags(rawValue: raw) }
        return [.shift]
    }() {
        didSet {
            UserDefaults.standard.set(goForwardModifiers.rawValue, forKey: "goForwardModifiers")
            engine.updateGoForwardHotkey(keyCode: goForwardKeyCode, modifiers: goForwardModifiers)
        }
    }

    func goBackShortcutDisplayString() -> String {
        JorvikShortcutPanel.displayString(keyCode: goBackKeyCode, modifiers: goBackModifiers)
    }

    func goForwardShortcutDisplayString() -> String {
        JorvikShortcutPanel.displayString(keyCode: goForwardKeyCode, modifiers: goForwardModifiers)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateLegacyPillColorKey()

        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()
        _ = sparkleUpdater  // forces lazy init so Sparkle starts at launch

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        engine.start()

        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                self.updateIcon()
                if self.engine.isActive { timer.invalidate() }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { engine.stop() }

    // One-shot removal of the user-chosen pill colour key from the old design.
    // The new pill uses fixed grey/light colours; the key is dead weight.
    private func migrateLegacyPillColorKey() {
        let migrated = "didMigratePillColorV2"
        if UserDefaults.standard.bool(forKey: migrated) { return }
        UserDefaults.standard.removeObject(forKey: "menuBarPillColor")
        UserDefaults.standard.set(true, forKey: migrated)
    }

    func refreshPill() { updateIcon() }

    private func updateIcon() {
        let symbolName = engine.isActive
            ? (engine.isEnabled ? "globe.badge.chevron.backward" : "globe")
            : "globe"
        statusItem.button?.image = JorvikMenuBarPill.icon(
            symbolName: symbolName,
            accessibilityDescription: "Browser Commander"
        )
    }

    func linkHUDShortcutDisplayString() -> String {
        JorvikShortcutPanel.displayString(keyCode: linkHUDKeyCode, modifiers: linkHUDModifiers)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateIcon()
        var actions: [JorvikMenuBuilder.ActionItem] = []
        actions.append(JorvikMenuBuilder.ActionItem(
            title: engine.isEnabled ? "Disable" : "Enable",
            action: #selector(toggleEnabled), target: self, keyEquivalent: ""
        ))
        actions.append(JorvikMenuBuilder.ActionItem(
            title: "Check for Updates\u{2026}",
            action: #selector(checkForUpdates(_:)), target: self
        ))

        let built = JorvikMenuBuilder.buildMenu(
            appName: "Browser Commander",
            aboutAction: #selector(openAbout), settingsAction: #selector(openSettings),
            target: self, actions: actions
        )
        menu.removeAllItems()
        for item in built.items { built.removeItem(item); menu.addItem(item) }
    }

    @objc private func toggleEnabled() { engine.isEnabled.toggle(); updateIcon() }
    @objc func checkForUpdates(_ sender: Any?) {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        sparkleUpdater.checkForUpdates(sender)
    }
    @objc private func noop() {}

    @objc private func openAbout() {
        JorvikAboutView.showWindow(appName: "Browser Commander", repoName: "BrowserCommander", productPage: "utilities/browsercommander")
    }

    @objc private func openSettings() {
        let delegate = self
        JorvikSettingsView.showWindow(appName: "Browser Commander") {
            BrowserCommanderSettingsContent(delegate: delegate)
        }
    }
}

/// Keeps Sparkle's update UI visible across the whole session, including
/// when the user switches to another app mid-download. See KB:
/// `conventions/sparkle-integration.md` §6 for the rationale.
final class BrowserCommanderUserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    private var sessionObserver: NSObjectProtocol?
    private var elevatedWindows: [(window: NSWindow, originalLevel: NSWindow.Level)] = []

    func standardUserDriverWillShowModalAlert() {
        bringForward()
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        startFocusGuard()
        bringForward()
    }

    func standardUserDriverWillFinishUpdateSession() {
        stopFocusGuard()
    }

    private func bringForward() {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        elevateAllWindows()
    }

    private func startFocusGuard() {
        guard sessionObserver == nil else { return }
        sessionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.bringForward()
        }
    }

    private func stopFocusGuard() {
        if let obs = sessionObserver {
            NotificationCenter.default.removeObserver(obs)
            sessionObserver = nil
        }
        for entry in elevatedWindows {
            entry.window.level = entry.originalLevel
        }
        elevatedWindows.removeAll()
    }

    private func elevateAllWindows() {
        for window in NSApp.windows where window.isVisible && window.level == .normal {
            elevatedWindows.append((window, window.level))
            window.level = .floating
        }
    }
}
