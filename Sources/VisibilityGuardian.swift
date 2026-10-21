import Foundation
import Darwin

// The guardian owns all visibility writes. Its in-memory recovery map survives
// removal of the app bundle and preferences. EOF or a missing bundle restores it.
enum VisibilityGuardian {
    private static var stopping: sig_atomic_t = 0
    private static var process: Process?
    private static var input: FileHandle?
    private static var output: FileHandle?

    static func apply(hidden: Set<String>) throws {
        signal(SIGPIPE, SIG_IGN)
        // Never overlap a failed guardian's recovery with another writer.
        if process != nil && (process?.isRunning != true || input == nil) {
            throw NativeVisibility.Failure.guardianUnavailable
        }
        if process == nil {
            guard let executable = Bundle.main.executableURL else { throw NativeVisibility.Failure.guardianUnavailable }
            let child = Process()
            child.executableURL = executable
            child.arguments = ["--visibility-guardian", executable.path]
            let requests = Pipe(), responses = Pipe()
            child.standardInput = requests
            child.standardOutput = responses
            child.standardError = FileHandle.nullDevice
            try child.run()
            requests.fileHandleForReading.closeFile()
            responses.fileHandleForWriting.closeFile()
            process = child
            input = requests.fileHandleForWriting
            output = responses.fileHandleForReading
        }
        guard let input, let output else { throw NativeVisibility.Failure.guardianUnavailable }
        let data = try JSONSerialization.data(withJSONObject: hidden.sorted()) + Data([10])
        try input.write(contentsOf: data)
        var descriptor = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
        guard poll(&descriptor, 1, 10_000) > 0,
              let response = try output.read(upToCount: 1), response == Data([1]) else {
            // Closing the channel triggers recovery; never fall back to unguarded writes.
            try? input.close()
            self.input = nil
            self.output = nil
            throw NativeVisibility.Failure.guardianUnavailable
        }
    }

    static func run(bundlePath: String) -> Never {
        signal(SIGTERM) { _ in VisibilityGuardian.stopping = 1 }
        signal(SIGINT) { _ in VisibilityGuardian.stopping = 1 }
        signal(SIGHUP) { _ in VisibilityGuardian.stopping = 1 }
        let parent = getppid()
        var pending = Data()
        var finished = false
        while !finished && stopping == 0 {
            if getppid() != parent || !FileManager.default.fileExists(atPath: bundlePath) { break }
            var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN | POLLHUP), revents: 0)
            let ready = poll(&descriptor, 1, 500)
            if ready < 0 { if errno == EINTR { continue }; break }
            if ready == 0 { continue }
            var bytes = [UInt8](repeating: 0, count: 4096)
            let count = read(STDIN_FILENO, &bytes, bytes.count)
            if count <= 0 { break }
            pending.append(contentsOf: bytes.prefix(count))
            if pending.count > 1_048_576 { break }
            while let end = pending.firstIndex(of: 10) {
                let command = Data(pending[..<end])
                pending.removeSubrange(...end)
                do {
                    guard let ids = try JSONSerialization.jsonObject(with: command) as? [String] else {
                        throw NativeVisibility.Failure.invalidFormat
                    }
                    // Check again immediately before any write after a removal.
                    guard FileManager.default.fileExists(atPath: bundlePath) else { finished = true; break }
                    try NativeVisibility.applyDirect(hidden: Set(ids))
                    var success: UInt8 = 1
                    _ = write(STDOUT_FILENO, &success, 1)
                } catch {
                    var failure: UInt8 = 0
                    _ = write(STDOUT_FILENO, &failure, 1)
                    finished = true
                    break
                }
            }
        }
        // Retry temporary preference-service failures without requiring the UI app.
        for attempt in 0..<30 {
            do { try NativeVisibility.applyDirect(hidden: []); exit(0) }
            catch { if attempt < 29 { sleep(1) } }
        }
        exit(1)
    }
}
