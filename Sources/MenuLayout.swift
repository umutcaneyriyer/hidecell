import AppKit
import ApplicationServices

struct LayoutTarget {
    let id: String
    let name: String
    let owners: Set<String>
}

struct BarPosition {
    let key: String
    let owner: String
    let element: AXUIElement
    let frame: CGRect
    var eventPID: pid_t = 0
    var eventWindow: UInt32 = 0
}

enum MenuLayout {
    static let layoutURL = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar.plist")
    private static var grantedURL: URL?
    static func requestLayoutAccess() -> Bool {
        if grantedURL == nil, let data = UserDefaults.standard.data(forKey: "menuLayoutBookmark") {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale), url == layoutURL {
                _ = url.startAccessingSecurityScopedResource()
                grantedURL = url
            }
        }
        if FileManager.default.isReadableFile(atPath: layoutURL.path) { return true }
        let panel = NSOpenPanel()
        panel.title = "Menu bar layout access"
        panel.message = "Select the macOS menu layout file to apply your order. Hidecell will only access this file."
        panel.prompt = "Allow Layout Access"
        panel.directoryURL = layoutURL.deletingLastPathComponent()
        panel.nameFieldStringValue = layoutURL.lastPathComponent
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, url.standardizedFileURL == layoutURL.standardizedFileURL else { return false }
        _ = url.startAccessingSecurityScopedResource()
        grantedURL = url
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmark, forKey: "menuLayoutBookmark")
        }
        return true
    }
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, 0.1)
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }

    static func rect(_ element: AXUIElement) -> CGRect? {
        if let raw = attribute(element, "AXFrame"), CFGetTypeID(raw) == AXValueGetTypeID() {
            var frame = CGRect.zero
            if AXValueGetValue(raw as! AXValue, .cgRect, &frame), frame.width >= 4, frame.height >= 4, frame.height < 70 { return frame }
        }
        guard let p = attribute(element, kAXPositionAttribute), let s = attribute(element, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point),
              AXValueGetValue(s as! AXValue, .cgSize, &size),
              size.width >= 4, size.height >= 4, size.height < 70 else { return nil }
        return CGRect(origin: point, size: size)
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    static func items(owner: String, pid: pid_t) -> [BarPosition] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        guard let raw = attribute(app, kAXExtrasMenuBarAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return [] }
        let bar = raw as! AXUIElement
        var result: [BarPosition] = []
        for (i, child) in children(bar).enumerated() {
            guard let frame = rect(child) else { continue }
            let identity = attribute(child, kAXIdentifierAttribute) as? String ?? String(i)
            result.append(BarPosition(key: owner + ":" + identity, owner: owner, element: child, frame: frame))
        }
        return result
    }

    static func visibleWindows(_ root: AXUIElement) -> [AXUIElement] {
        let windows = children(root).filter { (attribute($0, kAXRoleAttribute) as? String) == "AXWindow" }
        let onscreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let numbers = Set(onscreen.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
        let scored = windows.map { window -> (AXUIElement, Int) in
            let count = children(window).flatMap { children($0) }.filter { (attribute($0, kAXRoleAttribute) as? String) == "AXButton" }.count
            return (window, count)
        }
        let report = scored.map { window, count in
            let roles = children(window).map { slot in
                children(slot).map { child in
                    let role = attribute(child, kAXRoleAttribute) as? String ?? "?"
                    var pid: pid_t = 0
                    AXUIElementGetPid(child, &pid)
                    return "\(role):\(pid)"
                }.joined(separator: ",")
            }.joined(separator: " | ")
            return "window=\(STMenuBarShim.windowNumber(window)) visible=\(numbers.contains(STMenuBarShim.windowNumber(window))) buttons=\(count) children=\(roles)"
        }.joined(separator: "\n")
        try? report.write(toFile: NSTemporaryDirectory() + "Hidecell-windows.txt", atomically: true, encoding: .utf8)
        if let active = scored.max(by: { $0.1 < $1.1 }), active.1 > 0 { return [active.0] }
        return windows.filter { numbers.contains(STMenuBarShim.windowNumber($0)) }
    }

    static func systemItems() -> [BarPosition] {
        guard let host = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.MenuBarAgent" }) else { return [] }
        let root = AXUIElementCreateApplication(host.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.2)
        var result: [BarPosition] = []
        func walk(_ element: AXUIElement, depth: Int) {
            guard depth < 5 else { return }
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            guard pid == host.processIdentifier else { return }
            let identifier = attribute(element, kAXIdentifierAttribute) as? String ?? ""
            let title = attribute(element, kAXTitleAttribute) as? String ?? ""
            let description = attribute(element, kAXDescriptionAttribute) as? String ?? ""
            if identifier.hasPrefix("com.apple.menuextra.") || title == "Spotlight" || description == "Spotlight" {
                if let frame = rect(element) {
                    result.append(.init(key: identifier.isEmpty ? "Spotlight" : identifier,
                                        owner: "system", element: element, frame: frame))
                }
            }
            for child in children(element) { walk(child, depth: depth + 1) }
        }
        for window in visibleWindows(root) {
            walk(window, depth: 0)
        }
        return result
    }

    static func onScreen(_ frame: CGRect) -> Bool {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(16, &displays, &count) == .success else { return false }
        return displays.prefix(Int(count)).contains { display in
            let screen = CGDisplayBounds(display)
            return frame.midX >= screen.minX && frame.midX < screen.maxX &&
                frame.midY >= screen.minY && frame.midY < screen.minY + 65
        }
    }

    static func snapshot() -> [BarPosition] {
        guard let host = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.MenuBarAgent" }) else { return [] }
        let root = AXUIElementCreateApplication(host.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.2)
        var result: [BarPosition] = []
        for window in visibleWindows(root) {
            for (index, slot) in children(window).enumerated() {
                guard let frame = rect(slot) else { continue }
                var queue = children(slot)
                var visited = 0
                while !queue.isEmpty && visited < 20 {
                    let element = queue.removeFirst()
                    visited += 1
                    var pid: pid_t = 0
                    AXUIElementGetPid(element, &pid)
                    if pid != host.processIdentifier, let app = NSRunningApplication(processIdentifier: pid),
                       let owner = app.bundleIdentifier, !owner.hasPrefix("com.apple.") {
                        result.append(.init(key: owner + ":" + String(index), owner: owner, element: slot, frame: frame, eventPID: host.processIdentifier, eventWindow: STMenuBarShim.windowNumber(window)))
                        break
                    }
                    queue.append(contentsOf: children(element))
                }
            }
        }
        var seen = Set<String>()
        return result.filter { item in
            seen.insert(item.owner + ":" + String(Int(item.frame.midX)) + ":" + String(Int(item.frame.midY))).inserted
        }
    }

    static func arrange(_ targets: [LayoutTarget], hiddenOwners: Set<String> = []) -> (success: Bool, message: String) {
        guard AXIsProcessTrusted() else { return (false, "Accessibility permission is required to reorder icons.") }
        let path = NSHomeDirectory() + "/Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar"
        let domain = path as CFString
        let key = "TrailingItemPreferredPositions" as CFString
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard let original = CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String: Double], !original.isEmpty else {
            return (false, "Could not read the macOS menu layout. Order was not changed.")
        }
        let running = NSWorkspace.shared.runningApplications
        let groups = targets.map { target -> Set<String> in
            var aliases = target.owners
            for app in running where app.bundleIdentifier.map({ target.owners.contains($0) }) == true {
                if let name = app.executableURL?.lastPathComponent { aliases.insert(name) }
            }
            return aliases
        }
        let before = snapshot()
        let systemFrames = systemItems().map(\.frame).filter { onScreen($0) }
        guard let systemEdge = systemFrames.map(\.minX).min(),
              let screenRight = systemFrames.map(\.maxX).max() else {
            return (false, "The menu bar is not ready. Please try Save again.")
        }
        // Preferences store point offsets from the trailing edge, not ranks.
        // Ignore old, currently invisible system records when packing the apps.
        let boundary = screenRight - systemEdge + 20
        let widths = targets.map { target in
            Double(before.filter { target.owners.contains($0.owner) }.map { $0.frame.width }.max() ?? 38)
        }
        let positions = MenuOrderPolicy.packedOffsets(widths: widths, boundary: Double(boundary))
        var updated = original
        for (index, aliases) in groups.enumerated() {
            let tags = original.keys.filter { tag in aliases.contains { tag.hasPrefix("status:" + $0 + "::") } }
                .sorted { (original[$0] ?? 0) > (original[$1] ?? 0) }
            guard !tags.isEmpty else { return (false, "Menu item record not found: " + targets[index].name) }
            // Historical aliases of a provider must not each reserve another slot.
            for (offset, tag) in tags.enumerated() {
                updated[tag] = positions[index] + Double(tags.count - offset - 1) * 0.01
            }
        }
        if UserDefaults.standard.dictionary(forKey: "nativeMenuLayoutBackup") == nil {
            UserDefaults.standard.set(original, forKey: "nativeMenuLayoutBackup")
        }
        CFPreferencesSetValue(key, updated as CFDictionary, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            return (false, "Could not save the menu layout.")
        }
        guard let host = running.first(where: { $0.bundleIdentifier == "com.apple.MenuBarAgent" }), kill(host.processIdentifier, SIGTERM) == 0 else {
            return (false, "Layout saved, but the menu bar could not be refreshed.")
        }
        // MenuBarAgent rebuilds status items asynchronously. A single snapshot
        // can contain missing providers and overlapping transitional slots.
        var missing: [String] = []
        var misplaced: [String] = []
        var consecutiveValid = 0
        let deadline = Date().addingTimeInterval(15)
        repeat {
            Thread.sleep(forTimeInterval: 0.75)
            let after = snapshot()
            let systems = systemItems().filter { onScreen($0.frame) }
            try? (after + systems).map { "\($0.owner) \($0.frame)" }.joined(separator: "\n").write(toFile: NSTemporaryDirectory() + "Hidecell-layout-after.txt", atomically: true, encoding: .utf8)
            CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            let persisted = CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String: Double] ?? [:]
            let savedCorrectly = groups.allSatisfy { aliases in
                let tags = updated.keys.filter { tag in aliases.contains { tag.hasPrefix("status:" + $0 + "::") } }
                return tags.allSatisfy { tag in persisted[tag] == updated[tag] }
            }
            guard savedCorrectly else {
                consecutiveValid = 0
                misplaced = ["saved menu layout"]
                continue
            }
            missing = []
            misplaced = []
            guard let edge = systems.map(\.frame.minX).min() else {
                consecutiveValid = 0
                missing = ["system icons"]
                continue
            }
            // Overflow slots at the leading edge share a placeholder location.
            // They have no independent screen order; their persisted offsets above
            // remain the source of truth until macOS has room to display them.
            let leftmost = after.map { $0.frame.minX }.min() ?? 0
            let overflowOwners = Set(after.filter { item in
                item.frame.minX <= leftmost + 8 && after.contains { other in
                    other.owner != item.owner && item.frame.intersection(other.frame).width > min(item.frame.width, other.frame.width) * 0.5
                }
            }.map(\.owner))
            var previous: CGFloat = -.infinity
            for target in targets {
                if !target.owners.isDisjoint(with: hiddenOwners) || !target.owners.isDisjoint(with: overflowOwners) { continue }
                let frames = after.filter { target.owners.contains($0.owner) }.map(\.frame)
                guard !frames.isEmpty else { missing.append(target.name); continue }
                guard frames.allSatisfy({ onScreen($0) && $0.maxX <= edge + 1 }),
                      let first = frames.map(\.minX).min(), let last = frames.map(\.maxX).max(), first >= previous - 1 else {
                    misplaced.append(target.name)
                    continue
                }
                previous = last
            }
            if missing.isEmpty && misplaced.isEmpty {
                consecutiveValid += 1
                if consecutiveValid >= 2 {
                    return (true, "Order applied. App icons are to the left of system icons.")
                }
            } else { consecutiveValid = 0 }
        } while Date() < deadline
        if !missing.isEmpty {
            return (false, "Order saved. These icons did not become readable: " + missing.joined(separator: ", ") + ".")
        }
        return (false, "Order saved, but these icons are not in the requested position: " + misplaced.joined(separator: ", ") + ".")
    }
}
