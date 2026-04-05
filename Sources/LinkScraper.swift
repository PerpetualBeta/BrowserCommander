import AppKit
import ApplicationServices

/// A scraped link from the browser's accessibility tree
struct ScrapedLink {
    let title: String       // Display text for the HUD
    let url: String         // Target URL
    let element: AXUIElement  // For performing AXPress
}

/// Walks the AX tree of the frontmost browser window to find all links
enum LinkScraper {

    /// Maximum number of elements to visit (safety limit for huge pages)
    private static let maxVisited = 25000
    /// Maximum number of links to collect
    private static let maxLinks = 1000

    static func scrapeLinks(pid: pid_t) -> [ScrapedLink] {
        let app = AXUIElementCreateApplication(pid)

        // Get the focused window
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowValue) == .success else {
            return []
        }
        let window = windowValue as! AXUIElement

        // Find the web area(s) in the window
        var links: [ScrapedLink] = []
        var visited = 0
        collectLinks(from: window, into: &links, visited: &visited)

        // Deduplicate by URL, keeping the first occurrence
        var seen = Set<String>()
        return links.filter { link in
            guard !seen.contains(link.url) else { return false }
            seen.insert(link.url)
            return true
        }
    }

    private static func collectLinks(
        from element: AXUIElement,
        into links: inout [ScrapedLink],
        visited: inout Int
    ) {
        guard visited < maxVisited, links.count < maxLinks else { return }
        visited += 1

        // Check if this element is a link
        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String

        if role == "AXLink" {
            if let link = extractLink(from: element) {
                links.append(link)
            }
            // Don't recurse into links — we have what we need
            return
        }

        // Recurse into children
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement]
        else { return }

        for child in children {
            guard visited < maxVisited, links.count < maxLinks else { break }
            collectLinks(from: child, into: &links, visited: &visited)
        }
    }

    private static func extractLink(from element: AXUIElement) -> ScrapedLink? {
        // Try to get the URL
        var urlValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &urlValue)

        // Also try AXValue as fallback for URL
        var valueRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)

        let url: String
        if let u = urlValue as? URL {
            url = u.absoluteString
        } else if let u = urlValue as? String {
            url = u
        } else if let v = valueRef as? String, v.hasPrefix("http") {
            url = v
        } else {
            // Try the href from the link's child text or description
            var descValue: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descValue)
            if let d = descValue as? String, d.hasPrefix("http") {
                url = d
            } else {
                url = ""
            }
        }

        // Get display title: try AXTitle, then AXDescription, then child text, then URL
        let title = linkDisplayText(from: element) ?? (url.isEmpty ? nil : shortenURL(url))
        guard let title, !title.isEmpty else { return nil }

        return ScrapedLink(title: title, url: url, element: element)
    }

    /// Extracts human-readable display text for a link
    private static func linkDisplayText(from element: AXUIElement) -> String? {
        // AXTitle
        var titleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
        if let t = titleValue as? String, !t.trimmingCharacters(in: .whitespaces).isEmpty {
            return t.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // AXDescription (often set for image links via alt text)
        var descValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descValue)
        if let d = descValue as? String, !d.trimmingCharacters(in: .whitespaces).isEmpty,
           !d.hasPrefix("http") {
            return d.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Walk children for AXStaticText
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement]
        else { return nil }

        var texts: [String] = []
        for child in children {
            var childRole: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &childRole)

            if let cr = childRole as? String {
                if cr == "AXStaticText" {
                    var val: CFTypeRef?
                    AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &val)
                    if let v = val as? String, !v.trimmingCharacters(in: .whitespaces).isEmpty {
                        texts.append(v.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                } else if cr == "AXImage" {
                    // Image alt text
                    var imgDesc: CFTypeRef?
                    AXUIElementCopyAttributeValue(child, kAXDescriptionAttribute as CFString, &imgDesc)
                    if let d = imgDesc as? String, !d.trimmingCharacters(in: .whitespaces).isEmpty {
                        texts.append(d.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            }
        }

        let joined = texts.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    /// Shortens a URL for display (removes scheme, truncates)
    private static func shortenURL(_ url: String) -> String {
        var short = url
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        if short.hasSuffix("/") { short = String(short.dropLast()) }
        if short.count > 60 {
            short = String(short.prefix(57)) + "..."
        }
        return short
    }
}
