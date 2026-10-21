import AppKit

// Use Control Center's per-application visibility preferences, not assessment mode.
// Only trackedApplications is written; unrelated Control Center settings stay intact.
enum NativeVisibility {
    #if RECOVERY_TESTING
    static let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HIDECELL_TEST_DOMAIN"]! + ".plist")
    #else
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist")
    #endif
    #if RECOVERY_TESTING
    private static let recoveryDefaults = UserDefaults(suiteName: ProcessInfo.processInfo.environment["HIDECELL_TEST_DOMAIN"]! + ".recovery")!
    #else
    private static let recoveryDefaults = UserDefaults.standard
    #endif
    private static var accessURL: URL?
    private static let backupKey = "nativeVisibilityOriginalStates"
    private static let preferenceKey = "trackedApplications"

    static func requestAccess(showPanel: Bool = true) -> Bool {
        var stale = false
        if accessURL == nil, let data = UserDefaults.standard.data(forKey: "nativeVisibilityBookmark"),
           let restored = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale), restored == url {
            _ = restored.startAccessingSecurityScopedResource()
            accessURL = restored
        }
        if (try? readRows()) != nil { return true }
        guard showPanel else { return false }
        let panel = NSOpenPanel()
        panel.title = "Menu icon visibility"
        panel.message = "Allow access to this Control Center settings file to hide icons without blocking Notification Center."
        panel.prompt = "Allow Access"
        panel.directoryURL = url.deletingLastPathComponent()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let chosen = panel.url, chosen.standardizedFileURL == url.standardizedFileURL else { return false }
        _ = chosen.startAccessingSecurityScopedResource()
        accessURL = chosen
        if let bookmark = try? chosen.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmark, forKey: "nativeVisibilityBookmark")
        }
        return (try? readRows()) != nil
    }

    enum Failure: LocalizedError {
        case unreadable, invalidFormat, writeFailed, guardianUnavailable
        var errorDescription: String? {
            switch self {
            case .guardianUnavailable: return "Icon recovery protection is unavailable. Icons were not hidden. Reopen Hidecell to try again."
            case .unreadable: return "Cannot access menu visibility settings. Reopen Hidecell and grant file access."
            case .invalidFormat: return "The macOS menu visibility format is not supported. Settings were not changed."
            case .writeFailed: return "Could not save menu visibility."
            }
        }
    }

    private static var domain: String { url.deletingPathExtension().path }
    private static func preferences(_ arguments: [String]) throws -> Data {
        // A fresh preferences client avoids cached access denials from before
        // the user selected the file. Never pass the whole domain back on write.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = arguments
        let output = Pipe()
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice
        try task.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw Failure.unreadable }
        return data
    }
    private static func readRows() throws -> [Any] {
        let exported = try preferences(["export", domain, "-"])
        guard let dictionary = try PropertyListSerialization.propertyList(from: exported, format: nil) as? [String: Any],
              let data = dictionary[preferenceKey] as? Data else { throw Failure.unreadable }
        guard let rows = try PropertyListSerialization.propertyList(from: data, format: nil) as? [Any], rows.count.isMultiple(of: 2) else { throw Failure.invalidFormat }
        return rows
    }

    struct Inventory {
        var owners: Set<String> = []
        var allowedOwners: Set<String> = []
    }

    // This registry also includes providers whose AX extras bar is unavailable.
    // Callers intersect it with running applications, so old records are not listed.
    static func inventory(from rows: [Any]) -> Inventory {
        var result = Inventory()
        guard rows.count.isMultiple(of: 2) else { return result }
        for i in stride(from: 0, to: rows.count, by: 2) {
            guard let key = rows[i] as? [String: Any],
                  let bundle = key["bundle"] as? [String: Any],
                  let id = bundle["_0"] as? String,
                  let value = rows[i + 1] as? [String: Any] else { continue }
            let locations = value["menuItemLocations"] as? [[String: Any]] ?? []
            let owners = Set(locations.compactMap {
                ($0["bundle"] as? [String: Any])?["_0"] as? String
            }).union([id]).filter { !$0.hasPrefix("com.apple.") && $0 != "app.hidecell.Hidecell" }
            result.owners.formUnion(owners)
            if value["isAllowed"] as? Bool ?? true { result.allowedOwners.formUnion(owners) }
        }
        return result
    }

    static func inventory() throws -> Inventory { inventory(from: try readRows()) }

    // Preserve unknown records and metadata. Resolve helper owners through macOS's
    // own menuItemLocations mapping instead of inventing new preference records.
    static func update(_ rows: [Any], hidden: Set<String>, originals: inout [String: Bool]) throws -> [Any] {
        guard rows.count.isMultiple(of: 2) else { throw Failure.invalidFormat }
        var result = rows
        for i in stride(from: 0, to: rows.count, by: 2) {
            guard let key = rows[i] as? [String: Any],
                  let bundle = key["bundle"] as? [String: Any], let id = bundle["_0"] as? String,
                  var value = rows[i + 1] as? [String: Any] else { continue }
            let locations = value["menuItemLocations"] as? [[String: Any]] ?? []
            let owners = Set(locations.compactMap { ($0["bundle"] as? [String: Any])?["_0"] as? String }).union([id])
            let shouldHide = !hidden.isDisjoint(with: owners) && !id.hasPrefix("com.apple.") && id != "app.hidecell.Hidecell"
            let current = value["isAllowed"] as? Bool ?? true
            if shouldHide {
                if originals[id] == nil { originals[id] = current }
                value["isAllowed"] = false
            } else if let original = originals[id] {
                value["isAllowed"] = original
                originals.removeValue(forKey: id)
            } else { continue }
            result[i + 1] = value
        }
        return result
    }

    private static var recoveryStates: [String: Bool]?

    static func apply(hidden: Set<String>) throws {
        try VisibilityGuardian.apply(hidden: hidden)
    }

    static func applyDirect(hidden: Set<String>) throws {
        // No access is needed to restore if Hidecell has never changed this domain.
        var originals = recoveryStates ?? (recoveryDefaults.dictionary(forKey: backupKey) as? [String: Bool] ?? [:])
        if hidden.isEmpty && originals.isEmpty { return }
        let recovery = originals
        let rows = try readRows()
        let updated = try update(rows, hidden: hidden, originals: &originals)
        let data = try PropertyListSerialization.data(fromPropertyList: updated, format: .binary, options: 0)
        guard !NSArray(array: rows).isEqual(to: updated) else {
            recoveryStates = originals
            recoveryDefaults.set(originals, forKey: backupKey)
            return
        }
        recoveryStates = recovery.merging(originals) { old, _ in old }
        // Persist recovery information before changing the system setting.
        recoveryDefaults.set(recovery.merging(originals) { old, _ in old }, forKey: backupKey)
        let hexadecimal = data.map { String(format: "%02x", $0) }.joined()
        _ = try preferences(["write", domain, preferenceKey, "-data", hexadecimal])
        guard NSArray(array: try readRows()).isEqual(to: updated) else { throw Failure.writeFailed }
        recoveryStates = originals
            recoveryDefaults.set(originals, forKey: backupKey)
    }
}
