import Foundation

struct RunningIdentity {
    let owner: String
    let parent: String
}

enum IconPolicy {
    static func allowlist(running: [RunningIdentity], selected: Set<String>, ownID: String) -> Set<String> {
        var allowed = Set<String>()
        // A menu-only launcher can register its status item using the parent ID.
        // All owners of a selected parent must be covered, including newly launched helpers.
        let hiddenParents = Set(running.filter { selected.contains($0.owner) || selected.contains($0.parent) }.map(\.parent))
        for app in running where !hiddenParents.contains(app.parent) {
            allowed.formUnion([app.owner, app.parent])
        }
        allowed.insert(ownID)
        return allowed
    }

    static func outerBundle(_ url: URL) -> URL {
        var root = URL(fileURLWithPath: "/")
        for component in url.pathComponents.dropFirst() {
            root.appendPathComponent(component)
            if root.pathExtension == "app" { return root }
        }
        return url
    }

    static func newlyDiscovered(groups: [String: Set<String>], known: Set<String>, ownID: String) -> Set<String> {
        Set(groups.compactMap { id, owners in
            guard id != ownID, !id.hasPrefix("com.apple."),
                  known.isDisjoint(with: owners.union([id])) else { return nil }
            return id
        })
    }

    static func keepOwner(hasExtras: Bool, confirmed: Bool, hidden: Bool, transientFailure: Bool) -> Bool {
        hasExtras || (confirmed && (hidden || transientFailure))
    }
}


enum MenuOrderPolicy {
    static func packedOffsets(widths: [Double], boundary: Double) -> [Double] {
        var result = Array(repeating: 0.0, count: widths.count)
        var trailing = boundary + 8
        for index in widths.indices.reversed() {
            result[index] = trailing
            trailing += max(16, widths[index]) + 8
        }
        return result
    }

    static func positions(_ existing: [String: Double], groups: [Set<String>]) -> [String: Double] {
        var result = existing
        func owner(_ tag: String) -> String? {
            guard tag.hasPrefix("status:"), let end = tag.range(of: "::") else { return nil }
            return String(tag[tag.index(tag.startIndex, offsetBy: 7)..<end.lowerBound])
        }
        let systemKeys = existing.keys.filter { key in
            key.hasPrefix("module:") || owner(key)?.hasPrefix("com.apple.") == true || owner(key) == "GamePolicyAgent"
        }
        let boundary = systemKeys.compactMap { existing[$0] }.max() ?? 0
        let unmanaged = existing.keys.filter { key in
            guard let id = owner(key), !systemKeys.contains(key) else { return false }
            return !groups.contains(where: { $0.contains(id) })
        }.sorted()
        for (index, group) in groups.enumerated() {
            let position = boundary + 100 + Double(groups.count - index) * 100
            for tag in existing.keys where owner(tag).map({ group.contains($0) }) == true { result[tag] = position }
            for id in group { result["status:" + id + "::Item-0"] = position }
        }
        for (index, tag) in unmanaged.enumerated() {
            result[tag] = boundary + 200 + Double(groups.count + unmanaged.count - index) * 100
        }
        return result
    }
}
