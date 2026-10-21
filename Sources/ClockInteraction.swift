import AppKit

// Assessment assertions also suppress the native clock action. Release the
// assertion before forwarding that exact click, then wait for the panel to close.
final class ClockInteraction {
    var reveal: (() -> Void)?
    var resume: (() -> Void)?
    var isHidden: (() -> Bool)?
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var clockFrame: CGRect?
    private var suspendedAt: Date?
    private var sawPanel = false
    private var swallowUp = false
    private let marker: Int64 = 0x48494445

    func start() {
        let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: CGEventMask(mask), callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return Unmanaged<ClockInteraction>.fromOpaque(context).takeUnretainedValue().handle(type, event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let port {
            source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == marker { return Unmanaged.passUnretained(event) }
        if type == .leftMouseUp && swallowUp { swallowUp = false; return nil }
        guard type == .leftMouseDown, suspendedAt == nil, isHidden?() == true,
              clockFrame?.contains(event.location) == true else { return Unmanaged.passUnretained(event) }
        suspendedAt = Date()
        sawPanel = false
        swallowUp = true
        reveal?()
        let point = event.location
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            for kind in [CGEventType.leftMouseDown, .leftMouseUp] {
                let copy = CGEvent(mouseEventSource: nil, mouseType: kind, mouseCursorPosition: point, mouseButton: .left)
                copy?.setIntegerValueField(.eventSourceUserData, value: self.marker)
                copy?.post(tap: .cghidEventTap)
            }
        }
        return nil
    }

    private func tick() {
        if clockFrame == nil {
            clockFrame = MenuLayout.systemItems().first { $0.key == "com.apple.menuextra.clock" }?.frame
        }
        guard let since = suspendedAt else { return }
        let pid = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.notificationcenterui" }?.processIdentifier
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let panel = windows.contains { row in
            guard let pid, (row[kCGWindowOwnerPID as String] as? Int32) == pid,
                  let bounds = row[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return false }
            return frame.width > 200 && frame.height > 200
        }
        if panel { sawPanel = true }
        if !panel && (sawPanel || Date().timeIntervalSince(since) > 3) {
            suspendedAt = nil
            clockFrame = nil
            resume?()
        }
    }
}
