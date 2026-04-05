import AppKit
import ApplicationServices

// MARK: - Module-level state for C-compatible CGEvent tap callback

private var _commanderTap: CFMachPort?
var _isEnabled: Bool = true
private var _onAction: ((CommanderAction) -> Void)?
private var _linkHUDKeyCode: UInt16 = 37  // L
private var _linkHUDModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
private var _goBackKeyCode: UInt16 = 51       // Backspace
private var _goBackModifiers: NSEvent.ModifierFlags = []
private var _goForwardKeyCode: UInt16 = 51    // Backspace
private var _goForwardModifiers: NSEvent.ModifierFlags = [.shift]

/// Set to true when the Link HUD is visible — suppresses backspace interception
var _linkHUDIsVisible: Bool = false

/// Actions the engine can trigger
enum CommanderAction {
    case goBack
    case goForward
    case showLinkHUD
}

/// Bundle IDs of known web browsers
let browserBundleIDs: Set<String> = [
    "com.apple.Safari",
    "com.apple.SafariTechnologyPreview",
    "com.google.Chrome",
    "com.google.Chrome.canary",
    "org.mozilla.firefox",
    "org.mozilla.firefoxdeveloperedition",
    "org.mozilla.nightly",
    "company.thebrowser.Browser",       // Arc
    "com.microsoft.edgemac",
    "com.brave.Browser",
    "com.operasoftware.Opera",
    "com.vivaldi.Vivaldi",
    "com.kagi.kagimacOS",               // Orion
    "org.chromium.Chromium",
    "com.nickvision.nicegram",
    "app.zen-browser.zen",              // Zen Browser
]

/// AX roles that indicate the focused element is a text input
private let textInputRoles: Set<String> = [
    "AXTextField",
    "AXTextArea",
    "AXSearchField",
    "AXComboBox",
]

// MARK: - CGEvent tap callback

private func commanderCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = _commanderTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passRetained(event)
    }

    guard _isEnabled, type == .keyDown else {
        return Unmanaged.passRetained(event)
    }

    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let modifiers = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        .intersection([.command, .control, .option, .shift])

    guard let frontApp = NSWorkspace.shared.frontmostApplication,
          let bundleID = frontApp.bundleIdentifier,
          browserBundleIDs.contains(bundleID)
    else {
        return Unmanaged.passRetained(event)
    }

    // Link HUD hotkey
    let linkMods = _linkHUDModifiers.intersection([.command, .control, .option, .shift])
    if keyCode == _linkHUDKeyCode && modifiers.contains(linkMods) {
        DispatchQueue.main.async { _onAction?(.showLinkHUD) }
        return nil
    }

    // Go Back / Go Forward
    let goBackMods = _goBackModifiers.intersection([.command, .control, .option, .shift])
    let goForwardMods = _goForwardModifiers.intersection([.command, .control, .option, .shift])
    let isGoBack = keyCode == _goBackKeyCode && modifiers == goBackMods
    let isGoForward = keyCode == _goForwardKeyCode && modifiers == goForwardMods

    if isGoBack || isGoForward {
        if _linkHUDIsVisible {
            return Unmanaged.passRetained(event)
        }
        if isTextFieldFocused(pid: frontApp.processIdentifier) {
            return Unmanaged.passRetained(event)
        }
        if isOtherAppFocused(browserPID: frontApp.processIdentifier) {
            return Unmanaged.passRetained(event)
        }
        if isGoBack {
            DispatchQueue.main.async { _onAction?(.goBack) }
            return nil
        } else {
            DispatchQueue.main.async { _onAction?(.goForward) }
            return nil
        }
    }

    return Unmanaged.passRetained(event)
}

/// Checks if the system-wide focused element belongs to a different process than the browser
/// (e.g. a Browser Notes panel is key while the browser is frontmost)
func isOtherAppFocused(browserPID: pid_t) -> Bool {
    let systemWide = AXUIElementCreateSystemWide()
    var focusedValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success else {
        return false
    }
    var pid: pid_t = 0
    AXUIElementGetPid(focusedValue as! AXUIElement, &pid)
    return pid != 0 && pid != browserPID
}

/// Uses the Accessibility API to check if the currently focused UI element is a text input
func isTextFieldFocused(pid: pid_t) -> Bool {
    let axApp = AXUIElementCreateApplication(pid)

    var focusedValue: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedValue)
    guard result == .success else { return true }

    let element = focusedValue as! AXUIElement
    var roleValue: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)

    if let role = roleValue as? String {
        if textInputRoles.contains(role) { return true }

        if role == "AXWebArea" || role == "AXGroup" {
            var focusedChild: CFTypeRef?
            let childResult = AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focusedChild)
            if childResult == .success {
                let child = focusedChild as! AXUIElement
                var childRole: CFTypeRef?
                AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &childRole)
                if let cr = childRole as? String, textInputRoles.contains(cr) { return true }
            }
        }
    }

    var subroleValue: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue)
    if let subrole = subroleValue as? String {
        if subrole.contains("Text") || subrole.contains("Search") { return true }
    }

    return false
}

// MARK: - BrowserCommanderEngine

@MainActor
@Observable
final class BrowserCommanderEngine {
    var isActive: Bool = false
    var permissionGranted: Bool = false
    var isEnabled: Bool = true {
        didSet {
            _isEnabled = isEnabled
            UserDefaults.standard.set(isEnabled, forKey: "browserCommanderEnabled")
        }
    }

    private var eventTap: CFMachPort?
    private var permissionTimer: Timer?
    private let linkHUD = LinkHUDPanel()

    func updateLinkHUDHotkey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        _linkHUDKeyCode = keyCode
        _linkHUDModifiers = modifiers
    }

    func updateGoBackHotkey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        _goBackKeyCode = keyCode
        _goBackModifiers = modifiers
    }

    func updateGoForwardHotkey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        _goForwardKeyCode = keyCode
        _goForwardModifiers = modifiers
    }

    func start() {
        guard !isActive else { return }

        isEnabled = UserDefaults.standard.object(forKey: "browserCommanderEnabled") != nil
            ? UserDefaults.standard.bool(forKey: "browserCommanderEnabled")
            : true
        _isEnabled = isEnabled

        if UserDefaults.standard.object(forKey: "linkHUDKeyCode") != nil {
            _linkHUDKeyCode = UInt16(UserDefaults.standard.integer(forKey: "linkHUDKeyCode"))
            _linkHUDModifiers = NSEvent.ModifierFlags(rawValue: UInt(UserDefaults.standard.integer(forKey: "linkHUDModifiers")))
        }
        if UserDefaults.standard.object(forKey: "goBackKeyCode") != nil {
            _goBackKeyCode = UInt16(UserDefaults.standard.integer(forKey: "goBackKeyCode"))
            _goBackModifiers = NSEvent.ModifierFlags(rawValue: UInt(UserDefaults.standard.integer(forKey: "goBackModifiers")))
        }
        if UserDefaults.standard.object(forKey: "goForwardKeyCode") != nil {
            _goForwardKeyCode = UInt16(UserDefaults.standard.integer(forKey: "goForwardKeyCode"))
            _goForwardModifiers = NSEvent.ModifierFlags(rawValue: UInt(UserDefaults.standard.integer(forKey: "goForwardModifiers")))
        }

        _onAction = { [weak self] action in
            Task { @MainActor in
                self?.handleAction(action)
            }
        }

        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        permissionGranted = trusted

        if trusted {
            if tryCreateEventTap() { isActive = true }
        } else {
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
                if AXIsProcessTrusted() {
                    Task { @MainActor in
                        guard let self else { return }
                        self.permissionGranted = true
                        if self.tryCreateEventTap() { self.isActive = true }
                    }
                    timer.invalidate()
                }
            }
        }
    }

    func stop() {
        isActive = false
        permissionTimer?.invalidate()
        permissionTimer = nil
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        eventTap = nil
        _commanderTap = nil
    }

    private func handleAction(_ action: CommanderAction) {
        switch action {
        case .goBack:
            sendKeyCombo(keyCode: 33, flags: .maskCommand)
        case .goForward:
            sendKeyCombo(keyCode: 30, flags: .maskCommand)
        case .showLinkHUD:
            showLinkNavigator()
        }
    }

    private func sendKeyCombo(keyCode: UInt16, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func showLinkNavigator() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let pid = frontApp.processIdentifier
        DispatchQueue.global(qos: .userInitiated).async {
            let links = LinkScraper.scrapeLinks(pid: pid)
            DispatchQueue.main.async { [weak self] in
                guard let self, !links.isEmpty else { return }
                self.linkHUD.show(links: links, browserPID: pid)
            }
        }
    }

    private func tryCreateEventTap() -> Bool {
        if eventTap != nil { return true }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: commanderCallback,
            userInfo: nil
        ) else { return false }

        eventTap = tap
        _commanderTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }
}
