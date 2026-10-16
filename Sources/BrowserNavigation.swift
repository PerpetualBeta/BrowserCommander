import AppKit
import ScriptingBridge

// MARK: - Browser navigation

/// Chromium-based bundle IDs (all share the same AppleScript dictionary)
private let chromiumBundleIDs: Set<String> = [
    "com.google.Chrome", "com.google.Chrome.canary",
    "com.microsoft.edgemac", "com.brave.Browser",
    "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
    "company.thebrowser.Browser", "org.chromium.Chromium",
    "app.zen-browser.zen",
]

private let safariBundleIDs: Set<String> = [
    "com.apple.Safari", "com.apple.SafariTechnologyPreview",
]

/// Collects the error of a Scripting Bridge event that fails. Without a delegate,
/// a failed event only logs to the console.
private final class NavigationErrors: NSObject, SBApplicationDelegate {
    var last: Error?
    func eventDidFail(_ event: UnsafePointer<AppleEvent>, withError error: Error) -> Any? {
        last = error
        return nil
    }
}

/// Navigates the current tab of one browser PROCESS to a URL.
///
/// Until this version it ran `osascript -e 'tell application id "<bundle ID>" ...'`.
/// A bundle ID names an app, not a process, and two processes can have the same one:
/// Safari's WebDriver (`safaridriver`, also the Safari MCP) starts a second Safari with
/// `--automation`. AppleScript sent the event to that one. It had no windows, so the
/// event failed with "Can't get document 1" (-1719), the error went to /dev/null, and
/// choosing a link did nothing (2026-10-17). Scripting Bridge sends the same command
/// ("set URL of document 1", or "of active tab of front window") to the process ID of
/// the browser that was in front.
///
/// The log records the browser, the process and the host, never the full address.
func navigateBrowserTab(pid: pid_t, bundleID: String, url: String) {
    let host = URL(string: url)?.host ?? "?"
    let isSafari = safariBundleIDs.contains(bundleID)
    guard isSafari || chromiumBundleIDs.contains(bundleID) else {
        // No shared dictionary for other browsers (Firefox and others): ask the app
        // to open the location. These are not known to start a second process.
        openLocation(bundleID: bundleID, url: url)
        bcLog("navigate: \(bundleID) pid \(pid) host \(host) via open location")
        return
    }
    guard let app = SBApplication(processIdentifier: pid) else {
        bcLog("navigate: \(bundleID) pid \(pid): no Scripting Bridge application")
        return
    }
    let errors = NavigationErrors()
    app.delegate = errors

    let target: SBObject?
    if isSafari {
        let documents = app.value(forKey: "documents") as? SBElementArray
        target = (documents?.count ?? 0) > 0 ? documents?.object(at: 0) as? SBObject : nil
    } else {
        let windows = app.value(forKey: "windows") as? SBElementArray
        let window = (windows?.count ?? 0) > 0 ? windows?.object(at: 0) as? SBObject : nil
        target = window?.value(forKey: "activeTab") as? SBObject
    }
    guard let target else {
        let code = errors.last.map { ($0 as NSError).code } ?? 0
        bcLog("navigate: \(bundleID) pid \(pid): no front document or tab (error \(code))")
        return
    }
    target.setValue(url, forKey: "URL")
    if let error = errors.last {
        bcLog("navigate: \(bundleID) pid \(pid) host \(host) FAILED (error \((error as NSError).code))")
    } else {
        bcLog("navigate: \(bundleID) pid \(pid) host \(host) ok")
    }
}

/// The generic AppleScript "open location", for browsers without a known dictionary.
private func openLocation(bundleID: String, url: String) {
    let escaped = url.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", "tell application id \"\(bundleID)\" to open location \"\(escaped)\""]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
}
