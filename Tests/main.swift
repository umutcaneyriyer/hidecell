import Foundation
var count = 0
func check(_ name: String, _ value: @autoclosure () -> Bool) {
    precondition(value(), "FAIL: \(name)")
    count += 1
    print("PASS: \(name)")
}
let own = "app.hidecell.Hidecell"
let gem = RunningIdentity(owner: "com.google.GeminiMacOS.launcher", parent: "com.google.GeminiMacOS")
let extra = RunningIdentity(owner: "com.google.GeminiMacOS.new-helper", parent: gem.parent)
let chrome = RunningIdentity(owner: "com.google.Chrome", parent: "com.google.Chrome")
check("launcher includes non-running parent", IconPolicy.allowlist(running: [gem], selected: [], ownID: own).isSuperset(of: [gem.owner,gem.parent,own]))
check("parent selection hides launcher", IconPolicy.allowlist(running: [gem], selected: [gem.parent], ownID: own) == [own])
check("legacy helper selection hides parent", IconPolicy.allowlist(running: [gem], selected: [gem.owner], ownID: own) == [own])
check("new helpers inherit parent selection", IconPolicy.allowlist(running: [gem,extra], selected: [gem.parent], ownID: own) == [own])
check("helper selection covers sibling owner", IconPolicy.allowlist(running: [gem,extra], selected: [gem.owner], ownID: own) == [own])
check("unrelated app remains visible", IconPolicy.allowlist(running: [gem,chrome], selected: [gem.parent], ownID: own).contains(chrome.owner))
check("own icon survives malformed preference", IconPolicy.allowlist(running: [.init(owner: own, parent: own)], selected: [own], ownID: own) == [own])
check("stopped selected app does not hide other apps", IconPolicy.allowlist(running: [chrome], selected: [gem.parent], ownID: own).contains(chrome.parent))
check("nested launcher resolves root", IconPolicy.outerBundle(URL(fileURLWithPath: "/Applications/Gemini.app/Contents/Helpers/GeminiAppLauncher.app")).path == "/Applications/Gemini.app")
check("normal bundle unchanged", IconPolicy.outerBundle(URL(fileURLWithPath: "/Applications/Figma.app")).path == "/Applications/Figma.app")
check("spaces in bundle path", IconPolicy.outerBundle(URL(fileURLWithPath: "/Applications/My App.app/Contents/Helpers/Agent.app")).path == "/Applications/My App.app")
check("non-bundle path remains intact", IconPolicy.outerBundle(URL(fileURLWithPath: "/usr/local/bin/agent")).path == "/usr/local/bin/agent")
check("extras bar suffices without readable child count", IconPolicy.keepOwner(hasExtras: true, confirmed: false, hidden: false, transientFailure: false))
check("unknown helper excluded", !IconPolicy.keepOwner(hasExtras: false, confirmed: false, hidden: false, transientFailure: false))
check("hidden confirmed owner retained", IconPolicy.keepOwner(hasExtras: false, confirmed: true, hidden: true, transientFailure: false))
check("one timeout does not remove confirmed owner", IconPolicy.keepOwner(hasExtras: false, confirmed: true, hidden: false, transientFailure: true))
check("removed visible icon not retained forever", !IconPolicy.keepOwner(hasExtras: false, confirmed: true, hidden: false, transientFailure: false))
check("unconfirmed app not accepted on timeout", !IconPolicy.keepOwner(hasExtras: false, confirmed: false, hidden: false, transientFailure: true))


let orderInput: [String: Double] = ["module:Clock": 0, "module:WiFi": 300, "status:com.apple.campo::Item-0": 400, "status:a::custom": 2, "status:b::Item-0": 5, "status:other::Item-0": 7]
let ordered = MenuOrderPolicy.positions(orderInput, groups: [["a", "helper"], ["b"]])
check("system positions remain unchanged", ordered["module:WiFi"] == 300 && ordered["status:com.apple.campo::Item-0"] == 400)
check("all app groups sit left of system items", ordered["status:b::Item-0"]! > 400 && ordered["status:other::Item-0"]! > 400)
check("left to right ordering uses descending positions", ordered["status:a::custom"]! > ordered["status:b::Item-0"]!)
check("helper and named tags share parent order", ordered["status:helper::Item-0"] == ordered["status:a::custom"])
check("repeated ordering is stable", MenuOrderPolicy.positions(ordered, groups: [["a", "helper"], ["b"]]) == ordered)

let nativeRows: [Any] = [
    ["bundle": ["_0": "example.parent"]], ["isAllowed": true, "custom": "preserve", "menuItemLocations": [["bundle": ["_0": "example.helper"]]]],
    ["bundle": ["_0": "example.disabled"]], ["isAllowed": false],
    ["bundle": ["_0": "com.apple.test"]], ["isAllowed": true],
    ["bundle": ["_0": own]], ["isAllowed": true],
    ["unknown": "future"], ["isAllowed": true]
]
var originals: [String: Bool] = [:]
let hiddenRows = try NativeVisibility.update(nativeRows, hidden: ["example.helper", "example.disabled", "com.apple.test", own], originals: &originals)
check("native helper selection hides parent row", (hiddenRows[1] as! [String: Any])["isAllowed"] as? Bool == false)
check("native metadata preserved", (hiddenRows[1] as! [String: Any])["custom"] as? String == "preserve")
check("native system and own icons protected", (hiddenRows[5] as! [String: Any])["isAllowed"] as? Bool == true && (hiddenRows[7] as! [String: Any])["isAllowed"] as? Bool == true)
check("native initial states recorded", originals == ["example.parent": true, "example.disabled": false])
let repeatedRows = try NativeVisibility.update(hiddenRows, hidden: ["example.helper", "example.disabled"], originals: &originals)
check("native repeated hide preserves backup", originals["example.parent"] == true)
let restoredRows = try NativeVisibility.update(repeatedRows, hidden: [], originals: &originals)
check("native reveal restores exact original records", NSArray(array: restoredRows).isEqual(to: nativeRows))
check("native restoration releases managed rows", originals.isEmpty)
do {
    _ = try NativeVisibility.update(["malformed"], hidden: [], originals: &originals)
    check("native malformed input rejected", false)
} catch { check("native malformed input rejected", true) }

let packed = MenuOrderPolicy.packedOffsets(widths: [32, 42, 38], boundary: 300)
check("packed offsets use actual slot widths", packed == [404, 354, 308])
check("packed offsets handle no apps", MenuOrderPolicy.packedOffsets(widths: [], boundary: 300).isEmpty)
check("packed offsets preserve right boundary", packed.last! > 300)
print("\(count) tests passed")
