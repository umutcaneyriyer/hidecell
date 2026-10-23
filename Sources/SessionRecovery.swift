import AppKit
import Darwin

// A launchd-owned recovery job survives the app and is restarted after a crash.
// It exists only for this hiding session, not as a login item.
enum SessionRecovery {
    private static var prepared = false
    #if RECOVERY_TESTING
    private static let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HIDECELL_TEST_DOMAIN"]! + ".session")
    private static let label = "app.hidecell.recovery-test"
    #else
    private static let root = FileManager.default.temporaryDirectory.appendingPathComponent("HidecellRecoverySession", isDirectory: true)
    private static let label = "app.hidecell.session-recovery"
    #endif

    private static func launchctl(_ arguments: [String]) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw NativeVisibility.Failure.guardianUnavailable }
    }

    static func apply(hidden: Set<String>) throws {
        if !prepared {
            guard !hidden.isEmpty else { return }
            try prepare()
        }
        // Do not hide anything after the executable was removed.
        guard let executable = Bundle.main.executableURL,
              FileManager.default.fileExists(atPath: executable.path) else {
            try NativeVisibility.applyDirect(hidden: [])
            return
        }
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("ready").path) else {
            throw NativeVisibility.Failure.guardianUnavailable
        }
        try NativeVisibility.applyDirect(hidden: hidden)
    }

    private static func prepare() throws {
        let fm = FileManager.default
        // A previous recovery must finish before a new writer can start.
        let deadline = Date().addingTimeInterval(8)
        while fm.fileExists(atPath: root.path) && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        guard !fm.fileExists(atPath: root.path), let executable = Bundle.main.executableURL else {
            throw NativeVisibility.Failure.guardianUnavailable
        }
        try fm.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let helper = root.appendingPathComponent("HidecellRecovery")
        let journal = root.appendingPathComponent("originals.plist")
        let plist = root.appendingPathComponent("job.plist")
        do {
            try fm.copyItem(at: executable, to: helper)
            NativeVisibility.recoveryJournal = journal
            try NativeVisibility.saveRecoveryJournal()
            var job: [String: Any] = [
                "Label": label,
                "ProgramArguments": [helper.path, "--session-recovery", String(getpid()), executable.path, root.path],
                "RunAtLoad": true,
                "KeepAlive": ["SuccessfulExit": false],
                "ThrottleInterval": 1,
                "ProcessType": "Background"
            ]
            #if RECOVERY_TESTING
            job["EnvironmentVariables"] = ["HIDECELL_TEST_DOMAIN": ProcessInfo.processInfo.environment["HIDECELL_TEST_DOMAIN"]!]
            #endif
            try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0).write(to: plist, options: .atomic)
            try launchctl(["bootstrap", "gui/\(getuid())", plist.path])
            let ready = root.appendingPathComponent("ready")
            let deadline = Date().addingTimeInterval(5)
            while !fm.fileExists(atPath: ready.path) && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
            guard fm.fileExists(atPath: ready.path) else { throw NativeVisibility.Failure.guardianUnavailable }
            prepared = true
        } catch {
            // No visibility write has occurred until prepare succeeds.
            try? launchctl(["bootout", "gui/\(getuid())/\(label)"])
            try? fm.removeItem(at: root)
            NativeVisibility.recoveryJournal = nil
            throw error
        }
    }

    static func run(parent: pid_t, executable: String, directory: String) -> Never {
        let directory = URL(fileURLWithPath: directory, isDirectory: true)
        NativeVisibility.recoveryJournal = directory.appendingPathComponent("originals.plist")
        // Verify recovery access before allowing the app's first write.
        guard (try? NativeVisibility.inventory()) != nil else { exit(1) }
        do { try Data().write(to: directory.appendingPathComponent("ready"), options: .atomic) }
        catch { exit(1) }
        while kill(parent, 0) == 0 && FileManager.default.fileExists(atPath: executable) {
            Thread.sleep(forTimeInterval: 0.25)
        }
        // Stop the writer before restoration when an uninstaller removes the bundle.
        // Otherwise an in-flight hide could overwrite the recovered state.
        if kill(parent, 0) == 0 {
            kill(parent, SIGTERM)
            let deadline = Date().addingTimeInterval(2)
            while kill(parent, 0) == 0 && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
            if kill(parent, 0) == 0 { kill(parent, SIGKILL) }
            while kill(parent, 0) == 0 { Thread.sleep(forTimeInterval: 0.05) }
        }
        do { try NativeVisibility.applyDirect(hidden: []) }
        catch { exit(1) } // launchd retries using the durable journal.
        try? FileManager.default.removeItem(at: directory)
        let remove = Process()
        remove.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        remove.arguments = ["remove", label]
        try? remove.run()
        exit(0)
    }
}
