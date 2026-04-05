import AppKit
import ApplicationServices
import SwiftUI
import ServiceManagement

@MainActor
@Observable
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    let engine = BrowserCommanderEngine()
    let updateChecker = JorvikUpdateChecker(repoName: "BrowserCommander")

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
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()
        JorvikMenuBarPill.apply(to: statusItem.button!)
        updateChecker.checkOnSchedule()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        DistributedNotificationCenter.default.addObserver(
            self, selector: #selector(appearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil
        )

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

    @objc private func appearanceChanged() {
        if let button = statusItem.button { JorvikMenuBarPill.refresh(on: button) }
    }

    func refreshPill() {
        if let button = statusItem.button { JorvikMenuBarPill.apply(to: button) }
    }

    private func updateIcon() {
        let symbolName = engine.isActive
            ? (engine.isEnabled ? "globe.badge.chevron.backward" : "globe")
            : "globe"
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Browser Commander") {
            image.isTemplate = true
            statusItem.button?.image = image
        }
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

        let built = JorvikMenuBuilder.buildMenu(
            appName: "Browser Commander",
            aboutAction: #selector(openAbout), settingsAction: #selector(openSettings),
            target: self, actions: actions
        )
        menu.removeAllItems()
        for item in built.items { built.removeItem(item); menu.addItem(item) }
    }

    @objc private func toggleEnabled() { engine.isEnabled.toggle(); updateIcon() }
    @objc private func noop() {}

    @objc private func openAbout() {
        JorvikAboutView.showWindow(appName: "Browser Commander", repoName: "BrowserCommander", productPage: "utilities/browsercommander")
    }

    @objc private func openSettings() {
        let delegate = self
        JorvikSettingsView.showWindow(appName: "Browser Commander", updateChecker: updateChecker) {
            BrowserCommanderSettingsContent(delegate: delegate)
        }
    }
}
