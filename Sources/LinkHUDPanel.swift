import AppKit
import ApplicationServices

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

/// Navigates the current tab of the given browser to a URL via osascript
func navigateBrowserTab(bundleID: String, url: String) {
    let escaped = url.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")

    let script: String
    if safariBundleIDs.contains(bundleID) {
        script = "tell application id \"\(bundleID)\" to set URL of document 1 to \"\(escaped)\""
    } else if chromiumBundleIDs.contains(bundleID) {
        script = "tell application id \"\(bundleID)\" to set URL of active tab of front window to \"\(escaped)\""
    } else {
        script = "tell application id \"\(bundleID)\" to open location \"\(escaped)\""
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
}

/// A floating HUD panel that displays browser links for keyboard navigation.
/// Type to filter, up/down to select, Enter to activate, Escape to dismiss.
@MainActor
final class LinkHUDPanel: NSObject, HUDKeyPanelDelegate {

    private var panel: NSPanel?
    private var scrollView: NSScrollView!
    private var tableView: NSTableView!
    private var searchField: NSTextField!
    private var countLabel: NSTextField!

    private var allLinks: [ScrapedLink] = []
    private var filteredLinks: [ScrapedLink] = []
    private var selectedIndex: Int = 0

    /// The browser app that was frontmost when the HUD was opened
    private var browserApp: NSRunningApplication?
    /// The browser window frame for centring the HUD
    private var browserWindowFrame: CGRect?

    // Visual constants
    private let panelWidth: CGFloat = 560
    private let panelHeight: CGFloat = 420
    private let rowHeight: CGFloat = 32

    func show(links: [ScrapedLink], browserPID: pid_t) {
        allLinks = links
        filteredLinks = links
        selectedIndex = 0
        browserApp = NSWorkspace.shared.frontmostApplication
        browserWindowFrame = getBrowserWindowFrame(pid: browserPID)

        if panel == nil {
            createPanel()
        }

        _linkHUDIsVisible = true
        searchField.stringValue = ""
        updateFilter()
        positionPanel()
        panel?.makeKeyAndOrderFront(nil)
        searchField.becomeFirstResponder()
    }

    func dismiss() {
        _linkHUDIsVisible = false
        panel?.orderOut(nil)
    }

    func deleteSelected() {
        // No delete for links
    }

    // MARK: - Panel creation

    private func createPanel() {
        let p = HUDKeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = false
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.hudDelegate = self

        // Main container with vibrancy — .underWindowBackground gives the glassy translucent look
        let visualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        visualEffect.material = .underWindowBackground
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true

        // Search field
        searchField = NSTextField(frame: NSRect(x: 16, y: panelHeight - 52, width: panelWidth - 32, height: 28))
        searchField.placeholderString = "Filter links..."
        searchField.font = .systemFont(ofSize: 14)
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.textColor = .labelColor
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchAction)

        // Separator
        let sep = NSBox(frame: NSRect(x: 16, y: panelHeight - 58, width: panelWidth - 32, height: 1))
        sep.boxType = .separator

        // Count label
        countLabel = NSTextField(labelWithString: "")
        countLabel.frame = NSRect(x: 16, y: 8, width: panelWidth - 32, height: 16)
        countLabel.font = .systemFont(ofSize: 10)
        countLabel.textColor = .tertiaryLabelColor
        countLabel.alignment = .right

        // Table view for links
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("link"))
        column.width = panelWidth - 40

        tableView = NSTableView(frame: .zero)
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self
        tableView.doubleAction = #selector(activateSelected)
        tableView.target = self

        scrollView = NSScrollView(frame: NSRect(x: 8, y: 28, width: panelWidth - 16, height: panelHeight - 90))
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        visualEffect.addSubview(searchField)
        visualEffect.addSubview(sep)
        visualEffect.addSubview(scrollView)
        visualEffect.addSubview(countLabel)

        p.contentView = visualEffect

        panel = p
    }

    private func positionPanel() {
        // Centre on the browser window if we have its frame, otherwise screen centre
        if let wf = browserWindowFrame {
            let x = wf.midX - panelWidth / 2
            // Cocoa Y is flipped — convert from CG (top-left origin) to NS (bottom-left origin)
            guard let screen = NSScreen.main else { return }
            let screenH = screen.frame.height
            let nsWindowMidY = screenH - wf.midY
            let y = nsWindowMidY - panelHeight / 2
            panel?.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            guard let screen = NSScreen.main else { return }
            let x = screen.visibleFrame.midX - panelWidth / 2
            let y = screen.visibleFrame.midY - panelHeight / 2
            panel?.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    /// Gets the browser's focused window frame via the Accessibility API
    private func getBrowserWindowFrame(pid: pid_t) -> CGRect? {
        let app = AXUIElementCreateApplication(pid)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowValue) == .success else {
            return nil
        }
        let window = windowValue as! AXUIElement

        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }

        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)

        return CGRect(origin: pos, size: size)
    }

    // MARK: - Filtering

    private func updateFilter() {
        let query = searchField?.stringValue.lowercased() ?? ""
        if query.isEmpty {
            filteredLinks = allLinks
        } else {
            filteredLinks = allLinks.filter { link in
                link.title.lowercased().contains(query) ||
                link.url.lowercased().contains(query)
            }
        }
        selectedIndex = filteredLinks.isEmpty ? -1 : 0
        tableView?.reloadData()
        if selectedIndex >= 0 {
            tableView?.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
            tableView?.scrollRowToVisible(selectedIndex)
        }
        countLabel?.stringValue = "\(filteredLinks.count) of \(allLinks.count) links"
    }

    // MARK: - Navigation

    func moveSelectionUp() {
        guard !filteredLinks.isEmpty else { return }
        selectedIndex = max(0, selectedIndex - 1)
        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        tableView.scrollRowToVisible(selectedIndex)
    }

    func moveSelectionDown() {
        guard !filteredLinks.isEmpty else { return }
        selectedIndex = min(filteredLinks.count - 1, selectedIndex + 1)
        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        tableView.scrollRowToVisible(selectedIndex)
    }

    @objc func activateSelected() {
        guard selectedIndex >= 0, selectedIndex < filteredLinks.count else { return }
        let link = filteredLinks[selectedIndex]
        guard !link.url.isEmpty else { return }

        let urlString = link.url
        let bundleID = browserApp?.bundleIdentifier ?? ""

        dismiss()

        // Navigate in the current tab via AppleScript
        DispatchQueue.global(qos: .userInitiated).async {
            navigateBrowserTab(bundleID: bundleID, url: urlString)
        }
    }

    @objc private func searchAction() {
        activateSelected()
    }
}

// MARK: - NSTextFieldDelegate

extension LinkHUDPanel: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        updateFilter()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            moveSelectionUp()
            return true
        }
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            moveSelectionDown()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            dismiss()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            activateSelected()
            return true
        }
        return false
    }
}

// MARK: - NSTableViewDataSource & NSTableViewDelegate

extension LinkHUDPanel: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredLinks.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filteredLinks.count else { return nil }
        let link = filteredLinks[row]

        let cellID = NSUserInterfaceItemIdentifier("LinkCell")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView(frame: NSRect(x: 0, y: 0, width: tableColumn?.width ?? panelWidth - 40, height: rowHeight))
            cell.identifier = cellID

            let titleField = NSTextField(labelWithString: "")
            titleField.tag = 1
            titleField.font = .systemFont(ofSize: 13)
            titleField.textColor = .labelColor
            titleField.lineBreakMode = .byTruncatingTail
            titleField.translatesAutoresizingMaskIntoConstraints = false

            let urlField = NSTextField(labelWithString: "")
            urlField.tag = 2
            urlField.font = .systemFont(ofSize: 10)
            urlField.textColor = .tertiaryLabelColor
            urlField.lineBreakMode = .byTruncatingMiddle
            urlField.translatesAutoresizingMaskIntoConstraints = false

            cell.addSubview(titleField)
            cell.addSubview(urlField)

            NSLayoutConstraint.activate([
                titleField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                titleField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                titleField.topAnchor.constraint(equalTo: cell.topAnchor, constant: 2),

                urlField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                urlField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                urlField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 0),
            ])
        }

        if let titleField = cell.viewWithTag(1) as? NSTextField {
            titleField.stringValue = link.title
        }
        if let urlField = cell.viewWithTag(2) as? NSTextField {
            urlField.stringValue = link.url.isEmpty ? "" : shortenURL(link.url)
        }

        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        rowHeight
    }

    private func shortenURL(_ url: String) -> String {
        var short = url
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        if short.hasSuffix("/") { short = String(short.dropLast()) }
        if short.count > 80 { short = String(short.prefix(77)) + "..." }
        return short
    }
}

// MARK: - Custom NSPanel that forwards key events

@MainActor
protocol HUDKeyPanelDelegate: AnyObject {
    func moveSelectionUp()
    func moveSelectionDown()
    func activateSelected()
    func deleteSelected()
    func dismiss()
}

/// NSPanel subclass that can become key without activating the app
final class HUDKeyPanel: NSPanel {
    weak var hudDelegate: (any HUDKeyPanelDelegate)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: hudDelegate?.moveSelectionUp()
        case 125: hudDelegate?.moveSelectionDown()
        case 36:  hudDelegate?.activateSelected()
        case 51:  hudDelegate?.deleteSelected()  // Backspace
        case 53:  hudDelegate?.dismiss()
        default:  super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        hudDelegate?.dismiss()
    }
}
