import AppKit
import CoreText
import SwiftUI
import ServiceManagement
import Carbon
import ApplicationServices
import UniformTypeIdentifiers

struct AppEntry: Identifiable {
    let id: String
    let name: String
    let icon: NSImage?
    let owners: Set<String>
}

final class BarModel: ObservableObject {
    static let ownID = "app.hidecell.Hidecell"
    @Published var entries: [AppEntry] = []
    @Published var selectionDraft: Set<String>?
    @Published var selected: Set<String>
    @Published var collapsed = true
    @Published var loginEnabled = false
    @Published var loginNeedsApproval = false
    @Published var loginError: String?
    @Published var error: String?
    @Published var visibilityNeedsAccess = false
    @Published var busy = false
    @Published var searchExpanded = false
    @Published var search = ""
    @Published var scrollEdges = ScrollEdges(top: false, bottom: false)
    @Published var trusted = AXIsProcessTrusted()
    @Published var scanning = false
    @Published var hoveredID: String?
    @Published var editingOrder = false
    private var orderBeforeEditing: [String] = []
    @Published var draggingID: String?
    private var iconCache: [String: NSImage] = [:]
    private var pendingOrder = false
    private var orderApplyTask: DispatchWorkItem?
    private var dragChangedOrder = false
    @Published var arranging = false
    @Published var orderMessage: String?
    @Published var orderedIDs = UserDefaults.standard.stringArray(forKey: "iconOrder") ?? []
    let available = true
    private var verifiedOwners = Set(UserDefaults.standard.stringArray(forKey: "verifiedMenuOwners") ?? [])
    private var knownMenuApps = Set(UserDefaults.standard.stringArray(forKey: "knownMenuApps")
        ?? ((UserDefaults.standard.stringArray(forKey: "verifiedMenuOwners") ?? [])
            + (UserDefaults.standard.stringArray(forKey: "hiddenApps") ?? [])))
    private var scanRevision = 0
    private var scanAgain = false
    private var refreshTimer: Timer?
    private var revision = 0
    private var observation: NSKeyValueObservation?
    private var presentationRevision = 0
    private var clockInteraction = ClockInteraction()
    private var clockSuspended = false
    private var visibilityToken: AnyObject?
    private var lastAllowed: Set<String>?
    private var visibilityRevision = 0
    private var removalTimer: Timer?
    private var diagnostics: [String] = []
    var onStateChange: (() -> Void)?

    init() {
        selected = Set(UserDefaults.standard.stringArray(forKey: "hiddenApps") ?? [])
        selected.remove(Self.ownID)
        refresh()
        observation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            DispatchQueue.main.async { self?.apply(); self?.refresh() }
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refreshLoginStatus() {
        loginEnabled = SMAppService.mainApp.status == .enabled
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    func setLoginEnabled(_ enabled: Bool) {
        loginError = nil
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            loginError = "Launch at login: \(error.localizedDescription)"
        }
        refreshLoginStatus()
    }

    func configureLogin() {
        refreshLoginStatus()
        if !UserDefaults.standard.bool(forKey: "hidecellLoginConfigured") {
            if !loginEnabled && !loginNeedsApproval { setLoginEnabled(true) }
            if loginEnabled || loginNeedsApproval {
                UserDefaults.standard.set(true, forKey: "hidecellLoginConfigured")
            }
        }
    }

    func requestAccess() {
        // Open Settings directly; asking AX to show a modal at the same time
        // leaves a second consent window covering the permission controls.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            if !NSWorkspace.shared.open(url) {
                error = "Open System Settings → Privacy & Security and enable Hidecell in Device Control and Data Access (Accessibility)."
            }
        }
    }

    func parentURL(owner: String, url: URL) -> URL {
        let root = IconPolicy.outerBundle(url)
        if root != url { return root }
        var components = owner.split(separator: ".")
        while components.count > 3 {
            components.removeLast()
            let parentID = components.joined(separator: ".")
            if let parent = NSWorkspace.shared.urlForApplication(withBundleIdentifier: parentID),
               Bundle(url: parent)?.bundleIdentifier == parentID { return parent }
        }
        return root
    }

    func runningIdentities() -> [RunningIdentity] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let owner = app.bundleIdentifier else { return nil }
            let parent = app.bundleURL.map { parentURL(owner: owner, url: $0) }
            return RunningIdentity(owner: owner, parent: parent.flatMap { Bundle(url: $0)?.bundleIdentifier } ?? owner)
        }
    }

    func startHiding() {
        visibilityNeedsAccess = false
        guard AXIsProcessTrusted() else { return }
        if removalTimer == nil {
            clockInteraction.isHidden = { [weak self] in self?.visibilityToken != nil }
            clockInteraction.reveal = { [weak self] in self?.clockSuspended = true; self?.reveal() }
            clockInteraction.resume = { [weak self] in self?.clockSuspended = false; self?.apply() }
            clockInteraction.start()
            let executable = Bundle.main.executableURL
            removalTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let executable, !FileManager.default.fileExists(atPath: executable.path) else { return }
                self?.collapsed = false
                self?.reveal()
                NSApp.terminate(nil)
            }
        }
        apply()
    }

    func grantVisibilityAccess() { requestAccess() }

    func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Hidecell-diagnostics.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = ["Hidecell V1 Node (1.5, build 16)", "Path: \(Bundle.main.bundlePath)",
                    "Login: \(SMAppService.mainApp.status.rawValue)", "AX trusted: \(AXIsProcessTrusted())",
                    "Collapsed: \(collapsed)", "Busy: \(busy)",
                    "Selected: \(selected.sorted().joined(separator: ", "))",
                    "Visibility backend: Control Center trackedApplications"] + diagnostics
        do { try text.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8) }
        catch { self.error = error.localizedDescription }
    }

    func updateHover(_ id: String?) {
        guard hoveredID != id else { return }
        hoveredID = id
    }

    func refresh() {
        let access = AXIsProcessTrusted()
        if trusted != access {
            trusted = access
            if access { startHiding() }
            else { reveal() }
        }
        guard trusted else {
            scanRevision += 1
            entries = []
            return
        }
        guard !arranging, !editingOrder else { return }
        guard !scanning else { scanAgain = true; return }
        scanning = true
        scanRevision += 1
        let revision = scanRevision
        let candidates = NSWorkspace.shared.runningApplications.compactMap { app -> (pid_t, String, URL, String)? in
            guard let id = app.bundleIdentifier, let url = app.bundleURL,
                  id != Self.ownID, !id.hasPrefix("com.apple.") else { return nil }
            let parent = parentURL(owner: id, url: url)
            return (app.processIdentifier, id, parent, Bundle(url: parent)?.bundleIdentifier ?? id)
        }
        let remembered = verifiedOwners
        let hidden = collapsed ? selected : []
        let stateRevision = presentationRevision
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var found: [(String, URL)] = []
            let nativeInventory = try? NativeVisibility.inventory()
            let registry = nativeInventory ?? NativeVisibility.Inventory()
            // AX traversal is an expensive fallback, not a mandatory polling step.
            let menuOwners = nativeInventory == nil ? Set(MenuLayout.snapshot().map(\.owner)) : Set<String>()
            var verified = Set<String>()
            var details: [String] = []
            for (pid, id, url, parentID) in candidates {
                let element = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(element, 0.2)
                var value: CFTypeRef?
                let registered = registry.owners.contains(id) || registry.owners.contains(parentID)
                var result: AXError = .success
                if !registered { result = AXUIElementCopyAttributeValue(element, kAXExtrasMenuBarAttribute as CFString, &value) }
                if result == .cannotComplete {
                    AXUIElementSetMessagingTimeout(element, 0.6)
                    result = AXUIElementCopyAttributeValue(element, kAXExtrasMenuBarAttribute as CFString, &value)
                }
                let hasExtras = registry.owners.contains(id) || registry.owners.contains(parentID) || menuOwners.contains(id) || (result == .success && value.map { CFGetTypeID($0) == AXUIElementGetTypeID() } == true)
                // Some status-item providers expose AXExtrasMenuBar but not AXChildren.
                // Requiring a positive child count incorrectly excluded those providers.
                if hasExtras { verified.insert(id) }
                let keep = IconPolicy.keepOwner(hasExtras: hasExtras, confirmed: remembered.contains(id),
                    hidden: hidden.contains(id) || hidden.contains(parentID), transientFailure: result == .cannotComplete)
                details.append("\(id) -> \(parentID): AX=\(result.rawValue), extras=\(hasExtras), included=\(keep)")
                if keep { found.append((id, url)) }

            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.scanning = false
                guard revision == self.scanRevision, AXIsProcessTrusted(), !self.arranging, !self.editingOrder else {
                    self.scanAgain = false
                    return
                }
                guard stateRevision == self.presentationRevision else { self.refresh(); return }
                self.diagnostics = details
                let updatedOwners = self.verifiedOwners.union(verified)
                if updatedOwners != self.verifiedOwners {
                    self.verifiedOwners = updatedOwners
                    UserDefaults.standard.set(updatedOwners.sorted(), forKey: "verifiedMenuOwners")
                }
                var groups: [String: (URL, Set<String>)] = [:]
                for (owner, url) in found {
                    let root = url
                    let id = Bundle(url: root)?.bundleIdentifier ?? owner
                    if groups[id] == nil { groups[id] = (root, []) }
                    groups[id]!.1.insert(owner)
                }
                let newApps = IconPolicy.newlyDiscovered(groups: groups.mapValues { $0.1 },
                    known: self.knownMenuApps, ownID: Self.ownID)
                if !newApps.isEmpty {
                    self.selected.formUnion(newApps)
                    // Preserve an in-progress edit when a provider appears mid-scan.
                    if self.selectionDraft != nil { self.selectionDraft?.formUnion(newApps) }
                    UserDefaults.standard.set(self.selected.sorted(), forKey: "hiddenApps")
                    self.presentationRevision += 1
                }
                self.knownMenuApps.formUnion(groups.keys)
                self.knownMenuApps.formUnion(groups.values.flatMap { $0.1 })
                UserDefaults.standard.set(self.knownMenuApps.sorted(), forKey: "knownMenuApps")
                let activePaths = Set(groups.values.map { $0.0.path })
                self.iconCache = self.iconCache.filter { activePaths.contains($0.key) }
                let updatedEntries = groups.map { id, group in
                    let bundle = Bundle(url: group.0)
                    let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                        ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                        ?? group.0.deletingPathExtension().lastPathComponent
                    let icon = self.iconCache[group.0.path] ?? NSWorkspace.shared.icon(forFile: group.0.path)
                    self.iconCache[group.0.path] = icon
                    return AppEntry(id: id, name: name, icon: icon, owners: group.1)
                }.sorted { left, right in
                    let l = self.orderedIDs.firstIndex(of: left.id) ?? Int.max
                    let r = self.orderedIDs.firstIndex(of: right.id) ?? Int.max
                    return l == r ? left.name.localizedStandardCompare(right.name) == .orderedAscending : l < r
                }
                if self.entries.count != updatedEntries.count || zip(self.entries, updatedEntries).contains(where: {
                    $0.id != $1.id || $0.name != $1.name || $0.owners != $1.owners
                }) {
                    self.entries = updatedEntries
                }
                // A provider can register its icon after the launch notification.
                // Reapply only saved choices that macOS currently reports visible.
                let identities = self.runningIdentities()
                let hiddenParents = Set(identities.filter {
                    self.selected.contains($0.owner) || self.selected.contains($0.parent)
                }.map(\.parent))
                let hiddenOwners = self.selected.union(identities.filter {
                    hiddenParents.contains($0.parent)
                }.flatMap { [$0.owner, $0.parent] })
                if self.collapsed && (!newApps.isEmpty || !registry.allowedOwners.isDisjoint(with: hiddenOwners)) {
                    self.apply()
                }
                if self.scanAgain { self.scanAgain = false; self.refresh() }
            }
        }
    }

    func beginEditingOrder() {
        guard !arranging, !hasVisibilityChanges else { return }
        orderApplyTask?.cancel()
        orderBeforeEditing = entries.map(\.id)
        search = ""
        error = nil
        editingOrder = true
        dragChangedOrder = false
    }

    func cancelEditingOrder() {
        guard !arranging else { return }
        entries.sort { (orderBeforeEditing.firstIndex(of: $0.id) ?? Int.max) < (orderBeforeEditing.firstIndex(of: $1.id) ?? Int.max) }
        editingOrder = false
        draggingID = nil
        dragChangedOrder = false
        refresh()
    }

    var hasOrderChanges: Bool {
        editingOrder && entries.map(\.id) != orderBeforeEditing
    }

    func saveEditingOrder() {
        guard editingOrder, !arranging, hasOrderChanges else { return }
        draggingID = nil
        editingOrder = false
        dragChangedOrder = false
        orderedIDs = entries.map(\.id) + orderedIDs.filter { id in !entries.contains(where: { $0.id == id }) }
        UserDefaults.standard.set(orderedIDs, forKey: "iconOrder")
        arrangeIcons()
    }

    func moveEntry(id: String, onto targetID: String) {
        guard editingOrder, !arranging, id != targetID,
              let from = entries.firstIndex(where: { $0.id == id }),
              let to = entries.firstIndex(where: { $0.id == targetID }) else { return }
        dragChangedOrder = true
        let entry = entries.remove(at: from)
        entries.insert(entry, at: to)
    }

    func finishReordering() {
        NSCursor.arrow.set()
        draggingID = nil
    }

    func arrangeIcons() {
        guard trusted, !entries.isEmpty else { return }
        if arranging { pendingOrder = true; return }
        guard MenuLayout.requestLayoutAccess() else { error = "Access to the menu layout file is required to reorder icons."; return }
        let restoreCollapsed = collapsed
        var targets = entries.map { LayoutTarget(id: $0.id, name: $0.name, owners: $0.owners.union([$0.id])) }
        targets.append(LayoutTarget(id: Self.ownID, name: "Hidecell", owners: [Self.ownID]))
        arranging = true
        presentationRevision += 1
        let hiddenOwners = restoreCollapsed ? selected : []
        orderMessage = "Applying order…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            Thread.sleep(forTimeInterval: 1)
            let result = MenuLayout.arrange(targets, hiddenOwners: hiddenOwners)
            DispatchQueue.main.async {
                guard let self else { return }
                self.arranging = false
                self.orderMessage = result.message
                self.collapsed = restoreCollapsed
                self.presentationRevision += 1
                self.apply()
                self.error = result.success ? nil : result.message
                self.refresh()
                if self.pendingOrder {
                    self.pendingOrder = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.arrangeIcons() }
                }
            }
        }
    }

    var hasVisibilityChanges: Bool {
        selectionDraft.map { $0 != selected } ?? false
    }

    func isSelected(_ entry: AppEntry) -> Bool {
        !(selectionDraft ?? selected).isDisjoint(with: entry.owners.union([entry.id]))
    }

    func select(_ entry: AppEntry, hidden: Bool) {
        guard !editingOrder, !arranging else { return }
        var draft = selectionDraft ?? selected
        let ids = entry.owners.union([entry.id]).subtracting([Self.ownID])
        if hidden { draft.formUnion(ids) } else { draft.subtract(ids) }
        selectionDraft = draft == selected ? nil : draft
    }

    func cancelVisibilityChanges() {
        selectionDraft = nil
    }

    func saveVisibilityChanges() {
        guard hasVisibilityChanges, let draft = selectionDraft, !arranging else { return }
        presentationRevision += 1
        selected = draft
        selectionDraft = nil
        UserDefaults.standard.set(selected.sorted(), forKey: "hiddenApps")
        apply()
    }

    func toggle() {
        presentationRevision += 1
        collapsed.toggle()
        apply()
        refresh()
    }

    func reveal() {
        visibilityRevision += 1
        STMenuBarShim.invalidate(visibilityToken)
        visibilityToken = nil
        lastAllowed = nil
        busy = false
        onStateChange?()
    }

    func apply() {
        guard !arranging, !clockSuspended, AXIsProcessTrusted() else { return }
        guard collapsed, !selected.isEmpty else { reveal(); return }
        guard STMenuBarShim.isAvailable() else {
            collapsed = false
            reveal()
            error = "Session-only hiding is unavailable on this macOS version. Icons were left visible."
            return
        }
        let allowed = IconPolicy.allowlist(running: runningIdentities(), selected: selected, ownID: Self.ownID)
        guard allowed != lastAllowed else { return }
        reveal()
        visibilityRevision += 1
        let current = visibilityRevision
        busy = true
        error = nil
        visibilityToken = STMenuBarShim.activate(withAllowedBundleIdentifiers: allowed.sorted(),
            allowedSystemItems: (0...255).map { NSNumber(value: $0) }) { [weak self] failure in
            DispatchQueue.main.async {
                guard let self, self.visibilityRevision == current else { return }
                self.busy = false
                if let failure {
                    self.collapsed = false
                    self.reveal()
                    self.error = failure.localizedDescription
                }
                self.onStateChange?()
            }
        } as AnyObject?
        if visibilityToken == nil {
            collapsed = false
            reveal()
            error = "Session-only hiding could not start. Icons were left visible."
        } else { lastAllowed = allowed }
        onStateChange?()
    }

}

struct RowDropDelegate: DropDelegate {
    let id: String
    let model: BarModel
    let reduceMotion: Bool
    func validateDrop(info: DropInfo) -> Bool { model.editingOrder && !model.arranging && model.draggingID != nil }
    func dropEntered(info: DropInfo) {
        guard let source = model.draggingID else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.88)) {
            model.moveEntry(id: source, onto: id)
        }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        model.finishReordering()
        return true
    }
}

struct RowHoverTracker: NSViewRepresentable {
    let id: String
    let model: BarModel
    func makeNSView(context: Context) -> TrackingView { TrackingView() }
    func updateNSView(_ view: TrackingView, context: Context) { view.id = id; view.model = model }
    final class TrackingView: NSView {
        var id = ""
        weak var model: BarModel?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
        }
        override func cursorUpdate(with event: NSEvent) {
            guard let model else { return }
            if model.arranging { NSCursor.arrow.set() }
            else if !model.editingOrder { NSCursor.pointingHand.set() }
            else {
                (NSEvent.pressedMouseButtons & 1 != 0 ? NSCursor.closedHand : NSCursor.openHand).set()
            }
        }
        override func mouseEntered(with event: NSEvent) { model?.updateHover(id); cursorUpdate(with: event) }
        override func mouseMoved(with event: NSEvent) { model?.updateHover(id) }
        override func mouseExited(with event: NSEvent) { if model?.hoveredID == id { model?.updateHover(nil) } }
    }
}

enum BrandTheme {
    static let accent = Color(red: 0.65, green: 0.59, blue: 0.85)
    static let background = Color(red: 0.067, green: 0.071, blue: 0.086)
    static let surface = Color(red: 0.106, green: 0.110, blue: 0.133)
    static let text = Color(red: 0.95, green: 0.95, blue: 0.97)
}

struct BrandToggleStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(LinearGradient(colors: configuration.isOn
                    ? [Color(red: 0.72, green: 0.63, blue: 0.96), Color(red: 0.48, green: 0.37, blue: 0.73)]
                    : [Color(white: 0.22), Color(white: 0.15)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Capsule().fill(LinearGradient(colors: [.white.opacity(0.28), .clear, .black.opacity(0.16)], startPoint: .top, endPoint: .bottom))
                Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.48), BrandTheme.accent.opacity(0.12), .white.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
                Capsule().fill(.white.opacity(configuration.isOn ? 0.32 : 0.10))
                    .frame(width: 22, height: 2).blur(radius: 0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 2)
                Circle().fill(LinearGradient(colors: [.white, Color(red: 0.91, green: 0.87, blue: 0.98), Color(red: 0.72, green: 0.66, blue: 0.84)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 0.65))
                    .overlay(alignment: .topLeading) {
                        Ellipse().fill(.white.opacity(0.9)).frame(width: 9, height: 4)
                            .blur(radius: 0.6).padding(.top, 2).padding(.leading, 3)
                    }
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.38), radius: 2, y: 1)
                    .padding(3)
            }
            .frame(width: 42, height: 24)
            .shadow(color: BrandTheme.accent.opacity(configuration.isOn && enabled ? 0.22 : 0), radius: 4, y: 1)
            .contentShape(Capsule())
            .opacity(enabled ? 1 : 0.4)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
        }
    }
}

struct ReorderPreview: View {
    let entry: AppEntry
    var body: some View {
        HStack(spacing: 12) {
            if let icon = entry.icon {
                Image(nsImage: icon).resizable().frame(width: 32, height: 32)
            }
            Text(entry.name).font(.system(size: 14, weight: .medium)).lineLimit(1)
            Spacer(minLength: 24)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(BrandTheme.accent)
        }
        .padding(.horizontal, 14).frame(width: 280, height: 52)
        .foregroundStyle(BrandTheme.text)
        .background(RoundedRectangle(cornerRadius: 12).fill(BrandTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(BrandTheme.accent.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 5)
        .padding(12)
    }
}

struct DragHandleCursor: NSViewRepresentable {
    var cursor: NSCursor = .openHand
    func makeNSView(context: Context) -> CursorView {
        let view = CursorView()
        view.cursor = cursor
        return view
    }
    func updateNSView(_ view: CursorView, context: Context) {
        view.cursor = cursor
        view.window?.invalidateCursorRects(for: view)
    }
    final class CursorView: NSView {
        var cursor: NSCursor = .openHand
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.cursorUpdate, .mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
        }
        override func cursorUpdate(with event: NSEvent) { cursor.set() }
        override func mouseEntered(with event: NSEvent) { cursor.set() }
        override func mouseMoved(with event: NSEvent) { cursor.set() }
        override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }
        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: cursor)
        }
    }
}

struct OrderDragHandle: ViewModifier {
    let entry: AppEntry
    @ObservedObject var model: BarModel
    @ViewBuilder func body(content: Content) -> some View {
        if model.editingOrder && !model.arranging {
            content.background(DragHandleCursor()).onDrag {
                NSCursor.closedHand.set()
                model.draggingID = entry.id
                return NSItemProvider(object: entry.id as NSString)
            } preview: { ReorderPreview(entry: entry) }
        } else { content }
    }
}

struct ApplicationRow: View {
    @FocusState private var toggleFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let entry: AppEntry
    @ObservedObject var model: BarModel
    var hovered: Bool { model.hoveredID == entry.id }
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Group {
                    if let icon = entry.icon { Image(nsImage: icon).resizable() }
                    else { Image(systemName: "app").resizable() }
                }
                .frame(width: 32, height: 32)
                .opacity(model.editingOrder ? 0 : 1)
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(BrandTheme.accent)
                    .opacity(model.editingOrder ? 1 : 0)
            }
            .frame(width: 32, height: 36)
            .contentShape(Rectangle())
            .help(model.editingOrder ? "Drag to reorder" : entry.name)
            .accessibilityLabel(model.editingOrder ? "Reorder \(entry.name)" : entry.name)
            Text(entry.name).font(.system(size: 14)).lineLimit(1)
            Spacer(minLength: 16)
            Toggle("Hide \(entry.name) icon", isOn: Binding(
                get: { model.isSelected(entry) }, set: { model.select(entry, hidden: $0) }))
                .labelsHidden().toggleStyle(BrandToggleStyle()).disabled(model.editingOrder || model.arranging)
                .focused($toggleFocused)
                .opacity(!model.editingOrder && (hovered || toggleFocused) ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(model.editingOrder)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: toggleFocused)
        }
        .padding(.horizontal, 8).frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 12).fill(hovered ? BrandTheme.accent.opacity(0.10) : .clear))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
        .background(RowHoverTracker(id: entry.id, model: model))
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active:
                model.updateHover(entry.id)
                if model.arranging { NSCursor.arrow.set() }
                else if model.editingOrder {
                    (NSEvent.pressedMouseButtons & 1 != 0 ? NSCursor.closedHand : NSCursor.openHand).set()
                } else { NSCursor.pointingHand.set() }
            case .ended:
                if model.hoveredID == entry.id { model.updateHover(nil) }
                NSCursor.arrow.set()
            }
        }
        .onTapGesture {
            guard !model.editingOrder, !model.arranging else { return }
            model.select(entry, hidden: !model.isSelected(entry))
        }
        .modifier(OrderDragHandle(entry: entry, model: model))
        .onDrop(of: [UTType.text], delegate: RowDropDelegate(id: entry.id, model: model, reduceMotion: reduceMotion))
    }
}

struct ScrollEdges: Equatable {
    let top: Bool
    let bottom: Bool
}

struct HeaderActionStyle: ButtonStyle {
    var emphasized = false
    var iconOnly = true
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("Inter-Regular", size: 14))
            .foregroundStyle(emphasized ? BrandTheme.text : BrandTheme.text.opacity(0.8))
            .padding(.horizontal, iconOnly ? 0 : 12)
            .frame(width: iconOnly ? 32 : nil, height: 32)
            .fixedSize(horizontal: true, vertical: false)
            .background(RoundedRectangle(cornerRadius: 11)
                .fill(emphasized ? BrandTheme.accent.opacity(configuration.isPressed ? 0.32 : 0.19) : BrandTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 11)
                .strokeBorder(BrandTheme.accent.opacity(emphasized ? 0.3 : 0.1), lineWidth: 1))
            .opacity(enabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 11))
            .background(DragHandleCursor(cursor: enabled ? .pointingHand : .arrow))
            .onContinuousHover { phase in
                switch phase {
                case .active: (enabled ? NSCursor.pointingHand : NSCursor.arrow).set()
                case .ended: NSCursor.arrow.set()
                }
            }
    }
}

struct SettingsView: View {
    @ObservedObject var model: BarModel
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func closeSearch() {
        model.search = ""
        searchFocused = false
        model.searchExpanded = false
    }
    var filtered: [AppEntry] {
        model.entries.filter { model.search.isEmpty || $0.name.localizedCaseInsensitiveContains(model.search) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Text(model.editingOrder ? "Order Applications" : "Applications")
                    .font(.custom("InstrumentSerif-Regular", size: 24)).tracking(0.36)
                    .fixedSize()
                Spacer(minLength: 4)
                if model.editingOrder || model.hasVisibilityChanges {
                    Button("Cancel") {
                        if model.editingOrder { model.cancelEditingOrder() }
                        else { model.cancelVisibilityChanges() }
                    }
                        .buttonStyle(HeaderActionStyle(iconOnly: false))
                    Button {
                        if model.editingOrder { model.saveEditingOrder() }
                        else { model.saveVisibilityChanges() }
                    } label: {
                        Label("Save changes", systemImage: "checkmark").fixedSize()
                    }
                        .buttonStyle(HeaderActionStyle(emphasized: true, iconOnly: false))
                        .disabled(!(model.editingOrder ? model.hasOrderChanges : model.hasVisibilityChanges))
                        .help("Save changes")
                        .accessibilityLabel("Save changes")
                } else {
                    ZStack(alignment: .trailing) {
                        HStack(spacing: 8) {
                            TextField("Search apps", text: $model.search).textFieldStyle(.plain)
                                .font(.system(size: 13)).focused($searchFocused)
                                .accessibilityLabel("Search applications")
                                .onExitCommand { closeSearch() }
                            Button { closeSearch() } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain)
                                .background(DragHandleCursor(cursor: .pointingHand)).help("Close search")
                                .accessibilityLabel("Close search")
                        }
                        .padding(.horizontal, 12).frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 11).fill(BrandTheme.surface))
                        .opacity(model.searchExpanded ? 1 : 0)
                        .allowsHitTesting(model.searchExpanded)
                        .accessibilityHidden(!model.searchExpanded)
                        Button {
                            model.searchExpanded = true
                            searchFocused = true
                        } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(HeaderActionStyle()).help("Search applications")
                            .accessibilityLabel("Search applications")
                            .opacity(model.searchExpanded ? 0 : 1)
                            .allowsHitTesting(!model.searchExpanded)
                            .accessibilityHidden(model.searchExpanded)
                    }
                    .frame(width: model.searchExpanded ? 150 : 32, height: 32)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: model.searchExpanded)
                    Button {
                        closeSearch()
                        model.beginEditingOrder()
                    } label: {
                        if model.arranging { ProgressView().controlSize(.small) }
                        else { Label("Order applications", systemImage: "arrow.up.arrow.down").fixedSize() }
                    }
                    .buttonStyle(HeaderActionStyle(emphasized: true, iconOnly: false))
                    .padding(.leading, 8)
                    .help(model.arranging ? "Saving order…" : "Order applications")
                    .accessibilityLabel(model.arranging ? "Saving order" : "Order applications")
                }
            }
            .disabled(!model.trusted || model.arranging)
            .onChange(of: model.hasVisibilityChanges) { _, changed in
                if changed { closeSearch() }
            }
            if !model.trusted {
                VStack(spacing: 12) {
                    Text("Menu icon access").font(.headline)
                    Text("Allow Hidecell in Accessibility to list your menu bar apps.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Open System Settings") { model.requestAccess() }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filtered) { entry in
                            ApplicationRow(entry: entry, model: model)
                        }
                    }.padding(.vertical, 4)
                        .padding(.trailing, 10)
                }
                .onScrollGeometryChange(for: ScrollEdges.self) { geometry in
                    ScrollEdges(
                        top: geometry.contentOffset.y + geometry.contentInsets.top > 1,
                        bottom: geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height + geometry.contentInsets.bottom - 1)
                } action: { _, edges in
                    model.scrollEdges = edges
                }
                .overlay(alignment: .top) {
                    LinearGradient(colors: [BrandTheme.background, BrandTheme.background.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 22).padding(.trailing, 18)
                        .opacity(model.scrollEdges.top ? 1 : 0).allowsHitTesting(false)
                }
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [BrandTheme.background.opacity(0), BrandTheme.background], startPoint: .top, endPoint: .bottom)
                        .frame(height: 22).padding(.trailing, 18)
                        .opacity(model.scrollEdges.bottom ? 1 : 0).allowsHitTesting(false)
                }
                .overlay {
                    if filtered.isEmpty {
                        Text(model.scanning ? "Scanning menu icons…" : (model.search.isEmpty ? "No menu icons found" : "No results"))
                            .foregroundStyle(.secondary)
                    }
                }
                // Extend the hover surface around the aligned content, without
                // changing the icon/text/toggle positions between interaction states.
                .padding(.leading, -8)
                .padding(.trailing, -18)
            }
            if model.arranging {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Applying order…").font(.caption).foregroundStyle(.secondary)
                }
            }
            if model.visibilityNeedsAccess {
                Text("Allow access to macOS menu settings once to hide icons.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Allow Menu Settings Access") { model.grantVisibilityAccess() }
                    .buttonStyle(.borderedProminent)
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .foregroundStyle(BrandTheme.text)
        .tint(BrandTheme.accent)
        .preferredColorScheme(.dark)
        .background(BrandTheme.background)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DesktopView: View {
    @ObservedObject var model: BarModel
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Image(nsImage: MenuBarBrandIcon.image).resizable().frame(width: 26, height: 26)
                Text("Hidecell").font(.custom("InstrumentSerif-Regular", size: 20))
                    .foregroundStyle(BrandTheme.text.opacity(0.85))
            }
            .frame(maxWidth: .infinity).frame(height: 63)
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            SettingsView(model: model)
        }
        .background(BrandTheme.background)
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
        .frame(minWidth: 500, idealWidth: 580, minHeight: 420, idealHeight: 677)
    }
}

enum MenuBarBrandIcon {
    static let image: NSImage = {
        let image = Bundle.main.url(forResource: "Hidecell-Fold-v2", withExtension: "icns")
            .flatMap { NSImage(contentsOf: $0) } ?? NSImage(size: NSSize(width: 22, height: 22))
        image.size = NSSize(width: 22, height: 22)
        image.isTemplate = false
        image.accessibilityDescription = "Hidecell"
        return image
    }()
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = BarModel()
    var status: NSStatusItem!
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        for name in ["InstrumentSerif-Regular", "Inter-Regular"] {
            if let fontURL = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
            }
        }
        if let iconURL = Bundle.main.url(forResource: "Hidecell-Fold-v2", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.autosaveName = "HidecellToggle"
        status.button?.target = self
        status.button?.action = #selector(clicked)
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        model.onStateChange = { [weak self] in self?.updateIcon() }
        updateIcon()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 677),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.delegate = self
        window.title = "Hidecell"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.titlebarSeparatorStyle = .none
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0.067, green: 0.071, blue: 0.086, alpha: 1)
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: DesktopView(model: model))
        window.center()
        window.setFrameAutosaveName("HidecellWindowV7")
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Hidecell", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"),
                                    ("Copy", "copy:", "c"), ("Paste", "paste:", "v"),
                                    ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: NSSelectorFromString(action), keyEquivalent: key)
        }
        editMenu.addItem(.separator())
        let sync = editMenu.addItem(withTitle: "Sync Menu Order", action: #selector(syncOrder), keyEquivalent: "r")
        sync.keyEquivalentModifierMask = [.command, .shift]
        sync.target = self
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApp.windowsMenu = windowMenu
        let helpItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        let export = helpMenu.addItem(withTitle: "Save Diagnostics…", action: #selector(exportDiagnostics), keyEquivalent: "")
        export.target = self
        helpItem.submenu = helpMenu
        mainMenu.addItem(helpItem)
        NSApp.mainMenu = mainMenu
        model.configureLogin()
        model.startHiding()
        let loginLaunch = NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
        if !loginLaunch { showSettings() }
    }
    private func layoutWindowControls() {
        guard let close = window.standardWindowButton(.closeButton),
              let container = close.superview else { return }
        // Keep the native buttons and their behavior, but align them with the 24pt Figma header inset.
        let top = container.frame.maxY
        if container.frame.height < 63 {
            var frame = container.frame
            frame.size.height = 63
            if container.superview?.isFlipped != true { frame.origin.y = top - 63 }
            container.frame = frame
        }
        var x: CGFloat = 24
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(type) else { continue }
            let y = container.isFlipped ? 24 : container.bounds.height - 24 - button.frame.height
            let origin = NSPoint(x: x, y: y)
            if button.frame.origin != origin { button.setFrameOrigin(origin) }
            x += button.frame.width + 8
        }
    }
    // AppKit can reset titlebar geometry after activation; realign after its layout pass.
    func windowDidUpdate(_ notification: Notification) { layoutWindowControls() }
    func windowDidResize(_ notification: Notification) { layoutWindowControls() }
    func windowDidBecomeKey(_ notification: Notification) { layoutWindowControls() }

    func updateIcon() {
        status?.button?.image = MenuBarBrandIcon.image
        status?.button?.toolTip = model.collapsed
            ? "Hidecell · Show hidden icons · Right-click: settings"
            : "Hidecell · Hide selected icons · Right-click: settings"
    }
    @objc func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let settings = menu.addItem(withTitle: "Manage Apps…", action: #selector(showSettings), keyEquivalent: ",")
            settings.target = self
            let toggle = menu.addItem(withTitle: model.collapsed ? "Show All" : "Hide Selected", action: #selector(toggle), keyEquivalent: "")
            toggle.target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Hidecell", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            status.menu = menu
            status.button?.performClick(nil)
            status.menu = nil
        } else if model.selected.isEmpty { showSettings() }
        else { model.toggle() }
    }
    @objc func syncOrder() { model.arrangeIcons() }
    @objc func exportDiagnostics() { model.exportDiagnostics() }
    @objc func toggle() { model.toggle() }
    @objc func showSettings() {
        model.refresh()
        model.refreshLoginStatus()
        window.makeKeyAndOrderFront(nil)
        layoutWindowControls()
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        model.reveal()
    }
}

// Run before NSApplication setup and the single-instance check.
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--visibility-guardian" {
    signal(SIGPIPE, SIG_IGN)
    VisibilityGuardian.run(bundlePath: CommandLine.arguments[2])
}

// Read-only diagnostic mode: no windows, input events or permission prompt.
if CommandLine.arguments.contains("--check-accessibility") {
    print(AXIsProcessTrusted() ? "accessibility=granted" : "accessibility=denied")
    exit(AXIsProcessTrusted() ? 0 : 2)
}

let app = NSApplication.shared
// Never leave a second copy holding a conflicting visibility assertion.
if let other = NSWorkspace.shared.runningApplications.first(where: {
    $0.bundleIdentifier == BarModel.ownID && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
}) {
    other.activate(options: [.activateAllWindows])
    exit(0)
}
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
